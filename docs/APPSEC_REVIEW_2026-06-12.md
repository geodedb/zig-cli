# Application Security Code Review (Iteration 2) — devnw/zig/cli

**Reviewer:** AppSec code review (defensive, evidence-first)
**Date:** 2026-06-12
**Frameworks:** OWASP Top 10:2025, CIS Controls v8.1.2
**Commit context:** branch `main`, HEAD `3e2d804` ("Merge branch 'refactor/audit-iter1'")
**Type:** Re-review after two fix batches (`188bf5a` audit-iteration-1 merge) and a large refactor/file-split (`3e2d804`)

---

## 1. Scope & Assumptions

### In scope (read directly from the working tree at `3e2d804`)

- **Shared sanitizer (new named module):** `src/sanitize.zig`, wired in `build.zig:60-72,88,96,119`
- **Parser pipeline (decomposed):** `src/cli/parser.zig`, `src/cli/parser/env.zig`, `src/cli/parser/format.zig`
- **Context / flag specs (extracted):** `src/cli/context.zig`, `src/cli/command.zig`
- **Help generators (split):** `src/cli/help.zig` (coordinator) + `src/cli/help/{common,text,markdown,man,json}.zig`
- **Completion generators:** `src/cli/completion/{bash,zsh,fish,powershell}.zig`
- **Terminal:** `src/term/{color,progress,table,pager,tty,env}.zig`
- **Prompts (split):** `src/prompt.zig`, `src/prompt/select.zig`
- **Errors / text / fs:** `src/util/{errors,text,fs,suggest}.zig`
- **Build/CI:** `build.zig`, `build.zig.zon`, `.gitlab-ci.yml`
- **Prior docs (treated as untrusted, re-verified against code):** `docs/APPSEC_REVIEW_2026-06-11.md` (F-01..F-10), `docs/SECURITY_GAP_ANALYSIS.md` (0 open)

### Verification performed

- Each prior finding F-01..F-08 was re-derived from current code with `file:line` + quoted evidence; the file splits relocated code, so each fix was confirmed to have survived relocation rather than trusting the gap doc.
- `zig build test` (zig 0.16.0): exit 0, all suites pass — confirms the new module boundaries compile and the regression tests pass.
- Exhaustive `{s}`/`{c}` interpolation sweeps over the completion and help subsystems, with load-bearing claims independently verified.

### Out of scope / not verifiable here

- External `config` dependency (`gitlab.com/devnw/zig/config.git`) — still a re-export shim (`src/config.zig`); config path resolution / deserialization / dotenv / secret-file reading remain unaudited (F-10, unchanged).
- `thread_pool` dependency internals.
- No dynamic analysis / fuzzing; ReleaseFast OOB reasoning is static.
- Windows console paths read but not executed.

### Trust model (unchanged from iter-1)

Library, not a service. Realistic attackers: (1) a consumer building `Command`/`FlagSpec` trees from untrusted/dynamic metadata then generating completions/man/markdown or rendering help to a TTY; (2) a local user controlling argv/env/stdin; (3) the supply chain. Command/flag/subcommand `name`/`help`/`summary` are runtime `[]const u8`, not comptime-constrained, so output-encoding correctness matters for profile (1).

---

## 2. Executive Summary

- **All eight prior code findings (F-01..F-08) are genuinely fixed in the current code, and every fix survived the file splits.** Control-byte sanitization is now centralized in one named module (`src/sanitize.zig`) and correctly applied on the live TTY paths (color, progress, table, plain-text help, unknown-command formatting). Call-site parity was confirmed against the pre-split monolith for the help subsystem (sanitization-site counts match exactly: 22 control-filter sites in text, 19 roff, 19 JSON, plus the markdown heading/prose/fence escapers) — **no sanitization site was lost in the move.** Completion hardening (PowerShell `-CommandName`, zsh identifier/case-label sanitizers, fish depth cap) is present and tested. F-02/NS-016 is correctly remediated by doc correction + a `secureZero`-based `freeSecret` helper. F-07/F-08 (fs helpers) are documentation-scoped as agreed.

