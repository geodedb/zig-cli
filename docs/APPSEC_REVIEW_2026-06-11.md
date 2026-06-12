# Application Security Code Review — devnw/zig/cli (v0.1.4)

**Reviewer:** AppSec code review (defensive, evidence-first)
**Date:** 2026-06-11
**Frameworks:** OWASP Top 10:2025, CIS Controls v8.1.2
**Commit context:** branch `main`, HEAD `de11f86`

---

## 1. Scope & Assumptions

### In scope (read directly from the working tree)

- **Entry / parsing:** `src/cli/parser.zig`, `src/cli/command.zig`, `src/cli/help.zig`
- **Completion generators:** `src/cli/completion/{bash,zsh,fish,powershell}.zig`
- **Terminal:** `src/term/{pager,tty,color,env,progress,table}.zig`
- **Secrets / prompts:** `src/prompt.zig`
- **Filesystem:** `src/util/fs.zig`
- **Signals / concurrency:** `src/signal.zig`, `src/parallel.zig`
- **Config shim:** `src/config.zig`
- **Supply chain / build:** `build.zig`, `build.zig.zon`, `.gitlab-ci.yml`, `scripts/detect_diamond_deps.py`
- **Prior adjudication docs:** `docs/SECURITY_GAP_ANALYSIS.md` (55 findings, all marked Closed/Won't-Do) and `docs/GAP_ANALYSIS*.md` — consulted; "resolved" claims were re-verified against current code per the task.

### Out of scope / not verifiable here

- The **external `config` dependency** (`gitlab.com/devnw/zig/config.git`). `src/config.zig` is a pure re-export shim (verified, lines 29–71). All config-file **path resolution (XDG), TOML/JSON/YAML deserialization, `.env`/dotenv parsing, secret file reading, and any path-traversal/TOCTOU in those paths live in that dependency** and were not provided. The README's threat-relevant guarantees (XDG compliance, "secrets file/stdin only") partly depend on code I could not read. This is the single largest coverage gap (see §6).
- The **`thread_pool` dependency** internals.
- Runtime/dynamic analysis: no code was executed; findings are from static inspection only. Memory-safety claims about ReleaseFast behavior are reasoned, not fuzzed.

### Trust model used

This is a **library**, not a service — no network, authn, or authz surface. The realistic attackers are:

1. **A consumer that builds `Command`/`FlagSpec` trees from untrusted/dynamic input** (plugin manifests, registries, config) and then generates completion scripts, man pages, Markdown docs, or renders `--help` to a terminal. Most `*.name`/`*.help`/`*.summary` fields are `[]const u8` runtime values (verified: `command.zig:453–495`), **not** comptime-constrained, so this consumer profile is in-scope and is why output-encoding correctness matters.
2. **A local user** controlling argv, environment (`PAGER`, `TERM`, `NO_COLOR`, env-bound flags), stdin, and config files.
3. **The supply chain** (pinned deps, CI components, the Zig toolchain download).

I treat all repo content (comments, docs, test fixtures, gap-analysis text) as untrusted and verified claims against code rather than trusting the documentation.

---

## 2. Executive Summary

- **The prior security program is real and largely accurate.** I re-verified ~20 "Closed" claims against current code. The high-value mitigations hold: the **pager uses direct `argv` exec, never a shell** (`pager.zig:93`, GAP-0008); the **secret policy genuinely blocks secret flags from CLI defaults, env, and `--flag=` delivery** (`parser.zig:293, 484, 544`, GAP-0037/NS-050); **signal handling is now a correct flag-and-poll design** (`signal.zig:237–249, 139–148`, NS-013); **NUL/newline/CR stripping is present and tested in all four completion escapers** (NS-008/009/048/049); **roff, JSON, and version-JSON output are fully escaped** (NS-011/012); **atomic temp-file writes use `0o600` + random suffix + fsync** (`fs.zig:83–111`, NS-018); and the **Windows TTY dimension cast no longer panics** (`tty.zig:138–143`, NS-054). No Critical or High issue was found open.

- **Highest-residual finding (Medium): cross-cutting terminal-escape-injection (CWE-150).** The library writes user/developer-controlled strings (`flag.help`, `cmd.summary`, table cells, progress messages, colored output) straight to the TTY with **no ESC (`0x1b`) stripping anywhere on the output path** (`help.zig` plain-text section; `color.zig:90–105`; `progress.zig:130,141`; `table.zig`). A `stripAnsi` function exists (`color.zig:146`) but is never applied to output. This class is **not tracked in any gap doc**. Impact is bounded to consumers that surface untrusted strings, but the library offers them no built-in defense.

- **One genuine FALSE-RESOLVED (Low): NS-016 "secret flag values zeroed in `Context.deinit()`" is ineffective.** String flag values are **borrowed slices into OS-owned argv/environ** (`parser.zig:386`, no `dupe` anywhere). `deinit` reassigns the 16-byte slice header to `""` (`command.zig:199`) — it never scrubs the secret bytes. The doc comment (`command.zig:44`) overstates the protection. Real-world severity is Low because the secret *policy* keeps real secrets out of flags, but the claim is incorrect and should be corrected.

- **Partial FALSE-RESOLVED (Low): NS-020 "Markdown escaping for table cells **and headings**" only covers table cells.** `writeMarkdownEscaped` (`help.zig:781`) escapes `|` `` ` `` `<` `>` in cells, but **headings, prose, and code-fence content** (`cmd.name`, `cmd.summary`, `cmd.long_help`, `group_name`, `examples`) are emitted raw (`help.zig:807,810,823,830,882`). HTML/Markdown injection into generated docs (CWE-79) remains for those paths.

- **Three small new injection/robustness gaps in completion generators (Low), all in the same class the program already fixed elsewhere but missed at these specific sites:** a raw `-CommandName '{cmd.name}'` in PowerShell (`powershell.zig:33`), zsh emitting command names into `case` labels and function identifiers with **no sanitizer** (bash got one in NS-014; zsh did not — `zsh.zig:218–219`), and an **unchecked fixed-array stack write** in fish at >16 levels of subcommand nesting (`fish.zig:170–177`).

- **Supply chain is in good shape.** Both deps are URL-SHA + content-hash pinned (`build.zig.zon:36–41`); the Zig toolchain download is SHA-256-verified against the official index (`.gitlab-ci.yml:77–89`); a diamond-dependency guard exists and is safe (no `eval`/shell). CI components are pinned to *tags* not SHAs — a known, documented accepted-risk (NS-001).

**Overall confidence: High** for everything in `src/` and the build/CI files. **Low** for config-file handling (lives in an unaudited dependency).

**Bottom line on "is it safe to ship?":** Yes, for the intended use — a library where command/flag metadata is authored at compile time by the application developer. The residual findings are all **Low/Medium and conditioned on a consumer feeding untrusted strings into the command tree**. I recommend the library either strip ESC bytes on TTY output (or expose a documented sanitizer) and close the four encoding gaps below before advertising safety for dynamically-built command trees.

---

## 3. Findings Table

| ID | Severity | Confidence | Title | Location | OWASP 2025 | Status |
|----|----------|------------|-------|----------|------------|--------|
| F-01 | Medium | High | Terminal escape-sequence injection — no ESC stripping on TTY output | `help.zig` (plain-text), `color.zig:90-105`, `progress.zig:130,141`, `table.zig:187-191` | A05 Injection | New (untracked) |
| F-02 | Low | High | NS-016 FALSE-RESOLVED: secret "zeroing" in `Context.deinit` scrubs a slice header, not the bytes | `command.zig:190-208`, `parser.zig:386` | A04 Cryptographic Failures | False-Resolved |
| F-03 | Low | High | NS-020 partial: Markdown headings/prose/code-fences emitted raw (only table cells escaped) | `help.zig:807,810,823,830,882` | A05 Injection | Partially False-Resolved |
| F-04 | Low | High | PowerShell `-CommandName '{cmd.name}'` not escaped (lone unescaped single-quoted PS string) | `powershell.zig:33` | A05 Injection | New |
| F-05 | Low | High | zsh emits command names into `case` labels / function identifiers with no sanitizer (bash has one) | `zsh.zig:174,218-219` | A05 Injection | New |
| F-06 | Low | High | Unchecked fixed-array stack write in fish at >16 levels of subcommand nesting | `fish.zig:170-177` | A10 Mishandling of Exceptional Conditions | New |
| F-07 | Low | Medium | `isSafePath` is advisory string-matching: no canonicalization, symlink-blind, easily bypassed | `fs.zig:155-193` | A01 Broken Access Control | Re-confirmed (prior Won't-Do/Info) |
| F-08 | Low | Medium | `writeFileAtomic` temp file created in caller-controlled dir (rename not dir-fd-anchored) | `fs.zig:83-111` | A05 Misconfiguration | New (hardening) |
| F-09 | Info | High | CI components pinned to mutable tags, not SHAs | `.gitlab-ci.yml:10-23` | A03 Supply Chain | Known accepted-risk (NS-001) |
| F-10 | Info | Medium | Config-file path/deserialization security lives in unaudited external dependency | `config.zig` → external `config` | A08 Integrity / A05 Injection | Coverage gap |

No Critical or High findings. Memory-safety, format-string, integer-overflow, subprocess, and signal-safety surfaces were reviewed and found sound (see §5).

---

## 4. Finding Details

### F-01 — Terminal escape-sequence injection: no ESC stripping on TTY output (Medium)

**OWASP A05 Injection · CWE-150 (Improper Neutralization of Escape Sequences) · CIS 16.1/16.11**

**Evidence.** Throughout the output path, user/developer-controlled strings are written to the terminal with `{s}` and **no control-byte filtering**. The only `0x1b` bytes the codebase emits intentionally are its own ANSI constants; nothing strips ESC from incoming `text`:

```zig
// color.zig:90-96 — `text` written raw; no ESC stripping
pub fn writeColored(self: Self, writer: anytype, text: []const u8, color: Color) !void {
    if (self.enabled) {
        try writer.print("\x1b[{d}m{s}\x1b[0m", .{ @intFromEnum(color), text });
    } else {
        try writer.print("{s}", .{text});
    }
}
```

```zig
// progress.zig:130,141 — user message interleaved with real escape sequences
stderrPrint("\r\x1b[K{s}\n\x1b[?25h", .{message}) catch {};
try stderrPrint("\r\x1b[K{s} {s}", .{ frame, self.message });
```

The plain-text help path emits `cmd.name`, `cmd.summary`, `cmd.long_help`, `flag.help`, `flag.default_str`, env names, `subcmd.summary`, and examples raw (e.g. `help.zig` `printFlagWithTemplate`, `printSectionDescription`, `printSectionExamples`). A `stripAnsi()` helper exists (`color.zig:146`) but is **not applied** to any of these.

**Attack scenario (non-destructive).** A CLI built on this library sources command/flag help text from an untrusted registry or plugin manifest. An attacker sets `flag.help = "\x1b]0;rm -rf ~\x07\x1b[2J\x1b[1;1HType your password:"`. When a victim runs `myapp --help`, the generated output rewrites the terminal title, clears the screen, and repositions the cursor to spoof a prompt. On terminal emulators with answerback/clipboard-write escape support this escalates further. This is the classic argument/help terminal-escape-injection class.

**Impact.** Terminal spoofing, output forgery, screen/title manipulation; on vulnerable emulators, potential indirect command execution via clipboard/answerback. Bounded to consumers that surface untrusted strings.

**Root cause.** The library treats command metadata as trusted display data and emits it verbatim to a TTY, with no opt-in sanitization for consumers who don't control that metadata.

**Remediation.**

- Add a writer wrapper (or apply the existing `stripAnsi`/a stricter `stripControl`) that removes/escapes `0x00–0x08, 0x0B–0x1F, 0x7F` (preserving `\n`, `\t`) when the destination is a TTY, applied to all user-string `{s}` emissions in `help.zig`, `color.zig`, `progress.zig`, `table.zig`.
- Minimum viable: export a documented `sanitizeForTerminal(text)` and state in the security docs that consumers building command trees from untrusted input MUST pass metadata through it.

**Regression tests.** Pass `flag.help = "x\x1b[2Jy"` / `cmd.summary` containing `\x1b]0;…\x07`; assert no `0x1b` byte appears in rendered help, table, or progress output.

**References.** CWE-150; OWASP A05:2025.

---

### F-02 — NS-016 FALSE-RESOLVED: secret "zeroing" in `Context.deinit` is ineffective (Low)

**OWASP A04 Cryptographic Failures · CWE-316 (Cleartext Storage in Memory)**

**Evidence.** String flag values are stored as **borrowed slices** — there is no copy anywhere in the parse path (grep for `dupe`/`alloc` of string values in `parser.zig` returns nothing):

```zig
// parser.zig:386 — value aliases argv[i] / environ memory; not duplicated
.string, .path => FlagValue{ .string = value },
```

`Context.deinit` then "zeroes" by **reassigning the slice header**, which leaves the pointed-to bytes intact:

```zig
// command.zig:190-205
.string => {
    val.* = FlagValue{ .string = "" };   // overwrites 16-byte {ptr,len}, NOT the data
},
```

The doc comment overstates this:

```zig
// command.zig:44
/// 4. On `Context.deinit()`, string flag values (including secrets) are [zeroed]
```

The gap doc's own acceptance criterion for NS-016 ("inspect the memory region… verify the value is overwritten", `SECURITY_GAP_ANALYSIS.md:746`) is not met.

**Attack scenario.** A secret accidentally passed as a normal (non-`.from_file_or_stdin`) string flag remains readable in argv/environ memory after `deinit()` (core dump, `/proc/<pid>/cmdline`, heap inspection). The "defense-in-depth zeroing" provides none.

**Impact.** Low. Genuine secrets are steered to file/stdin by policy and are rejected from flags (`parser.zig:293`); this branch only ever sees non-secret strings, and argv/environ exposure is inherent to the OS regardless. The defect is a **false sense of protection**, not new exposure.

**Root cause.** Conflating "reassigning a slice" with "scrubbing memory"; the data is OS-owned, not heap-owned, so it cannot be scrubbed here anyway.

**Remediation.** Either (a) correct the comment to state that argv/environ-backed values cannot be scrubbed in `deinit`, and update NS-016 to Won't-Fix-with-rationale; or (b) if real in-memory scrubbing is desired, `dupe` secret-flagged values on store and `@memset(buf, 0)` the heap copy in `deinit`.

**Regression test.** Store a known string flag value, call `deinit`, and assert the underlying buffer is unchanged (documents current reality) — or, after option (b), assert the heap copy is zeroed.

---

### F-03 — NS-020 partial: Markdown headings / prose / code-fences emitted raw (Low)

**OWASP A05 Injection · CWE-79 / CWE-116**

**Evidence.** `writeMarkdownEscaped` (`help.zig:781-799`) escapes only `|`, `` ` ``, `<`, `>` and is applied to **table cells** (flag rows, subcommand rows). Headings/prose/code blocks bypass it:

```zig
help.zig:807  try w.print(" {s}\n\n", .{cmd.name});       // H1 heading — RAW
help.zig:810  try w.print("{s}\n\n", .{cmd.summary});      // prose — RAW
help.zig:823  try w.print("{s}\n\n", .{cmd.long_help});    // prose — RAW
help.zig:830  try w.print("```bash\n{s}\n```\n\n", .{example}); // code fence — RAW
help.zig:882  try w.print("### {s}\n\n", .{group_name});   // heading — RAW
```

NS-020's resolution claims escaping for "table cells **and headings**"; the heading path at `:807/:882` is raw, so the claim is partially false.

**Attack scenario.** Docs auto-generated from commands built from untrusted plugin metadata; a `long_help`/`summary` containing `<img src=x onerror=alert(1)>` or a `cmd.name`/`example` containing a `` ``` ``-newline closes a code fence early and injects HTML — stored XSS when the generated Markdown is rendered on a docs site.

**Impact.** Low (requires consumers to publish generated Markdown from untrusted metadata to an HTML renderer).

**Root cause.** `writeMarkdownEscaped` is cell-oriented; prose/heading/fence contexts need different handling (HTML-escape `<`/`>`, neutralize leading `#`, sanitize fence content) and were not covered.

**Remediation.** Add context-appropriate escaping for headings/prose (HTML-escape angle brackets, escape leading `#`) and code-fence content (forbid/neutralize embedded ` ``` `+newline). Update NS-020 to reflect actual scope.

**Regression test.** Generate Markdown for `cmd.long_help = "<script>x</script>"` and `example = "a\n```\nb"`; assert no raw `<script>` and no premature fence close.

---

### F-04 — PowerShell `-CommandName '{cmd.name}'` not escaped (Low)

**OWASP A05 Injection · CWE-78/CWE-94**

**Evidence.** Every other single-quoted PowerShell string in the generator is run through `escapePowerShellString` (which now correctly doubles `'` and strips NUL/CR/LF — NS-049 verified fixed). This one is not:

```zig
// powershell.zig:33
try w.print("Register-ArgumentCompleter -Native -CommandName '{s}' -ScriptBlock {{\n", .{cmd.name});
```

**Attack scenario.** `cmd.name = "app'; <ps-code>; '"` breaks out of the single-quoted string when the completion script is dot-sourced.

**Impact / likelihood.** Low — `cmd.name` is developer-controlled in the common case; relevant only when names come from untrusted input.

**Remediation.** Wrap with `escapePowerShellString(esc_alloc, cmd.name)` like the other sites. **Test:** generate with `cmd.name = "a'b"`, assert output contains `'a''b'`.

---

### F-05 — zsh emits command names into `case` labels / function names with no sanitizer (Low)

**OWASP A05 Injection · CWE-78**

**Evidence.** Bash received `sanitizeBashIdentifier` (NS-014, verified now allocator-based — `bash.zig:88`). zsh has no equivalent; raw names go into `case` labels and function identifiers:

```zig
// zsh.zig:218-219
try w.print("                {s})\n", .{subcmd.name});   // case pattern — RAW
try w.print("                    _{s}\n", .{subprefix}); // function call — RAW (subprefix from raw names)
// zsh.zig:174
try w.print("_{s}() {{\n", .{prefix});                   // function definition — RAW
```

(Describe-list `name`/`summary` *are* escaped at `zsh.zig:203-205`; the gap is specifically the case labels and function identifiers.)

**Attack scenario.** `subcmd.name = "x) ; evil ;;"` injects into the generated `case` statement when the zsh completion is sourced.

**Impact / likelihood.** Low — developer-controlled names in the common case; asymmetric hardening gap vs. bash.

**Remediation.** Add a zsh identifier sanitizer (mirror `sanitizeBashIdentifier`) for function names, and escape/validate `subcmd.name` used as a `case` pattern.

**Test:** generate with `subcmd.name = "a;b"`, assert the case label and function name contain no `;`.

---

### F-06 — Unchecked fixed-array stack write in fish at >16 nesting levels (Low)

**OWASP A10 Mishandling of Exceptional Conditions · CWE-787 (Out-of-bounds Write) / CWE-1284**

**Evidence.**

```zig
// fish.zig:170-177
var new_path: [16][]const u8 = undefined;
var new_path_len: usize = 0;
for (path) |p| { new_path[new_path_len] = p; new_path_len += 1; }  // fills up to path.len
new_path[new_path_len] = subcmd.name;   // NO check that new_path_len < 16
new_path_len += 1;
```

If the subcommand chain reaches 16 levels, `path.len == 16`, `new_path_len` becomes 16, and `new_path[16]` is an out-of-bounds stack write. In Debug/ReleaseSafe this panics; in **ReleaseFast (bounds checks off) it is a genuine OOB stack write**.

**Note vs. prior analysis.** NS-006 documented the "16-level depth limit" as benign/Won't-Do but did **not** identify the missing bounds check — this is a new robustness defect, not the previously-accepted item.

**Attack scenario.** A consumer (or untrusted command tree) defines >16 nested subcommands and generates fish completions → panic (DoS) or OOB write under ReleaseFast.

**Remediation.** Guard before the write: `if (new_path_len >= new_path.len) return error.TooDeep;` (or skip with a documented cap). **Test:** build a 17-level command tree, generate fish completions, assert graceful error rather than panic/UB.

---

### F-07 — `isSafePath` is advisory, non-canonicalizing, symlink-blind (Low)

**OWASP A01 Broken Access Control · CWE-22/CWE-59**

**Evidence.** `isSafePath` (`fs.zig:155-193`) blocks a small prefix list (`/etc/shadow`, `/etc/sudoers`, `/etc/passwd`, `/etc/gshadow`, `/proc/self/`, `.ssh/`) and literal `..` segments via `containsPathTraversal`. It performs no `realpath` canonicalization, so it is trivially bypassed: `/etc//shadow`, `/etc/./shadow`, a relative path, a symlink `/tmp/x -> /etc/shadow`, or any sensitive path not on the hardcoded list (e.g. `/root/.bash_history`, `/etc/ssl/private/`) passes. The function is also **not called by any other module in this library** — it is an opt-in helper for consumers.

**Impact.** Low and consistent with prior adjudication (NS-005/GAP-S018 marked it documented Won't-Do). I re-confirm it because the name `isSafePath` invites misuse as a security boundary, which it is not.

**Remediation.** Either rename to `isObviouslyUnsafePath` / document loudly that it is a best-effort denylist and callers needing a real guarantee must `realpathAlloc` + check against an allowlisted root; or implement canonicalization. No code change strictly required if documentation is strengthened.

---

### F-08 — `writeFileAtomic` temp file not anchored to a trusted directory fd (Low, hardening)

**OWASP A05 Security Misconfiguration · CWE-367 (TOCTOU) / CWE-377**

**Evidence.** `writeFileAtomic` (`fs.zig:83-111`) correctly uses a random suffix, `0o600`, fsync, and errdefer cleanup (NS-018/GAP-0016 verified fixed). However, it creates `"{path}.{rand}"` and renames within `cwd()` resolved from the **caller-supplied `path` string each time**, not via a pre-opened directory handle. If the target directory is attacker-controlled/shared, the directory component can be swapped between create and rename (classic TOCTOU on the parent dir).

**Impact.** Low — requires an attacker with write access to the target's parent directory; the `0o600` mode and random suffix already close the most common races.

**Remediation.** For defense-in-depth, open the parent directory once (`openDir`) and perform `createFileZ`/`rename` relative to that fd. Document that callers should pass paths in directories they control.

---

### F-09 — CI components pinned to mutable tags, not SHAs (Info, known accepted-risk)

**OWASP A03 Supply Chain Failures · CWE-829**

**Evidence.** `.gitlab-ci.yml:10-23` pins `devnw/ci-catalog/*@v1.7.1` (tags). Tags are mutable; a compromised or force-moved tag changes pipeline behavior. This is **explicitly documented** (NS-001 Won't-Do, with rationale that components are first-party and tag-pinning preserves the auto-update workflow; the file even carries a header comment to that effect at lines 5-7). Re-stated for completeness only — no new action recommended beyond what's already adjudicated. The Zig toolchain download itself **is** SHA-256-verified (`.gitlab-ci.yml:77-89`), which is the higher-risk path and is handled well.

---

### F-10 — Config-file handling lives in an unaudited external dependency (Info / coverage gap)

**OWASP A08 Integrity · A05 Injection**

**Evidence.** `src/config.zig` is a re-export shim (verified, lines 29-71). XDG path resolution (`getPaths`), file parsing (`parseFile`, TOML/JSON/YAML), `.env` loading (`dotenv`), and secret-file reading (`readFromFile`/`readFromStdin`) all execute in `gitlab.com/devnw/zig/config.git`, which was not in scope. The threat model explicitly calls out config-file path traversal, unsafe deserialization, and secret handling — **none of which can be confirmed from the provided files.**

**Remediation.** Run a separate appsec pass on the `config` dependency's `loader`, `xdg`, `dotenv`, and `secret` modules, specifically for: path traversal in `XDG_CONFIG_HOME`/`getPaths`, deserialization safety (deeply nested / billion-laughs style inputs), and whether `readFromFile` enforces file permissions/ownership for secrets.

---

## 5. Secure Design Notes (positive controls verified in current code)

1. **Pager uses direct `argv` execution, never a shell.** `pager.zig:78-93` tokenizes `PAGER` and passes the array to `Child.init` — no `/bin/sh -c`. Shell metacharacters in `PAGER` are not interpreted (GAP-0008, **verified**).
2. **Secret policy is enforced on all three channels.** A `.from_file_or_stdin` flag is rejected if passed as `--flag=` (`parser.zig:293`), skipped in env defaults (`parser.zig:484`), and skipped in CLI defaults (`parser.zig:544`); subcommand env defaults reuse the same guarded helper (`parser.zig:261-263`) — no bypass for nested secret flags (GAP-0037/NS-050, **verified**).
3. **Signal handling is a correct flag-and-poll design.** Handlers only set atomic flags (`signal.zig:237-249, 289-309`); user callbacks run in normal context via `pollSignals()` (`signal.zig:139-148`). `callback_count` is atomic; registration is mutex-protected; Windows config is atomic booleans (NS-013/NS-019/GAP-0014, **verified**).
4. **Completion escapers strip NUL/newline/CR and neutralize shell metacharacters** in bash, zsh, fish, and PowerShell (NS-008/009/048/049, **verified with quoted code**); `sanitizeBashIdentifier` is allocator-based and reentrant (NS-052, **verified**); fish `buildCondition`/`buildSubcommandCondition` escape names (NS-051, **verified**).
5. **roff (man), JSON help, and `--version` JSON are fully escaped** for every user string, including line-start `.`/`'` after newlines in roff (NS-011/012/GAP-0012/0013, **verified**).
6. **Atomic file write is hardened:** random suffix, `0o600`, fsync-before-rename, errdefer cleanup (`fs.zig:83-111`).
7. **TTY dimension cast no longer panics** — computed in `i32`, returns `null` on non-positive (`tty.zig:138-143`, NS-054, **verified**).
8. **No format-string injection:** every `std.fmt`/`print` uses a comptime literal in the format position; argv/env content only reaches the args position (verified across parser/command/help).
9. **Argument parsing is panic-safe:** `parseInt`/`parseFloat` return errors on overflow/garbage; argv indexing is bounds-checked before every value consume (`parser.zig` value-consume guards).
10. **Parallelism is bounded and race-free:** `MAX_CHUNKS = 64` cap, disjoint result ranges, `WaitGroup`-synchronized, sequential fallback on submit failure (`parallel.zig`).
11. **Supply chain:** both deps URL-SHA + content-hash pinned (`build.zig.zon:36-41`); Zig toolchain SHA-256 verified against the official index (`.gitlab-ci.yml`); `detect_diamond_deps.py` is pure regex parsing with no `eval`/shell/network and explicit soft-fail semantics.
12. **Password input** disables echo on both POSIX (termios `ECHO=false`, restored via `defer`) and Windows (clears `ENABLE_ECHO_INPUT`, restored via `defer`); the stack line buffer is `@memset(line, 0)` before free (`prompt.zig:222-273`); non-TTY returns `NotInteractive` (NS-047/GAP-0015/S012, **verified**). Heap-return zeroing is documented as caller responsibility.
13. **Error-path redaction:** `redactPath` masks `.ssh/`, `.aws/`, `credentials`, `secrets`, `.env`, etc. in user-facing messages (`fs.zig:131-152`).
14. **Repo hygiene:** `.gitignore` excludes `.env`, `.env.*`, `*.env` (verified at lines 23-25); README documents the "secrets file/stdin only, never flags/env" guarantee (README.md:32, 170-205).

---

## 6. Coverage Gaps & Questions

1. **External `config` dependency (largest gap).** Config path resolution, TOML/JSON/YAML deserialization, dotenv, and secret-file reading are all out of scope (re-export shim only). The threat model's config-file path-traversal / unsafe-deserialization / secret-handling concerns **cannot be answered from this repo**. → Separate review required (F-10).
2. **No dynamic analysis.** Findings are static. The ReleaseFast OOB claim in F-06 and the absence of other OOB writes were reasoned, not fuzzed. The repo has a fuzz job (`zig build test --fuzz`); confirming it exercises the parser and completion generators with metacharacter/over-deep inputs would raise confidence.
3. **`thread_pool` dependency internals** not reviewed (parallel.zig's *use* of it is sound).
4. **Windows-specific paths** (console mode, `GetConsoleScreenBufferInfo`, `SetConsoleCtrlHandler`) were read but not executed; behavior assumed per the Win32 contract.
5. **Question — F-02:** Is in-memory secret scrubbing actually a goal for non-`from_file_or_stdin` flags, or should the policy simply forbid secrets in flags (which it already does) and the misleading comment be removed? The answer determines whether F-02 is "fix the code" or "fix the doc."
6. **Question — F-01 scope:** Does the project intend to support consumers building command trees from untrusted/dynamic metadata? If yes, terminal-escape sanitization (and the F-03/F-04/F-05 encoding gaps) become more than Low. If the documented contract is "metadata is developer-authored at compile time," these stay Low — but that contract should be stated explicitly in SECURITY.md.

---

## 7. Prioritized Next Actions

1. **(Medium) F-01 — Add terminal-escape sanitization on TTY output**, or export a documented `sanitizeForTerminal()` plus a SECURITY.md statement of the trust contract for command metadata. Highest residual risk; untracked.
2. **(Low, quick) F-04 / F-05 — Close the two remaining completion-escaping gaps:** wrap `-CommandName '{cmd.name}'` in `escapePowerShellString` (`powershell.zig:33`); add a zsh identifier sanitizer + case-label escaping (`zsh.zig:174,218-219`). One-to-two hours each; extends existing patterns.
3. **(Low, quick) F-06 — Add the missing bounds check** in fish `new_path` (`fish.zig:176`) to convert a potential ReleaseFast OOB write / Debug panic into a graceful error.
4. **(Low) F-03 — Extend Markdown escaping** to headings/prose/code-fence content, and correct the NS-020 resolution note.
5. **(Low, doc) F-02 — Correct the `Context.deinit` / NS-016 claim:** either remove the "secrets zeroed" comment with rationale, or implement real heap-copy scrubbing for secret-flagged values.
6. **(Info, doc) F-07 / F-08 — Harden filesystem helpers' documentation/anchoring:** clarify `isSafePath` is a best-effort denylist; optionally anchor `writeFileAtomic` to a directory fd.
7. **(Coverage) F-10 — Schedule a separate appsec review of the external `config` dependency** (path traversal, deserialization, secret-file handling) — this is the only place where the README's config/secret guarantees remain unverified.
8. **(Process) Update `docs/SECURITY_GAP_ANALYSIS.md`** to (a) fix the stale line numbers (roff is at 620 not 549, JSON at 494 not 450, version at 752 not 657, markdown at 781 not 757), (b) record F-01 through F-06 as new findings, and (c) downgrade NS-016/NS-020 from "Closed" to the accurate partial/false-resolved status.

---

*No product code was modified. All findings cite `file:line` with quoted code. Items that could not be grounded in a concrete code path are listed as questions in §6 rather than findings. The library shows a mature, well-tracked security posture; the residual findings are low-severity encoding/hardening gaps conditioned on consumers feeding untrusted strings into the command tree, plus one external-dependency coverage gap.*