- **One genuine NEW finding (Low–Medium, live-by-default for affected consumers): N-01 — the `.only_valid` positional-args validator echoes a raw, attacker-controlled positional into a stderr error message with no control-byte filter.** `ArgsErrorDetails.invalid_arg` captures the user's positional (`command.zig:153`) and `format.zig:91-93` prints it via `bufPrint("invalid argument: '{s}'", .{a})` straight to stderr in the default `run()` error path — bypassing `sanitize`. This is the exact CWE-150 class NS-056 was meant to close "live by default," and it slipped through the validator→format→stderr chain.

- **One documentation-accuracy NEW finding (Info): N-02 — the gap doc's claim that NS-056 is "live by default via the unknown-command path" no longer matches the wired code.** The default `run()` error renderer (`format.zig:23`) prints a static `"Error: Unknown command"` and never echoes argv; `formatUnknownCommand` (the function whose `stripControlChars` call the gap doc cites as the live fix, `errors.zig:110`) has **no production caller** (only tests). The fix itself is correct and safe for any consumer that calls it; the live default path is safe precisely because it does not echo. The doc overstates which path is "live."

- **Two small completion asymmetries (Low/Info): N-03 — bash registers `complete -F _name {raw cmd.name}` (`bash.zig:147`) with the command-name argument unescaped/unquoted**, while the other three generators harden their registration line; **N-04 — header `#` comment lines in bash/fish/powershell interpolate names/paths raw without newline stripping**, while zsh's header is newline-safe via `writeControlFiltered`. Both bounded by `cmd.name` being developer-controlled in the common case.

- **The pager migration to `std.process.spawn` is safe.** Direct `argv` exec (no shell), 8-token cap, and direct-output fallback on spawn failure, stdin-write failure, `wait` failure, or nonzero pager exit (`pager.zig:84-126`). Shell metacharacters in `PAGER` are not interpreted.

- **The decomposed `parse()` pipeline is sound.** Token-boundary index math is bounds-checked before every value consume (`parser.zig:269,307`), the phase split (`handleLongToken`/`handleShortToken`/`handlePlainToken` → `finalize`) preserves the secret policy on all three channels, and per-parse diagnostic state is reset (`resetErrorState`, `parser.zig:133`).

**Overall confidence: High** for `src/` and build/CI. **Low** for config-file handling (external dependency). **Bottom line on "is it safe to ship?":** Yes for the intended use. The residual findings are Low/Info and conditioned on either a consumer using `.only_valid` with untrusted argv (N-01) or building command trees from untrusted names (N-03/N-04).

---

## 3. Findings Table

### Prior findings — verification status

| ID | Prior Severity | Status now | Evidence (current code) |
|----|----------------|------------|--------------------------|
| F-01 / NS-056 | Medium | **FIXED (verified)** | `sanitize.writeControlFiltered` applied: `color.zig:95,98,107,110`; `progress.zig:132,159,272`; `table.zig:263,270,275,281`; plain-text help all 22 sites filtered (`help/text.zig`); unknown-command `errors.zig:110` |
| F-02 / NS-016 | Low | **FIXED (verified, doc remediation)** | `context.zig:42-46,188-200` now state argv/environ bytes are NOT scrubbed; `prompt.zig:288-292` `freeSecret` uses `std.crypto.secureZero` |
| F-03 / NS-060 | Low | **FIXED (verified)** | `help/markdown.zig:62` `writeMarkdownHeading`, `:86` `writeMarkdownProse`, `:112` `writeFenceSafe`; applied `:136,140,146,156,165,219`; fence-breakout test `:660` |
| F-04 / NS-061 | Low | **FIXED (verified)** | `powershell.zig:34-35` `cmd.name` wrapped in `escapePowerShellString`; escaper strips NUL/CR/LF `:197` |
| F-05 / NS-061 | Low | **FIXED (verified)** | `zsh.zig:128` `sanitizeZshIdentifier` (function ids `:244,292,297`); case label single-quote-escaped `:295-296` |
| F-06 / NS-061 | Low | **FIXED (verified)** | `fish.zig:181` `if (path.len >= max_depth) break;` precedes array decl `:183` and writes `:185-189`; `max_depth=16` |
| F-07 | Low | **Open (doc-scoped, as agreed)** | `fs.zig` `isSafePath` remains advisory denylist — documented Won't-Do |
| F-08 | Low | **Open (doc-scoped, as agreed)** | `fs.zig` `writeFileAtomic` not dir-fd-anchored — hardening, documented |
| F-09 / NS-001 | Info | **Accepted risk (unchanged)** | `.gitlab-ci.yml` CI components tag-pinned |
| F-10 | Info | **Coverage gap (unchanged)** | `config.zig` re-export shim; external dep unaudited |

### New findings (this iteration)

| ID | Severity | Confidence | Title | Location | OWASP 2025 | Status |
|----|----------|------------|-------|----------|------------|--------|
| N-01 | Low–Medium | High | `.only_valid` args validator echoes raw attacker positional to stderr with no control-byte filter | `command.zig:153,69`, `parser/format.zig:91-93` | A05 Injection | New (untracked) |
| N-02 | Info | High | NS-056 "live by default via unknown-command path" doc claim no longer matches code; `formatUnknownCommand` has no production caller | `parser/format.zig:23`, `util/errors.zig:105` | A09 Logging/A05 | New (doc accuracy) |
| N-03 | Low | High | bash `complete -F _name {raw cmd.name}` — registration target unescaped (asymmetric vs. other 3 generators) | `cli/completion/bash.zig:147` | A05 Injection | New |
| N-04 | Low | Medium | Header `#`-comment lines interpolate names/paths raw without newline stripping (bash/fish/powershell) | `bash.zig:114`, `fish.zig:66,92,94,152,154`, `powershell.zig:26` | A05 Injection | New |

No Critical or High findings.

---

## 4. Finding Details

### N-01 — `.only_valid` args validator echoes a raw attacker positional to stderr (Low–Medium)

**OWASP A05 Injection · CWE-150 · CIS 16.11**

**Evidence.** The `.only_valid` positional validator captures the user-supplied positional verbatim (`src/cli/command.zig:143-154`, `return ArgsErrorDetails{ .invalid_arg = arg };`). `format()` writes it with no control filtering (`command.zig:69`: `std.fmt.bufPrint(buf, "invalid argument: '{s}'", .{a})`), and the default `run()` error path prints that buffer straight to stderr (`parser/format.zig:91-93`). Unlike the color/progress/table/help paths, this chain never routes through `sanitize.writeControlFiltered`/`stripControlChars`.

**Attack scenario.** A CLI defines `.args = .{ .only_valid = &.{"start","stop"} }`. A local user runs `myapp svc $'\x1b[2J\x1b[1;1HEnter password:'`. The validator rejects the argument and the raw ESC bytes are echoed to the terminal — screen clear + cursor reposition to spoof a prompt.

**Impact.** Terminal spoofing / output forgery; live by default for any consumer using `.only_valid`; triggering value is runtime argv.

**Remediation.** Control-filter the positional before it reaches the message (filter `.invalid_arg` into the buffer dropping `sanitize.isTerminalControl` bytes, or `stripControlChars` in `format.zig`).

**Regression test.** Parse `["app","sub","\x1b[2Jx"]` against an `.only_valid` command; assert rendered stderr contains no `0x1b` byte and still reports `invalid argument`.

---

### N-02 — NS-056 "live by default" doc claim no longer matches wired code (Info)

**CWE-1059 (Incomplete Documentation)**

**Evidence.** `docs/SECURITY_GAP_ANALYSIS.md:171,184` state NS-056 is "live by default via the unknown-command path" citing `errors.zig:110`. In current code the default error renderer prints a static `"Error: Unknown command"` (`parser/format.zig:23`) and never echoes argv; `formatUnknownCommand` has no production caller (definition + tests only).

**Impact.** None on safety; the doc overstates which path is live. The genuinely live echo path is N-01.

**Remediation.** Update the NS-056 note; decide whether to wire `formatUnknownCommand` into the default path (to surface "did you mean" suggestions) or keep it a consumer-only helper.

---

### N-03 — bash `complete -F _name {raw cmd.name}` registration target unescaped (Low)

**CWE-78 / CWE-94**

**Evidence.** `bash.zig:147`: `try w.print("complete -F _{s} {s}\n", .{ safe_name, cmd.name });` — the function identifier is sanitized but the registration target is the raw name. The other three generators harden their registration line (powershell.zig:35, fish.zig:73, zsh.zig:160).

**Remediation.** Escape/quote the registration target. Test: `cmd.name = "a b;c"` → no bare `;`/unquoted space in the `complete -F` line.

---

### N-04 — Header `#`-comment lines interpolate names/paths raw without newline stripping (Low)

**CWE-116**

**Evidence.** `bash.zig:114`, `fish.zig:66,92,94,152,154`, `powershell.zig:26` print names/path elements into `#` comments with raw `{s}`. zsh alone routes its header through `sanitize.writeControlFiltered` (`zsh.zig:160,163`). A name with an embedded newline terminates the comment and injects a live script line.

**Remediation.** Route comment-line interpolations through `sanitize.writeControlFiltered` in bash/fish/powershell. Test: `cmd.name = "a\necho injected"` → no line begins with `echo injected`.

---

## 5. Secure Design Notes (positive controls verified in current code)

1. **Single-source sanitizer, correctly modularized.** `src/sanitize.zig` is a named build module imported by `cli`/`term`/`util`/`root` and all test modules; no file-path imports remain. `util/text.zig:16-18` re-exports it as the documented public path (matching `SECURITY.md`).
2. **Pager uses direct `argv` spawn, never a shell** (`pager.zig:85`), with direct-output fallback on every failure mode (`pager.zig:90-126`).
3. **Decomposed `parse()` preserves the secret policy on all three channels** (`parser.zig:391-393`, `parser/env.zig:81,128`, `parser.zig:367`); per-parse diagnostic state reset (`parser.zig:133`).
4. **Token index math is bounds-safe** (`parser.zig:244-282,269,307`).
5. **NS-058 underflow fixed:** saturating `term_width -| 20` (`progress.zig:169`).
6. **NS-062 UTF-8 safety:** `utf8FloorIndex` (`sanitize.zig:69`) applied in table truncation and `text.truncate`.
7. **NS-059 Windows password:** both console-mode failure branches return `NotInteractive` (`prompt.zig:235-238,247-249`); POSIX zeroes the line buffer.
8. **No format-string injection:** every `print`/`bufPrint` uses a comptime literal format.
9. **Help re-exports intact after the split;** format escapers are private so callers cannot bypass escaping.

---

## 6. Coverage Gaps & Questions

1. **External `config` dependency (largest gap, unchanged; F-10).** Separate review still required.
2. **No dynamic analysis.** A fuzz job exercising the parser with `.only_valid` validators and metacharacter/over-deep names would raise confidence.
3. **Question — N-01 scope:** bring the positional-args error path under the same `sanitize` policy as term/help paths? It is the one remaining runtime-argv echo on the default `run()` error path.
4. **Question — N-02 intent:** wire `formatUnknownCommand` into the default path, or keep as consumer-only helper (then fix the doc and consider removing the dead helper)?
5. **`prompt/select.zig`:** option labels and prompt messages emitted raw — developer-authored metadata per the documented trust contract; coverage observation, not a finding.
6. **Windows-specific paths** read but not executed.

---

## 7. Prioritized Next Actions

1. **(Low–Medium) N-01 — Route the `.only_valid` `invalid_arg` value through `sanitize`** before stderr printing.
2. **(Info, doc) N-02 — Correct the NS-056 "live by default" claim**; decide wire-or-keep for `formatUnknownCommand`.
3. **(Low, quick) N-03 — Escape/quote the bash `complete -F … {cmd.name}` registration target.**
4. **(Low) N-04 — Route bash/fish/powershell header comments through `writeControlFiltered`.**
5. **(No action) F-01..F-06 verified intact; F-07/F-08 doc-scoped; F-09/F-10 unchanged.**
6. **(Coverage) F-10 — separate appsec review of the external `config` dependency.**

---

*No product code was modified. All findings cite `file:line` with quoted code; uncertain items are questions in §6. The two fix batches and the file splits preserved every prior mitigation; the only new findings are one untracked low-severity escape-echo on the args-validation error path (N-01), a documentation-accuracy correction (N-02), and two low-severity completion-generator asymmetries (N-03/N-04).*
