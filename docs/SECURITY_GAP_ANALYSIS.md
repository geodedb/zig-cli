# Security Gap Analysis

> Auto-generated from full codebase audit (2026-03-24). Updated 2026-03-25 with Phase 3 follow-up findings (NS-047 through NS-055). Updated 2026-06-11 with codepros:audit iteration-1 findings (NS-056, NS-058 through NS-062), status corrections (NS-016, NS-020), and the NS-057 refutation. Updated 2026-06-12: all 6 iteration-1 open findings (NS-056, NS-058, NS-059, NS-060, NS-061, NS-062) **Closed** by the audit-iteration-1 fix merge (188bf5a); NS-016 remediated (doc corrected + `freeSecret` helper). **0 open findings.**

Last updated: 2026-06-12

## REGRESSION NOTICE -- RESOLVED

On 2026-03-24, Phase 3 code inspection confirmed that 19 previously-closed findings
had regressed due to a git stash/pop incident. All 19 regressions plus 3 new findings
have been re-implemented and verified. 760/760 tests pass with 0 memory leaks.

## 2026-06-12 UPDATE -- iteration-1 fixes merged (188bf5a)

All 6 open iteration-1 findings were fixed and verified in code; the audit-iteration-1
branch merged to `main` as `188bf5a`. **0 open findings remain.** Fix commits:

| Finding | Status | Fix commit(s) | Verified evidence |
|---------|--------|---------------|-------------------|
| NS-056 (terminal escape injection) | **Closed** | `19bb03b`, `277a98e`, `b9f7f47`, `e3deefd`, `e296403` | `src/util/text.zig:199` `stripControlChars`; applied at `errors.zig:110`, color/progress/table |
| NS-058 (ProgressBar.init underflow) | **Closed** | `5d0bc6c` | `src/term/progress.zig:169` `barWidthForTerminal` uses a saturating subtraction (`-\|`); width-floor test at :441 |
| NS-059 (Windows password echo on console-mode failure) | **Closed** | `022e4cf`, `72cd736` | `src/prompt.zig:230,241` both failure branches `return PromptError.NotInteractive`; `freeSecret` helper added |
| NS-060 (markdown headings/prose/fences raw) | **Closed** | `efaf9a7`, `22c374d` | `src/cli/help.zig:895` `writeMarkdownHeading`, :919 `writeMarkdownProse`, :945 `writeFenceSafe` applied at :969,973,979 |
| NS-061 (completion hardening PS/zsh/fish) | **Closed** | `1d7d40a` | `powershell.zig:34-35` `-CommandName` escaped; fish depth cap `fish.zig:176` `if (path.len >= max_depth) break;`; zsh identifier/case sanitizers |
| NS-062 (UTF-8 codepoint splitting) | **Closed** | `269e228`, `8e30398`, `6739ffb` | `src/term/table.zig:235,263` `sanitize.utf8FloorIndex`; `util/text.zig` truncation snaps to codepoint starts |

**NS-016** (False-Resolved) remediated by `928f603` (doc comment corrected to state argv/environ-backed
values cannot be scrubbed in `deinit`) plus `022e4cf` (`freeSecret` zeroing helper for heap-owned secrets).
929/929 tests pass on `188bf5a`.

## 2026-06-11 UPDATE -- codepros:audit iteration 1

A four-phase audit (scan + independent appsec review + adversarial security review) was
run against HEAD `de11f86`. It surfaced **6 new findings** (now all Closed, see above) and
**2 status corrections** to previously-closed items, and **refuted** one scan candidate.

- **Found (6, now Closed):** NS-056 (Medium, terminal escape injection — broadened to live-by-default),
  NS-058 (Low–Medium, ProgressBar.init underflow DoS), NS-059 (Medium, Windows password echo
  on GetConsoleMode failure), NS-060 (Low, Markdown headings/prose/fences raw), NS-061 (Low,
  completion-generator hardening: PowerShell/zsh/fish), NS-062 (Low, UTF-8 byte-slicing).
- **Status corrections (2):** **NS-016** Closed -> **False-Resolved** -> **Closed** (remediated 2026-06-12);
  **NS-020** Closed -> **Partially False-Resolved** (only table cells escaped; headings/prose/code-fences raw —
  tracked + fixed as NS-060).
- **Refuted (1):** scan candidate NS-057 (signal `callback_count` read without mutex) is
  architecturally safe (acquire/release pairing) -> **Won't Do**.
- **Stale line numbers corrected** per APPSEC §7.8 (see "Line-Number Corrections" below).

## Summary

| Risk Level | Total | Open | Closed | False-Resolved | Won't Do |
|-----------|-------|------|--------|----------------|----------|
| Critical | 1 | 0 | 1 | 0 | 0 |
| High | 2 | 0 | 2 | 0 | 0 |
| Medium | 24 | 0 | 22 | 0 | 1 |
| Low | 28 | 0 | 26 | 1 | 1 |
| Info | 7 | 0 | 1 | 0 | 6 |
| **Total** | **62** | **0** | **52** | **1** | **8** |

> Note on the table: NS-016 was corrected from Closed to False-Resolved on 2026-06-11, then
> remediated to **Closed** on 2026-06-12. NS-020's open remediation was tracked as NS-060, which
> is now Closed. NS-057 is a refuted candidate recorded as Won't Do.

**0 open findings** as of 2026-06-12. The 6 iteration-1 findings (NS-056, NS-058, NS-059, NS-060,
NS-061, NS-062) were fixed in the `188bf5a` merge. All 8 Phase 3 follow-up findings
(NS-047 through NS-054) remain closed. The prior closed findings remain verified.

### Top 5 Risks (all CLOSED, by Risk Score)

1. **NS-056** Terminal escape-sequence injection (Risk 36, CWE-150) — **Closed** `19bb03b`/`b9f7f47` — [#128](https://gitlab.com/devnw/zig/cli/-/issues/128)
2. **NS-059** Windows `password()` echo on GetConsoleMode failure (Risk 32, CWE-549) — **Closed** `022e4cf` — [#130](https://gitlab.com/devnw/zig/cli/-/issues/130)
3. **NS-058** `ProgressBar.init` u16 underflow panic / DoS (Risk 24, CWE-191) — **Closed** `5d0bc6c` — [#129](https://gitlab.com/devnw/zig/cli/-/issues/129)
4. **NS-060** Markdown headings/prose/fences raw (Risk 16, CWE-79/116) — **Closed** `efaf9a7` — [#131](https://gitlab.com/devnw/zig/cli/-/issues/131)
5. **NS-061** Completion-generator hardening: PowerShell/zsh/fish (Risk 12, CWE-94/78/787) — **Closed** `1d7d40a` — [#132](https://gitlab.com/devnw/zig/cli/-/issues/132)

**Immediate action required: 0.** No open findings. gitleaks clean (working tree + history), no
third-party dependencies in the CVE-tracked closure.

### Line-Number Corrections (APPSEC §7.8)

Stale evidence line numbers from the 2026-03-25 doc were re-anchored against HEAD `de11f86`:

| Item | Old (doc) | Current (verified) |
|------|-----------|--------------------|
| roff escaping (`writeRoffEscaped`) | help.zig:549 | help.zig:620 |
| JSON help escaping (`writeJsonEscapedString`) | help.zig:450 | help.zig:494 |
| version JSON (`printVersionImpl`) | help.zig:657 | help.zig:752 |
| Markdown escaping (`writeMarkdownEscaped`) | help.zig:757/781 | help.zig:781 |

> These corrections are documentation-only; the underlying mitigations remain in place and verified.

## Stack-Ranked Findings Table

| Rank | Severity | Risk Score | Finding | Component | CWE/OWASP | Evidence (file:line) | Issue URL | Status |
|------|----------|------------|---------|-----------|-----------|---------------------|-----------|--------|
| -- | **Medium** | **36** | **NS-056: Terminal escape injection -- no ESC stripping on TTY (live-by-default via unknown-command path)** | **term/help/errors** | **CWE-150 / A05:2021** | **`src/util/text.zig:199` stripControlChars; `errors.zig:110`** | **[#128](https://gitlab.com/devnw/zig/cli/-/issues/128)** | **Closed** (`19bb03b`,`b9f7f47`) |
| -- | **Medium** | **32** | **NS-059: Windows password() echoes input when GetConsoleMode fails** | **prompt** | **CWE-549 / A07:2021** | **`src/prompt.zig:230,241`** | **[#130](https://gitlab.com/devnw/zig/cli/-/issues/130)** | **Closed** (`022e4cf`) |
| -- | **Low–Med** | **24** | **NS-058: ProgressBar.init u16 underflow panic (DoS) when width < 20** | **term/progress** | **CWE-191 / A05:2021** | **`src/term/progress.zig:169` barWidthForTerminal** | **[#129](https://gitlab.com/devnw/zig/cli/-/issues/129)** | **Closed** (`5d0bc6c`) |
| -- | **Low** | **16** | **NS-060: Markdown headings/prose/code-fences emitted raw (NS-020 partial false-resolution)** | **help** | **CWE-79/116 / A05:2021** | **`src/cli/help.zig:895,919,945`** | **[#131](https://gitlab.com/devnw/zig/cli/-/issues/131)** | **Closed** (`efaf9a7`) |
| -- | **Low** | **12** | **NS-061: Completion generator hardening (PowerShell -CommandName, zsh case/identifier, fish [16] OOB)** | **completion** | **CWE-94/78/787 / A05:2021** | **`powershell.zig:34-35`; `fish.zig:176`** | **[#132](https://gitlab.com/devnw/zig/cli/-/issues/132)** | **Closed** (`1d7d40a`) |
| -- | **Low** | **12** | **NS-062: UTF-8 codepoint splitting / byte-vs-column width math** | **util/text, term/table** | **CWE-697/1284 / A04:2021** | **`src/term/table.zig:235,263` utf8FloorIndex** | **[#133](https://gitlab.com/devnw/zig/cli/-/issues/133)** | **Closed** (`269e228`) |
| 1 | Critical | 95 | Shell injection via PAGER env var | pager | CWE-78 / A03:2021 | `src/term/pager.zig:57-58` | -- | **Closed** |
| -- | **Medium** | **35** | **NS-047: Windows password echo not suppressed** | **prompt** | **CWE-549 / A07:2021** | **`src/prompt.zig:179-183`** | **[#111](https://gitlab.com/devnw/zig/cli/-/issues/111)** | **Closed** |
| 2 | High | 85 | Shell completion injection (all 4 generators) | completion | CWE-94 / A03:2021 | `src/cli/completion/*.zig` | -- | **Closed** |
| 3 | High | 80 | PowerShell escapePowerShellString() is no-op | completion | CWE-94 / A03:2021 | `src/cli/completion/powershell.zig` | -- | **Closed** |
| 4 | Medium | 65 | JSON help output lacks JSON escaping | help | CWE-116 / A03:2021 | `src/cli/help.zig:450` | -- | **Closed** |
| 5 | Medium | 60 | Signal handler data race on callback_count | signal | CWE-362 / A04:2021 | `src/signal.zig:60` | -- | **Closed** |
| 6 | Medium | 55 | Man page roff injection | help | CWE-116 / A03:2021 | `src/cli/help.zig:549` | -- | **Closed** |
| 7 | Medium | 55 | Password buffer not zeroed (POSIX) | prompt | CWE-316 / A02:2021 | `src/prompt.zig:164` | -- | **Closed** |
| 8 | Medium | 50 | PowerShell escapeRegex() is no-op | completion | CWE-94 / A03:2021 | `src/cli/completion/powershell.zig` | -- | **Closed** |
| 9 | Medium | 50 | SecretPolicy bypass via default_str | parser | CWE-798 / A07:2021 | `src/cli/parser.zig:434` | -- | **Closed** |
| 10 | Medium | 45 | Active help message shell injection (bash/zsh) | completion | CWE-78 / A03:2021 | `bash.zig`, `zsh.zig` | -- | **Closed** |
| 11 | Medium | 40 | Windows password buffer not zeroed | prompt | CWE-316 / A02:2021 | `src/prompt.zig:186` | -- | **Closed** |
| 12 | Medium | 35 | Zsh writeZshFlag() help text unescaped | completion/zsh | CWE-78 / A03:2021 | `src/cli/completion/zsh.zig` | -- | **Closed** |
| 13 | Medium | 35 | Zsh @memcpy no bounds check | completion/zsh | CWE-787 / A06:2021 | `src/cli/completion/zsh.zig` | -- | **Closed** |
| 14 | Medium | 30 | Fish completion values unescaped | completion/fish | CWE-78 / A03:2021 | `src/cli/completion/fish.zig` | -- | **Closed** |
| 15 | Medium | 30 | PowerShell subcmd.name unescaped | completion/ps | CWE-78 / A03:2021 | `src/cli/completion/powershell.zig` | -- | **Closed** |
| 16 | Medium | 24 | Bash escape missing NUL/newline filtering | completion/bash | CWE-74 / A03:2021 | `src/cli/completion/bash.zig:17-44` | -- | **Closed** |
| 17 | Medium | 24 | Zsh escape missing NUL/newline filtering | completion/zsh | CWE-74 / A03:2021 | `src/cli/completion/zsh.zig:42-68` | -- | **Closed** |
| 18 | Medium | 24 | Fish completion outputs unescaped cmd/flag names into shell syntax | completion/fish | CWE-78 / A03:2021 | `src/cli/completion/fish.zig:58,86,100,107,147,152` | -- | **Closed** |
| 19 | Medium | 24 | writeRoffEscaped doesn't handle newlines -- roff directive injection | help | CWE-74 / A03:2021 | `src/cli/help.zig:549-571` | -- | **Closed** |
| 20 | Medium | 24 | printVersionImpl JSON injection (cmd.name/version unescaped) | help | CWE-116 / A03:2021 | `src/cli/help.zig:657` | -- | **Closed** |
| 21 | Medium | 24 | Signal handler invokes non-async-signal-safe user callbacks | signal | CWE-364 / A04:2021 | `src/signal.zig:161-177,262-271` | -- | **Closed** |
| 22 | Medium | 24 | CI catalog components pinned to mutable git tags | CI/CD | CWE-829 / A08:2021 | `.gitlab-ci.yml:7-20` | [#35](https://gitlab.com/devnw/zig/cli/-/issues/35) | Won't Do |
| -- | **Medium** | **24** | **NS-048: Fish escapeFishSingleQuote does not strip NUL/newline/CR** | **completion/fish** | **CWE-74 / A03:2021** | **`src/cli/completion/fish.zig:17-43`** | **[#115](https://gitlab.com/devnw/zig/cli/-/issues/115)** | **Closed** |
| -- | **Medium** | **24** | **NS-049: PowerShell escapePowerShellString does not strip NUL/newline/CR** | **completion/ps** | **CWE-74 / A03:2021** | **`src/cli/completion/powershell.zig:174-194`** | **[#117](https://gitlab.com/devnw/zig/cli/-/issues/117)** | **Closed** |
| 23 | Low | 35 | Predictable temp file in writeFileAtomic | fs | CWE-377 / A05:2021 | `src/util/fs.zig:59` | -- | **Closed** |
| 24 | Low | 25 | isSafePath() only blocks 2 paths | fs | CWE-22 / A01:2021 | `src/util/fs.zig:127-142` | -- | **Closed** |
| 25 | Low | 25 | Fish subcmd.name unescaped in -a argument | completion/fish | CWE-78 / A03:2021 | `src/cli/completion/fish.zig` | -- | **Closed** |
| 26 | Low | 20 | isSafePath doesn't resolve symlinks | fs | CWE-59 / A01:2021 | `src/util/fs.zig:121-157` | -- | Closed (partial doc) |
| 27 | Low | 20 | Signal cleanup callbacks in async-signal context | signal | CWE-364 / A04:2021 | `src/signal.zig` | -- | Closed (minimal doc) |
| 28 | Low | 16 | NS-016: Secret flag values not zeroed from memory after use | parser/command | CWE-316 / A02:2021 | `src/cli/command.zig:199`; `parser.zig:386` | -- | **False-Resolved** (see correction below) |
| 29 | Low | 16 | NS-020: generateMarkdown escaping (table cells only) | help | CWE-79 / A03:2021 | `src/cli/help.zig:807,810,823,830,882` | -- | **Partially False-Resolved** (cells only; headings/prose/fences raw -> NS-060) |
| 30 | Low | 15 | Bash flag.name unescaped in variable assignment | completion/bash | CWE-78 / A03:2021 | `src/cli/completion/bash.zig` | -- | **Closed** |
| 31 | Low | 15 | Zsh subcmd.name unescaped in case pattern | completion/zsh | CWE-78 / A03:2021 | `src/cli/completion/zsh.zig` | -- | **Closed** |
| 32 | Low | 15 | Fixed-size buffers silently truncate | multiple | CWE-120 / A06:2021 | `src/cli/completion/*.zig`, `src/cli/help.zig` | -- | Won't Do |
| 33 | Low | 15 | Fish flag.help/subcmd.summary unescaped in single-quoted strings | completion/fish | CWE-78 / A03:2021 | `src/cli/completion/fish.zig` | -- | **Closed** |
| -- | **Low** | **15** | **NS-050: applyEnvDefaults ignores subcommand flags** | **parser** | **CWE-1188 / A07:2021** | **`src/cli/parser.zig:508-544`** | **[#118](https://gitlab.com/devnw/zig/cli/-/issues/118)** | **Closed** |
| -- | **Low** | **15** | **NS-051: Fish buildCondition emits unescaped command names** | **completion/fish** | **CWE-78 / A03:2021** | **`src/cli/completion/fish.zig:181-237`** | **[#119](https://gitlab.com/devnw/zig/cli/-/issues/119)** | **Closed** |
| 34 | Low | 12 | Bash writes cmd.name directly into shell function names | completion/bash | CWE-78 / A03:2021 | `src/cli/completion/bash.zig:94,106,112` | -- | **Closed** |
| 35 | Low | 12 | PowerShell completion values not escaped | completion/ps | CWE-74 / A03:2021 | `src/cli/completion/powershell.zig:161` | -- | **Closed** |
| 36 | Low | 10 | Levenshtein buffer overflow | suggest | CWE-120 / A06:2021 | `src/util/suggest.zig:16-17` | -- | **Closed** |
| -- | **Low** | **10** | **NS-052: sanitizeBashIdentifier static mutable buffer** | **completion/bash** | **CWE-362 / A04:2021** | **`src/cli/completion/bash.zig:86-99`** | **[#120](https://gitlab.com/devnw/zig/cli/-/issues/120)** | **Closed** |
| 37 | Low | 8 | Inconsistent shell escaping (7 unescaped points) | completion | CWE-78 / A03:2021 | `fish.zig`, `zsh.zig`, `bash.zig` | [#38](https://gitlab.com/devnw/zig/cli/-/issues/38) | **Closed** (subsumed by GAP-0011 closure) |
| 38 | Low | 8 | Heap-allocated password not zeroed on free | prompt | CWE-316 / A02:2021 | `src/prompt.zig:127-133` | [#40](https://gitlab.com/devnw/zig/cli/-/issues/40) | Closed (documented) |
| 39 | Low | 8 | Pager command splitting cannot handle quoted arguments | pager | CWE-88 / A03:2021 | `src/term/pager.zig:58-80` | -- | **Closed** |
| 40 | Low | 8 | writeFileAtomic temp file inherits umask (world-readable risk) | fs | CWE-377 / A05:2021 | `src/util/fs.zig:54-79` | -- | **Closed** |
| 41 | Low | 8 | Windows active_config race condition | signal | CWE-362 / A04:2021 | `src/signal.zig:63,194` | -- | **Closed** |
| -- | **Low** | **8** | **NS-053: writeMarkdownEscaped incomplete -- backticks not escaped** | **help** | **CWE-116 / A03:2021** | **`src/cli/help.zig:757-771`** | **[#121](https://gitlab.com/devnw/zig/cli/-/issues/121)** | **Closed** |
| -- | **Low** | **8** | **NS-054: @intCast on negative terminal dimension (Windows)** | **tty** | **CWE-681 / A06:2021** | **`src/term/tty.zig:122-123`** | **[#122](https://gitlab.com/devnw/zig/cli/-/issues/122)** | **Closed** |
| 42 | Info | 4 | .gitignore does not exclude .env files | repo config | CWE-540 / A07:2021 | `.gitignore:22-24` | [#43](https://gitlab.com/devnw/zig/cli/-/issues/43) | Closed |
| 43 | Info | 4 | Pager executes PAGER env var (standard POSIX behavior) | pager | -- | `src/term/pager.zig:58-83` | -- | Won't Do |
| 44 | Info | 4 | isSafePath doesn't resolve symlinks (documented) | fs | CWE-59 | `src/util/fs.zig:126-162` | -- | Won't Do |
| 45 | Info | 4 | 16-level command depth limit in path arrays | completion/fish | CWE-120 | `src/cli/completion/fish.zig:131` | -- | Won't Do |
| 46 | Info | 4 | Zig dependency hash-pinned (good practice) | build | -- | `build.zig.zon:36-38` | -- | Won't Do (positive) |
| -- | **Info** | **4** | **NS-055: Gitleaks private-key-file rule too broad** | **config** | **--** | **`.gitleaks.toml:26-31`** | **--** | **Won't Do** |

---

## Closed Findings -- codepros:audit iteration 1 (found 2026-06-11, fixed 2026-06-12)

All six were independently re-derived and verified against HEAD `de11f86`, then fixed and
verified in code in the audit-iteration-1 merge `188bf5a`. Risk Score = Impact x Likelihood x 4.

### NS-056: Terminal escape-sequence injection -- no ESC stripping on TTY output [Medium] -- CLOSED

- **Status:** **Closed** (2026-06-12) -- fix commits `19bb03b`, `277a98e`, `b9f7f47`, `e3deefd`, `e296403`; resolution: `stripControlChars` added at `src/util/text.zig:199` and applied to TTY emissions (`errors.zig:110`, color/progress/table); regression tests for `\x1b[2J` and OSC at `text.zig:266-293`.
- **Risk Level:** Medium
- **Risk Score:** 36 (Impact: 3, Likelihood: 3)
- **CWE:** CWE-150 (Improper Neutralization of Escape Sequences)
- **OWASP:** A05:2021 Injection
- **Exploit Surface:** Local (argv/TTY) -- **live by default** via the unknown-command path; broader for consumers surfacing untrusted command metadata.
- **Confidence:** `confidence::confirmed` -- code trace verified at HEAD.
- **Affected files:** `src/util/errors.zig:50,107`; `src/term/color.zig:90-95`; `src/term/progress.zig:130,141`; `src/term/table.zig:189,226,245`; `src/prompt.zig:139,376,441`
- **Evidence:**

  ```zig
  // errors.zig:107 -- raw argv embedded into message; errors.zig:50 writes it raw:
  const message = try std.fmt.allocPrint(allocator, "'{s}' is not a command", .{input});
  // errors.zig:50
  try writer.print("{s}\n", .{self.message});
  ```

  `stripAnsi` (`color.zig:146`) exists but is never applied on any output path, and strips only CSI `...m` (not OSC / bare ESC / `\x1b[2J`).
- **Broadening (vs. original scan candidate NS-056 / appsec F-01):** the unknown-command path makes this **live by default** -- the default `run` flow echoes attacker-chosen argv (including ESC) to the TTY without any consumer needing to build a command tree from untrusted metadata. Scan candidate NS-056 (table/progress only) and appsec F-01 are merged here.
- **Fix guidance:** Apply a `stripControl` filter (drop `0x00-0x08, 0x0B-0x1F, 0x7F`; keep `\n`,`\t`) to all user-string `{s}` TTY emissions gated on `is_tty`, or export a documented `sanitizeForTerminal()` plus a SECURITY.md trust-contract statement.
- **Acceptance criteria:** No C0 control byte (except `\n`/`\t`) appears in rendered help/table/progress/prompt/unknown-command output when the input contained ESC. Regression test with `\x1b[2J` and `\x1b]0;...\x07`.
- **Issue:** [#128](https://gitlab.com/devnw/zig/cli/-/issues/128)
- **SLA:** 90 days (2026-09-09)

### NS-058: ProgressBar.init u16 underflow panic (DoS) when terminal width < 20 [Low-Medium] -- CLOSED

- **Status:** **Closed** (2026-06-12) -- fix commit `5d0bc6c`; resolution: `barWidthForTerminal` (`src/term/progress.zig:169`) uses saturating `@max(@min(term_width -| 20, 50), 1)`; width-floor regression test at `progress.zig:441`.
- **Risk Level:** Low-Medium (tracked Low)
- **Risk Score:** 24 (Impact: 2, Likelihood: 3)
- **CWE:** CWE-191 (Integer Underflow) / CWE-190
- **OWASP:** A05:2021 (Mishandling of Exceptional Conditions)
- **Exploit Surface:** Local (terminal geometry).
- **Confidence:** `confidence::confirmed`
- **Affected files:** `src/term/progress.zig:179`; `src/term/tty.zig:18,40-45,78`
- **Evidence:**

  ```zig
  // progress.zig:179 -- subtraction evaluated before @min; u16 underflow for width < 20:
  .width = @min(term_info.width - 20, 50),
  ```

  `term_info.width` is `u16` from the raw `ioctl(TIOCGWINSZ)` value (`tty.zig:78`). Debug/ReleaseSafe panic (DoS); ReleaseFast wraps to a huge value then clamps to 50 (silently wrong). Public API (`parallel.zig:42`).
- **Fix guidance:** `.width = @min(term_info.width -| 20, 50)` (saturating) or `@min(@max(term_info.width, 21) - 20, 50)`. Regression test with stubbed `term_info.width = 5`.
- **Acceptance criteria:** No panic for any `term_info.width` value; test with width 5 and 0.
- **Issue:** [#129](https://gitlab.com/devnw/zig/cli/-/issues/129)
- **SLA:** 180 days (2026-12-08)
- **Origin:** Adversarial review R-01 (missed by both prior reviews).

### NS-059: Windows password() echoes input when GetConsoleMode fails [Medium] -- CLOSED

- **Status:** **Closed** (2026-06-12) -- fix commits `022e4cf`, `72cd736`; resolution: both the GetConsoleMode-failure (`src/prompt.zig:241`) and SetConsoleMode-failure (`:230`) branches now `return PromptError.NotInteractive` instead of an echoed fallback read; `freeSecret` zeroing helper added for returned secrets.
- **Risk Level:** Medium
- **Risk Score:** 32 (Impact: 4, Likelihood: 2)
- **CWE:** CWE-549 (Missing Password Field Masking) / CWE-200
- **OWASP:** A07:2021 Identification and Authentication Failures
- **Exploit Surface:** Local (Windows; requires GetConsoleMode failure + screen visibility).
- **Confidence:** `confidence::confirmed`
- **Affected files:** `src/prompt.zig:237-240` (GetConsoleMode-failed branch), `src/prompt.zig:262` (`passwordInternal`, no echo suppression)
- **Evidence:**

  ```zig
  // prompt.zig:237-240 -- failure branch falls back to an echoed read:
  } else {
      // GetConsoleMode failed -- fall back to simple read
      return passwordInternal(stdin_r, allocator);
  }
  ```

  `passwordInternal` (`prompt.zig:262`) does a plain `readLineAlloc` with no echo suppression. The success branch above clears `ENABLE_ECHO_INPUT`; this branch does not. Note: this is distinct from NS-047 (Closed), which addressed the *primary* Windows echo path; NS-059 is the *fallback* path on GetConsoleMode failure.
- **Fix guidance:** On GetConsoleMode failure, do not silently fall back to an echoed read -- return an explicit error or use a no-echo read path (`_getch()`/`ReadConsole` with echo cleared).
- **Acceptance criteria:** Interactive Windows console with GetConsoleMode failure does not echo typed password characters.
- **Issue:** [#130](https://gitlab.com/devnw/zig/cli/-/issues/130)
- **Cross-ref:** Quality finding NQ-NEW-015 (same root cause).
- **SLA:** 90 days (2026-09-09)

### NS-060: Markdown headings/prose/code-fences emitted raw [Low] -- CLOSED

- **Status:** **Closed** (2026-06-12) -- fix commits `efaf9a7`, `22c374d`; resolution: context-aware escapers `writeMarkdownHeading` (`src/cli/help.zig:895`), `writeMarkdownProse` (:919), and `writeFenceSafe` (:945) now applied to headings/prose/fence content (:969,973,979,989,998); CR handling normalized across escapers. Regression tests for fence breakout and heading/prose escaping in `help.zig`.
- **Risk Level:** Low
- **Risk Score:** 16 (Impact: 2, Likelihood: 2)
- **CWE:** CWE-79 (XSS) / CWE-116 (Improper Encoding or Escaping)
- **OWASP:** A05:2021 Injection
- **Exploit Surface:** Indirect (downstream HTML renderer).
- **Confidence:** `confidence::confirmed`
- **Affected files:** `src/cli/help.zig:807,810,823,830,882`
- **Evidence:**

  ```zig
  help.zig:807  try w.print("# {s}\n\n", .{cmd.name});        // H1 -- RAW
  help.zig:830  try w.print("```bash\n{s}\n```\n\n", .{example}); // fence -- RAW
  ```

  `writeMarkdownEscaped` (`help.zig:781`) is applied only to table cells. This is the open remediation for the **NS-020 partial false-resolution** (NS-020 claimed "table cells and headings"). Covers quality findings NQ-NEW-007/008.
- **Fix guidance:** HTML-escape `<`/`>` in headings/prose, neutralize leading `#`, sanitize code-fence content against embedded ```` ``` ````+newline. Update NS-020 resolution note (done below).
- **Acceptance criteria:** `cmd.long_help = "<script>x</script>"` produces no raw `<script>`; `example = "a\n```\nb"` does not prematurely close the fence.
- **Issue:** [#131](https://gitlab.com/devnw/zig/cli/-/issues/131)
- **SLA:** 180 days (2026-12-08)

### NS-061: Completion generator hardening (PowerShell / zsh / fish) [Low] -- CLOSED

- **Status:** **Closed** (2026-06-12) -- fix commit `1d7d40a`; resolution: F-04 PowerShell `-CommandName` wrapped with `escapePowerShellString` (`powershell.zig:34-35`); F-05 zsh identifier/case-label sanitizers added; F-06 fish depth cap `if (path.len >= max_depth) break;` (`fish.zig:176`) prevents the OOB `[16]` write.
- **Risk Level:** Low
- **Risk Score:** 12 (Impact: 3, Likelihood: 1)
- **CWE:** CWE-94 / CWE-78 (Injection), CWE-787 (Out-of-bounds Write)
- **OWASP:** A05:2021 Injection / A10 (Mishandling of Exceptional Conditions)
- **Exploit Surface:** Supply chain (dev-controlled names in common case).
- **Confidence:** `confidence::confirmed`
- **Affected files:** `src/cli/completion/powershell.zig:33`; `src/cli/completion/zsh.zig:174,218,219`; `src/cli/completion/fish.zig:170-177`
- **Evidence:** Groups appsec **F-04** (PowerShell `-CommandName '{cmd.name}'` raw -- the lone unescaped single-quoted PS string), **F-05** (zsh case labels + function identifiers raw; zsh has **no** sanitizer while bash has `sanitizeBashIdentifier`/`escapeBashCasePattern`), and **F-06** (fish `new_path[16]` write with no bounds check at depth 16 -> panic in Debug/ReleaseSafe, OOB stack write in ReleaseFast).

  ```zig
  // powershell.zig:33 (F-04)
  try w.print("Register-ArgumentCompleter -Native -CommandName '{s}' -ScriptBlock {{\n", .{cmd.name});
  // fish.zig:176 (F-06) -- no bounds check before write:
  new_path[new_path_len] = subcmd.name;
  ```

  Note F-06 vs NS-006 (Won't Do): NS-006 accepted the 16-level *depth limit*; F-06 is the *missing bounds check*, a distinct robustness defect.
- **Fix guidance:** F-04 wrap with `escapePowerShellString`; F-05 add a zsh identifier sanitizer + case-label escaping; F-06 `if (new_path_len >= new_path.len) return error.TooDeep;`.
- **Acceptance criteria:** F-04 `cmd.name="a'b"` -> `'a''b'`; F-05 `subcmd.name="a;b"` -> no `;` in case label/function name; F-06 17-level tree -> graceful error.
- **Issue:** [#132](https://gitlab.com/devnw/zig/cli/-/issues/132)
- **SLA:** 180 days (2026-12-08)

### NS-062: UTF-8 codepoint splitting / byte-vs-column width math [Low] -- CLOSED

- **Status:** **Closed** (2026-06-12) -- fix commits `269e228`, `8e30398`, `6739ffb`; resolution: slice boundaries snap to UTF-8 codepoint starts via `sanitize.utf8FloorIndex` in the table renderer (`src/term/table.zig:235,263`) and `util/text.zig` truncation/padding; `max_width` enforced as an absolute ceiling.
- **Risk Level:** Low
- **Risk Score:** 12 (Impact: 1, Likelihood: 3)
- **CWE:** CWE-697 (Incorrect Comparison) / CWE-1284
- **OWASP:** A04:2021 Insecure Design (data integrity)
- **Exploit Surface:** Local (output correctness; latent integrity issue for downstream UTF-8-validating consumers).
- **Confidence:** `confidence::confirmed`
- **Affected files:** `src/util/text.zig:107,110` (and `center`/`padLeft`/`padRight`/`wordWrap`); `src/term/table.zig:223-224,245,249`
- **Evidence:**

  ```zig
  // util/text.zig:107,110 -- byte-offset slices can split a codepoint:
  if (max_len <= 3) return text[0..max_len];
  try result.appendSlice(allocator, text[0 .. max_len - 3]);
  // table.zig:224 / 245 -- byte slice of multibyte cell; :249 treats bytes as columns
  display_cell = cell[0..col.max_width];
  ```

  In-bounds (guarded by early returns / `cell.len > max_width`), so not memory corruption -- a correctness/robustness defect (invalid UTF-8, mis-aligned columns for CJK/emoji).
- **Fix guidance:** Snap slice boundaries to UTF-8 codepoint starts (`std.unicode.Utf8View` / `utf8ValidateSlice`); compute display width via codepoint/wcwidth, not `.len`.
- **Acceptance criteria:** Truncating/aligning multibyte input yields valid UTF-8 (`utf8ValidateSlice`).
- **Issue:** [#133](https://gitlab.com/devnw/zig/cli/-/issues/133)
- **SLA:** 180 days (2026-12-08)
- **Origin:** Adversarial review R-02 (missed by both prior reviews).

---

## Status Corrections -- codepros:audit iteration 1 (2026-06-11)

### NS-016: Secret flag values "zeroed" in Context.deinit -- CORRECTED to FALSE-RESOLVED, then CLOSED

- **Previous status:** Closed / Implemented (2026-03-24)
- **Corrected status:** **False-Resolved** (2026-06-11)
- **Final status:** **Closed** (2026-06-12) -- remediated via option (a): the `command.zig` doc comment was corrected (commit `928f603`) to state that argv/environ-backed values cannot be scrubbed in `deinit`, and a `freeSecret()` zeroing helper (commit `022e4cf`) is provided for heap-owned secret material returned by `prompt.password()`. The misleading "zeroed" claim is removed.
- **Risk Level:** Low | **Risk Score:** 16 (unchanged)
- **CWE:** CWE-316 / A02:2021
- **Why corrected:** The "zeroing" reassigns the 16-byte slice header (`command.zig:199`: `val.* = FlagValue{ .string = "" }`) but the pointed-to bytes are **OS-owned argv/environ** -- never duplicated (`parser.zig:386`: `.string => FlagValue{ .string = value }`, no `dupe`/`alloc`). The bytes are untouched; the original NS-016 acceptance criterion ("inspect the memory region... verify the value is overwritten") is **not met**.
- **Real-world severity remains Low:** the secret *policy* keeps genuine secrets out of string flags, and argv/environ are OS-visible regardless. The defect is a **false sense of protection**, plus the overstated doc comment at `command.zig:44`.
- **Remediation options:** (a) correct the `command.zig:44` doc comment to state argv/environ-backed values cannot be scrubbed in `deinit`, and mark NS-016 Won't-Fix-with-rationale; or (b) `dupe` secret-flagged values on store and `@memset` the heap copy in `deinit`.
- **Origin:** appsec F-02 / adversarial review (confirmed).

### NS-020: generateMarkdown escaping -- CORRECTED to PARTIALLY FALSE-RESOLVED

- **Previous status:** Closed / Implemented (2026-03-24)
- **Corrected status:** **Partially False-Resolved** (2026-06-11)
- **Risk Level:** Low | **Risk Score:** 16 (unchanged)
- **CWE:** CWE-79 / CWE-116 / A05:2021
- **Why corrected:** `writeMarkdownEscaped` (`help.zig:781`) is applied only to **table cells** (`:845,847,854,862,892,894`). Headings, prose, and code-fence content (`help.zig:807,810,823,830,882`) are emitted **raw**. The NS-020 resolution claimed "table cells **and headings**"; the heading/prose/fence paths are raw.
- **Open remediation tracked as:** **NS-060** ([#131](https://gitlab.com/devnw/zig/cli/-/issues/131)).
- **Origin:** appsec F-03 / adversarial review (confirmed).

### NS-057: signal runCleanupCallbacks reads callback_count without mutex -- REFUTED / WON'T DO

- **Status:** **Won't Do** (refuted as a vulnerability, 2026-06-11)
- **Risk Level:** Info | **Risk Score:** 5
- **CWE:** CWE-362 (Race Condition) -- not exploitable
- **Affected files:** `src/signal.zig:156-167` (`onCleanup`), `:315-325` (`runCleanupCallbacks`)
- **Why refuted:** `onCleanup` writes `cleanup_callbacks[count]` **then** `callback_count.store(count + 1, .release)` under the mutex; `runCleanupCallbacks` does `callback_count.load(.acquire)` **then** iterates `cleanup_callbacks[0..count]`. The `.release`/`.acquire` pairing establishes a happens-before edge: any callback counted by the load is fully written and visible. The array is append-only; a concurrent registration completing after the load is merely deferred to the next `pollSignals()` -- a missed-this-cycle, not a torn read or OOB. No uninitialized slot can be invoked.
- **Resolution:** Architecturally safe. The scan candidate NS-057's own "what would confirm" condition (acquire/release pairing present) is satisfied. Recorded as Won't Do; no code change required.
- **Origin:** scan candidate NS-057 / adversarial review adjudication.

---

## Closed Findings -- Phase 3 Follow-up (2026-03-25)

### NS-047: Windows password echo not suppressed [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Medium
- **Risk Score:** 35 (Impact: 5, Likelihood: 1.4)
- **CWE:** CWE-549 (Missing Password Field Masking)
- **OWASP:** A07:2021 Identification and Authentication Failures
- **Exploit Surface:** Local access (Windows only, requires screen visibility)
- **Confidence:** `confidence::confirmed` -- code inspection shows Windows path at `prompt.zig:179-183` falls back to `inputSimple()` without disabling echo.
- **Affected files:** `src/prompt.zig:179-183`
- **Evidence:**

  ```zig
  // prompt.zig:179-183 -- Windows fallback, no echo suppression:
  } else {
      // Windows: Use _getch or similar
      // For now, fall back to regular input
      return inputSimple(stdin, allocator);
  }
  ```

- **Fix guidance:** Use Windows Console API (`SetConsoleMode` to clear `ENABLE_ECHO_INPUT`) or `_getch()` for character-at-a-time input without echo.
- **Acceptance criteria:** Windows password input does not echo characters. Console mode restored on exit.
- **Issue:** [#111](https://gitlab.com/devnw/zig/cli/-/issues/111) (confidential)
- **Cross-ref:** [#104 (NQ-052)](https://gitlab.com/devnw/zig/cli/-/issues/104) -- same root cause from quality perspective
- **SLA:** 90 days (2026-06-23)

### NS-048: Fish escapeFishSingleQuote does not strip NUL/newline/CR [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-74 (Improper Neutralization of Special Elements in Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Supply chain (compile-time constants only; requires compromised library consumer)
- **Confidence:** `confidence::confirmed` -- code inspection shows `escapeFishSingleQuote` (fish.zig:17-43) only escapes `'` and `\`. NUL, newline, CR pass through. Bash (NS-008) and zsh (NS-009) were fixed; fish was not.
- **Affected files:** `src/cli/completion/fish.zig:17-43`
- **Evidence:**

  ```zig
  // fish.zig:20-26 -- only these chars are checked:
  switch (c) {
      '\'', '\\' => { needs_escape = true; break; },
      else => {},  // NUL, newline, CR pass through
  }
  ```

- **Fix guidance:** Add `0x00`, `\n`, `\r` to the filter. Strip NUL bytes. Escape or strip newline/CR.
- **Acceptance criteria:** NUL/newline/CR neutralized. Unit test confirms. Parity with bash/zsh.
- **Issue:** [#115](https://gitlab.com/devnw/zig/cli/-/issues/115) (confidential)
- **SLA:** 90 days (2026-06-23)

### NS-049: PowerShell escapePowerShellString does not strip NUL/newline/CR [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-74 (Improper Neutralization of Special Elements in Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Supply chain (compile-time constants only; requires compromised library consumer)
- **Confidence:** `confidence::confirmed` -- code inspection shows `escapePowerShellString` (powershell.zig:174-194) only doubles single quotes. NUL could truncate string; newline could break syntax.
- **Affected files:** `src/cli/completion/powershell.zig:174-194`
- **Evidence:**

  ```zig
  // powershell.zig:176-181 -- only single quote checked:
  for (s) |c| {
      if (c == '\'') { needs_escape = true; break; }
  }
  // NUL, newline, CR not filtered
  ```

- **Fix guidance:** Add NUL/newline/CR filtering. Strip NUL. Escape or strip newline/CR.
- **Acceptance criteria:** NUL/newline/CR neutralized. Unit test confirms. Parity with bash/zsh.
- **Issue:** [#117](https://gitlab.com/devnw/zig/cli/-/issues/117) (confidential)
- **SLA:** 90 days (2026-06-23)

### NS-050: applyEnvDefaults ignores subcommand flags [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Low
- **Risk Score:** 15 (Impact: 3, Likelihood: 1)
- **CWE:** CWE-1188 (Initialization with Hard-Coded Network Resource Configuration Data)
- **OWASP:** A07:2021 Identification and Authentication Failures
- **Exploit Surface:** Indirect (may force less secure secret delivery via CLI args)
- **Confidence:** `confidence::confirmed` -- code inspection shows `applyEnvDefaults` (parser.zig:508-544) only iterates `self.root.flags`. Subcommand flags with `env` names are never checked.
- **Affected files:** `src/cli/parser.zig:508-544`
- **Evidence:**

  ```zig
  // parser.zig:522 -- only root flags iterated:
  for (self.root.flags) |flag| {
      if (flag.env) |env_name| { ... }
  }
  ```

- **Fix guidance:** After subcommand resolution, iterate the resolved command's flags for env defaults.
- **Acceptance criteria:** Subcommand env flags populated from environment. Test confirms.
- **Issue:** [#118](https://gitlab.com/devnw/zig/cli/-/issues/118)
- **Cross-ref:** [#95 (GAP-0090)](https://gitlab.com/devnw/zig/cli/-/issues/95) -- same root cause from functional perspective
- **SLA:** 180 days (2026-09-21)

### NS-051: Fish buildCondition/buildSubcommandCondition emit unescaped command names [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Low
- **Risk Score:** 15 (Impact: 3, Likelihood: 1)
- **CWE:** CWE-78 (OS Command Injection)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Supply chain (compile-time constants only)
- **Confidence:** `confidence::confirmed` -- code inspection shows `buildCondition` and `buildSubcommandCondition` (fish.zig:181-237) use raw `{s}` interpolation for path elements and `subcmd.name`. Partial regression of GAP-S018/NS-010 pattern.
- **Affected files:** `src/cli/completion/fish.zig:181-237`
- **Evidence:**

  ```zig
  // fish.zig:193 -- unescaped path element:
  w.print(" {s}", .{p}) catch return "";
  // fish.zig:201 -- unescaped subcmd.name:
  w.print(" {s}", .{subcmd.name}) catch return "";
  ```

- **Fix guidance:** Escape names via `escapeFishSingleQuote()` and wrap in single quotes.
- **Acceptance criteria:** Names in fish conditions are escaped. Test confirms metacharacter safety.
- **Issue:** [#119](https://gitlab.com/devnw/zig/cli/-/issues/119)
- **SLA:** 180 days (2026-09-21)

### NS-052: sanitizeBashIdentifier static mutable buffer [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Low
- **Risk Score:** 10 (Impact: 2, Likelihood: 1)
- **CWE:** CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization)
- **OWASP:** A04:2021 Insecure Design
- **Exploit Surface:** Internal (requires concurrent threading, unlikely in CLI context)
- **Confidence:** `confidence::confirmed` -- code inspection shows `sanitizeBashIdentifier` (bash.zig:86-99) uses a `struct { var buf: [256]u8 }` static buffer. Returned slice points into shared static memory.
- **Affected files:** `src/cli/completion/bash.zig:86-99`
- **Evidence:**

  ```zig
  // bash.zig:87-88 -- static mutable buffer:
  const S = struct {
      var buf: [256]u8 = undefined;
  };
  // bash.zig:98 -- returns slice into static buffer:
  return S.buf[0..len];
  ```

- **Fix guidance:** Accept an allocator and return an allocated slice, consistent with other escape functions.
- **Acceptance criteria:** No static mutable buffer. Concurrent calls produce correct results.
- **Issue:** [#120](https://gitlab.com/devnw/zig/cli/-/issues/120)
- **SLA:** 180 days (2026-09-21)

### NS-053: writeMarkdownEscaped incomplete -- backticks not escaped [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Low
- **Risk Score:** 8 (Impact: 2, Likelihood: 1)
- **CWE:** CWE-116 (Improper Encoding or Escaping of Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Indirect (depends on downstream Markdown renderer)
- **Confidence:** `confidence::confirmed` -- code inspection shows `writeMarkdownEscaped` (help.zig:757-771) only escapes `|`. Backticks and angle brackets pass through.
- **Affected files:** `src/cli/help.zig:757-771`
- **Evidence:**

  ```zig
  // help.zig:762 -- only pipe characters:
  if (c == '|') {
      // ... escape
  }
  // Backticks, <, > not handled
  ```

- **Fix guidance:** Escape backticks as `` \` `` and angle brackets as `&lt;`/`&gt;`.
- **Acceptance criteria:** Backticks and angle brackets escaped. Unit test confirms.
- **Issue:** [#121](https://gitlab.com/devnw/zig/cli/-/issues/121)
- **SLA:** 180 days (2026-09-21)

### NS-054: @intCast on potentially negative terminal dimension on Windows [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **Risk Level:** Low
- **Risk Score:** 8 (Impact: 2, Likelihood: 1)
- **CWE:** CWE-681 (Incorrect Conversion between Numeric Types)
- **OWASP:** A06:2021 Vulnerable and Outdated Components
- **Exploit Surface:** Local (Windows only, unusual console state)
- **Confidence:** `confidence::confirmed` -- code inspection shows `@intCast` on signed subtraction result at `tty.zig:122-123`. If `Right < Left`, result is negative and `@intCast` to `u16` panics.
- **Affected files:** `src/term/tty.zig:122-123`
- **Evidence:**

  ```zig
  // tty.zig:122-123 -- potentially negative subtraction cast to u16:
  const width = @as(u16, @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1));
  const height = @as(u16, @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1));
  ```

- **Fix guidance:** Check for negative result before casting; return `null` if negative.
- **Acceptance criteria:** Negative dimensions return `null` instead of panicking.
- **Issue:** [#122](https://gitlab.com/devnw/zig/cli/-/issues/122)
- **SLA:** 180 days (2026-09-21)

---

## Closed Findings -- Previously REGRESSED (19 re-fixed + 3 new closed)

All 19 regressed findings have been re-implemented and verified. Three new findings
have also been closed. All confirmed by code inspection and 710/710 tests passing
with 0 memory leaks on 2026-03-24.

### GAP-0008: Shell injection via PAGER environment variable [Critical] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Critical
- **Risk Score:** 95
- **CWE:** CWE-78 (OS Command Injection)
- **Resolution:** `/bin/sh -c` replaced with direct argv execution. Pager command is split on whitespace and passed directly to `Child.init`. Shell metacharacters in PAGER are not interpreted.
- **Evidence:** `pager.zig:57-58` uses `env_mod.getEnvValueRuntime()` + direct argv.
- **Resolved:** 2026-03-24

### GAP-0011: Shell completion injection in all 4 generators [High] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** High
- **Risk Score:** 85
- **CWE:** CWE-94 (Code Injection)
- **Resolution:** Shell-specific escape functions implemented in all 4 generators: `escapeBashDoubleQuote`, `escapeBashCasePattern` (bash.zig); `escapeZshSingleQuote`, `escapeZshDoubleQuote` (zsh.zig); `escapeFishSingleQuote` (fish.zig); `escapePowerShellString`, `escapeRegex` (powershell.zig). Applied at all injection points. Unit tests verify metacharacter handling.
- **Evidence:** 41 escape references in bash.zig, 32 in zsh.zig, 18 in fish.zig, 35 in powershell.zig.
- **Resolved:** 2026-03-24

### GAP-0009: PowerShell `escapePowerShellString()` is no-op [High] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** High
- **Risk Score:** 80
- **CWE:** CWE-94 (Code Injection)
- **Resolution:** `escapePowerShellString` now doubles single quotes (`'` -> `''`). `escapeRegex` now escapes all regex metacharacters. Both have unit tests.
- **Evidence:** `powershell.zig` escape functions confirmed functional.
- **Resolved:** 2026-03-24

### GAP-0012: JSON help output lacks JSON escaping [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 65
- **CWE:** CWE-116
- **Resolution:** `writeJsonEscapedString` helper added at `help.zig:450`. Applied to all string interpolations in `printJsonHelp`/`printJsonFlag`. Escapes `"`, `\`, `\n`, `\r`, `\t`, and control chars.
- **Resolved:** 2026-03-24

### GAP-0014: Signal handler data race on callback_count [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 60
- **CWE:** CWE-362
- **Resolution:** `callback_count` changed to `std.atomic.Value(usize)` at `signal.zig:60`. All reads use `.load(.acquire)`, all writes use `.store(.release)`.
- **Resolved:** 2026-03-24

### GAP-0013: Man page roff injection [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 55
- **CWE:** CWE-116
- **Resolution:** `writeRoffEscaped` helper added at `help.zig:549`. Applied to all user-controlled strings in `generateMan()`. Escapes `\`, `-`, and leading `.`/`'`.
- **Resolved:** 2026-03-24

### GAP-0015: POSIX password buffer not zeroed after use [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 55
- **CWE:** CWE-316
- **Resolution:** `defer @memset(&buffer, 0)` added at `prompt.zig:164` in POSIX password path.
- **Resolved:** 2026-03-24

### GAP-0010: PowerShell `escapeRegex()` is no-op [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 50
- **CWE:** CWE-94
- **Resolution:** `escapeRegex` now escapes all PowerShell regex metacharacters. Unit tests verify correctness.
- **Resolved:** 2026-03-24

### GAP-0037: SecretPolicy bypass via default_str [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 50
- **CWE:** CWE-798
- **Resolution:** `if (flag.secret == .from_file_or_stdin) continue;` added in `applyDefaultsForCommand` at `parser.zig:434` and `applyEnvDefaults` at `parser.zig:480`. Secret-policy flags never have defaults applied.
- **Resolved:** 2026-03-24

### GAP-S012: Windows password buffer not zeroed [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 40
- **CWE:** CWE-316
- **Resolution:** `defer @memset(&buffer, 0)` added at `prompt.zig:186` in Windows `inputSimple()` path.
- **Resolved:** 2026-03-24

### GAP-S013: Zsh writeZshFlag() help text unescaped [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 35
- **CWE:** CWE-78
- **Resolution:** `writeZshFlag()` now escapes `flag.help` via `escapeZshSingleQuote()` using ArenaAllocator.
- **Resolved:** 2026-03-24

### GAP-S014: Zsh @memcpy no bounds check [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 35
- **CWE:** CWE-787
- **Resolution:** Bounds check added before `@memcpy` in zsh completion value buffer. Values exceeding buffer are truncated safely.
- **Resolved:** 2026-03-24

### GAP-S015: Fish completion values unescaped [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 30
- **CWE:** CWE-78
- **Resolution:** Fish completion values escaped via `escapeFishSingleQuote()`. Applied at all `-a '...'` injection points.
- **Resolved:** 2026-03-24

### GAP-S016: PowerShell subcmd.name unescaped [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 30
- **CWE:** CWE-78
- **Resolution:** `escapePowerShellString()` now functional (GAP-0009). Applied to all subcommand and flag names in PowerShell output.
- **Resolved:** 2026-03-24

### GAP-0016: Predictable temp file in writeFileAtomic [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 35
- **CWE:** CWE-377
- **Resolution:** Random suffix via `std.crypto.random.int(u32)` at `fs.zig:59`. `errdefer` cleanup on failure.
- **Resolved:** 2026-03-24

### GAP-0017: `isSafePath()` expanded blocklist [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 25
- **CWE:** CWE-22
- **Resolution:** Blocklist expanded to include `/etc/passwd`, `/etc/gshadow`, `/proc/self/`, `.ssh/` at `fs.zig:127-142`. Path traversal (`..`) detection added. Unit tests for each blocked path.
- **Resolved:** 2026-03-24

### GAP-S017: Fish subcmd.name unescaped in -a argument [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 25
- **CWE:** CWE-78
- **Resolution:** `subcmd.name` escaped via `escapeFishSingleQuote()` in fish completion output.
- **Resolved:** 2026-03-24

### GAP-S020: Bash flag.name unescaped in variable assignment [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 15
- **CWE:** CWE-78
- **Resolution:** Flag names escaped via `escapeBashDoubleQuote()` in bash completion output.
- **Resolved:** 2026-03-24

### GAP-S021: Zsh subcmd.name unescaped in case pattern [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 15
- **CWE:** CWE-78
- **Resolution:** Subcommand name escaped in zsh case patterns.
- **Resolved:** 2026-03-24

---

## New Findings (3) -- ALL CLOSED

### NEW-S001: Active help message shell injection in bash/zsh [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 45
- **CWE:** CWE-78 (OS Command Injection)
- **Resolution:** Active help messages now escaped via `escapeBashDoubleQuote()` in bash.zig and `escapeZshDoubleQuote()` in zsh.zig. Shell metacharacters in help messages are rendered literally.
- **Resolved:** 2026-03-24

### NEW-S002: Fish flag.help/subcmd.summary unescaped in single-quoted strings [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 15
- **CWE:** CWE-78 (OS Command Injection)
- **Resolution:** `flag.help` and `subcmd.summary` escaped via `escapeFishSingleQuote()` in fish.zig at all single-quoted injection points.
- **Resolved:** 2026-03-24

### NEW-S003: Levenshtein buffer overflow [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 10
- **CWE:** CWE-120 (Buffer Copy without Checking Size of Input)
- **Resolution:** Bounds check added at `suggest.zig:16-17`: `if (b.len >= 256) return @max(a.len, b.len)` and same for `a`. Prevents out-of-bounds write.
- **Resolved:** 2026-03-24

---

## Previously Open -- Now Closed

### NS-002: Inconsistent shell escaping in fish/zsh/bash completion generators [Low] -- CLOSED

- **Status:** Closed / Implemented (subsumed by GAP-0011 closure)
- **Risk Level:** Low
- **Risk Score:** 8
- **CWE:** CWE-78 (OS Command Injection)
- **Issue:** [#38](https://gitlab.com/devnw/zig/cli/-/issues/38)
- **Resolution:** All 7 original injection points now covered by escape functions implemented as part of GAP-0011 closure. Escape functions applied at all string interpolation sites in all 4 completion generators.
- **Resolved:** 2026-03-24

---

## Phase 3 Deep-Inspection Findings (13 -- All Closed)

### NS-008: Bash escape functions don't filter NUL/newline bytes [Medium]

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-74 (Improper Neutralization of Special Elements in Output), CWE-78 (OS Command Injection)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (if CLI is used as a library with attacker-controlled input)
- **Confidence:** `confidence::confirmed` -- code inspection shows `escapeBashDoubleQuote` (bash.zig:17-44) only escapes `$`, `` ` ``, `"`, `\`, `!`. NUL bytes (`\x00`) and newlines (`\n`) pass through unfiltered.
- **Affected files:** `src/cli/completion/bash.zig:17-44`
- **Evidence:**

  ```zig
  // bash.zig:20-28 -- only these chars are checked:
  switch (c) {
      '$', '`', '"', '\\', '!' => { ... },
      else => {},
  }
  ```

- **Attack scenario:** An attacker who controls a command name, flag name, or help string containing a newline could break out of the current bash statement context. A NUL byte could cause early string termination in some shells.
- **Fix guidance:** Add `0x00` (NUL) and `\n` (newline) to the escape character set. NUL bytes should be stripped entirely. Newlines should be escaped as `\\n` or stripped.
- **Acceptance criteria:** `escapeBashDoubleQuote` strips NUL bytes and escapes or strips newline characters. Unit test confirms NUL and newline are neutralized.
- **How to verify:** Pass a string containing `\x00` and `\n` to `escapeBashDoubleQuote` and confirm neither appears in the output.
- **Resolution:** NUL bytes stripped, newlines escaped in `escapeBashDoubleQuote` and `escapeBashCasePattern`. Unit tests confirm NUL and newline neutralization.
- **Resolved:** 2026-03-24

### NS-009: Zsh escape functions don't filter NUL/newline bytes [Medium]

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-74 (Improper Neutralization of Special Elements in Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (if CLI is used as a library with attacker-controlled input)
- **Confidence:** `confidence::confirmed` -- code inspection shows `escapeZshDoubleQuote` (zsh.zig:42-68) only escapes `$`, `` ` ``, `"`, `\`. NUL and newline bytes pass through.
- **Affected files:** `src/cli/completion/zsh.zig:42-68`
- **Evidence:**

  ```zig
  // zsh.zig:46-50 -- only these chars are checked:
  switch (c) {
      '$', '`', '"', '\\' => { ... },
      else => {},
  }
  ```

- **Attack scenario:** Same as NS-008 but targeting zsh completion scripts. A newline in a value string could inject arbitrary zsh commands.
- **Fix guidance:** Add NUL and newline filtering to `escapeZshDoubleQuote` and `escapeZshSingleQuote`. Strip NUL bytes entirely. Escape or strip newlines.
- **Acceptance criteria:** Both zsh escape functions strip NUL bytes and neutralize newlines. Unit tests confirm.
- **How to verify:** Pass strings containing `\x00` and `\n` to both zsh escape functions and confirm they are neutralized.
- **Resolution:** NUL bytes stripped, newlines escaped in `escapeZshDoubleQuote` and `escapeZshSingleQuote`. Unit tests confirm.
- **Resolved:** 2026-03-24

### NS-010: Fish completion outputs unescaped command/flag names into shell syntax [Medium]

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-78 (OS Command Injection)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (if CLI is used as a library with attacker-controlled input)
- **Confidence:** `confidence::confirmed` -- code inspection shows `root_name`, `cmd.name`, and `flag.name` are written directly into fish shell syntax at multiple locations without escaping. Only descriptions are escaped.
- **Affected files:** `src/cli/completion/fish.zig:58,86,100,107,147,152`
- **Evidence:**

  ```zig
  // fish.zig:58 -- root_name used directly:
  try w.print("complete -c {s} -f\n\n", .{cmd.name});
  // fish.zig:107 -- flag.name used directly:
  try w.print(" -l {s}", .{flag.name});
  // fish.zig:152 -- subcmd.name in -a without quotes:
  try w.print(" -a {s} -d '{s}'\n", .{ subcmd.name, esc_summary });
  ```

- **Attack scenario:** A library user with a command name containing shell metacharacters (e.g., `my;cmd`) would produce fish completion output that executes arbitrary code when sourced.
- **Fix guidance:** Escape `root_name`, `cmd.name`, `flag.name`, and `subcmd.name` with `escapeFishSingleQuote()` and wrap in single quotes, or validate that names contain only safe characters (alphanumeric, `-`, `_`).
- **Acceptance criteria:** All command/flag/subcommand names in fish output are either escaped+quoted or validated as safe shell identifiers. Unit test confirms metacharacters in names do not produce injectable output.
- **How to verify:** Generate fish completions for a command with name `test;echo pwned` and verify the output does not contain an unquoted semicolon.
- **Resolution:** Fish completion names (`root_name`, `cmd.name`, `flag.name`, `subcmd.name`) now escaped via `escapeFishSingleQuote()` and wrapped in single quotes at all output sites. Unit tests confirm metacharacters are neutralized.
- **Resolved:** 2026-03-24

### NS-011: writeRoffEscaped doesn't handle newlines -- roff directive injection [Medium]

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 2, Likelihood: 3)
- **CWE:** CWE-74 (Improper Neutralization of Special Elements in Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (man page rendering from CLI-generated content)
- **Confidence:** `confidence::confirmed` -- code inspection shows `writeRoffEscaped` (help.zig:549-571) only checks for leading `.`/`'` at `i==0`, not after newlines. A newline followed by `.` or `'` would start a new roff directive.
- **Affected files:** `src/cli/help.zig:549-571`
- **Evidence:**

  ```zig
  // help.zig:554-559 -- only checks i==0:
  '.' => {
      if (i == 0) {
          try w.writeAll("\\&.");
      } else {
          try w.writeByte(c);
      }
  },
  ```

- **Attack scenario:** A help string or description containing `\n.TH` or `\n.SH` would inject roff directives into the generated man page, potentially altering its rendering or injecting misleading content.
- **Fix guidance:** Track whether the previous character was a newline (or split on `\n` and escape the start of each line). Escape `.` and `'` at the start of every line, not just the start of the entire string.
- **Acceptance criteria:** `writeRoffEscaped` escapes `.` and `'` at the start of every line within the string. Unit test confirms `"line1\n.TH"` produces `"line1\n\\&.TH"`.
- **How to verify:** Pass `"safe text\n.SH INJECTED"` to `writeRoffEscaped` and verify the `.SH` is escaped.
- **Resolution:** `writeRoffEscaped` now tracks newline state and escapes `.` and `'` at the start of every line, not just the start of the string. Unit test confirms `"line1\n.TH"` produces `"line1\n\\&.TH"`.
- **Resolved:** 2026-03-24

### NS-012: printVersionImpl writes cmd.name/version into JSON without escaping [Medium]

- **Status:** Closed / Implemented
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 2, Likelihood: 3)
- **CWE:** CWE-116 (Improper Encoding or Escaping of Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (JSON output consumed by tooling)
- **Confidence:** `confidence::confirmed` -- code inspection shows `printVersionImpl` (help.zig:657) interpolates `cmd.name` and `cmd.version` directly into a JSON template without using `writeJsonEscapedString`.
- **Affected files:** `src/cli/help.zig:657`
- **Evidence:**

  ```zig
  // help.zig:657 -- direct interpolation, no JSON escaping:
  try w.print("{{\"name\":\"{s}\",\"version\":\"{s}\"}}\n", .{
      cmd.name,
      if (cmd.version.len > 0) cmd.version else "0.0.0",
  });
  ```

- **Attack scenario:** A library user whose command name or version contains `"` or `\` would produce malformed JSON. Downstream tools parsing this JSON could crash or misinterpret the data. Note: `writeJsonEscapedString` was added for `printJsonHelp` (GAP-0012) but was not applied to `printVersionImpl`.
- **Fix guidance:** Use the existing `writeJsonEscapedString` helper for `cmd.name` and `cmd.version` in `printVersionImpl`.
- **Acceptance criteria:** `printVersionImpl` uses `writeJsonEscapedString` for all string values. Unit test confirms a version string containing `"` produces valid JSON.
- **How to verify:** Create a command with `version = "1.0\"beta"` and verify `--version --json` produces valid JSON.
- **Resolution:** `printVersionImpl` now uses `writeJsonEscapedString` for `cmd.name` and `cmd.version`. Shared `default_version` constant used for fallback. Also closes NQ-039.
- **Resolved:** 2026-03-24

### NS-013: Signal handler invokes non-async-signal-safe user callbacks [Medium]

- **Status:** Closed / Documented
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-364 (Signal Handler Race Condition), CWE-479 (Signal Handler Use of a Non-Reentrant Function)
- **OWASP:** A04:2021 Insecure Design
- **Exploit Surface:** Internal (requires process to receive a signal during callback execution)
- **Confidence:** `confidence::confirmed` -- code inspection shows `posixSignalHandler` (signal.zig:161-177) calls `runCleanupCallbacks()` (signal.zig:262-271), which iterates user-registered callbacks directly in signal handler context. User callbacks have no async-signal-safety constraint enforced at compile time.
- **Affected files:** `src/signal.zig:161-177,262-271`
- **Evidence:**

  ```zig
  // signal.zig:175-176 -- called from signal handler:
  // Run cleanup callbacks
  runCleanupCallbacks();

  // signal.zig:262-271 -- invokes arbitrary user callbacks:
  fn runCleanupCallbacks() void {
      const count = callback_count.load(.acquire);
      for (cleanup_callbacks[0..count]) |maybe_cb| {
          if (maybe_cb) |cb| {
              cb();  // user callback -- not guaranteed async-signal-safe
          }
      }
  }
  ```

- **Attack scenario:** A user registers a cleanup callback that performs heap allocation, file I/O, or mutex locking. A signal arrives during the same operation, causing the callback to deadlock or corrupt heap state. This is undefined behavior per POSIX.
- **Fix guidance:** Use a flag-and-poll pattern: have the signal handler set an atomic flag, and run cleanup callbacks from normal (non-signal) context. Alternatively, document the strict requirement and add a compile-time or runtime assertion that callbacks are async-signal-safe. Note that GAP-S019 added documentation but the runtime behavior remains unsafe.
- **Acceptance criteria:** Either (a) cleanup callbacks are no longer invoked directly from signal handler context, or (b) the API enforces and documents that only async-signal-safe operations are permitted, with runtime validation where possible.
- **How to verify:** Review `posixSignalHandler` to confirm it only sets atomic flags and does not call user code. Alternatively, verify documentation is clear and a test demonstrates the flag-and-poll pattern.
- **Resolution:** Signal handler async-safety constraints documented with clear API contract. Doc comments on `onCleanup()` and `posixSignalHandler` state that registered callbacks must be async-signal-safe. Also closes NQ-032.
- **Resolved:** 2026-03-24

### NS-014: Bash writes cmd.name directly into shell function names [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 12 (Impact: 3, Likelihood: 1)
- **CWE:** CWE-78 (OS Command Injection)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (if CLI is used as a library with attacker-controlled input)
- **Confidence:** `confidence::suspected` -- `cmd.name` is typically developer-controlled at compile time, but the library API does not validate it. Would confirm by testing with a cmd.name containing shell metacharacters.
- **Affected files:** `src/cli/completion/bash.zig:94,106,112`
- **Evidence:**

  ```zig
  // bash.zig:94 -- cmd.name in shell comment (low risk):
  try w.print("# Bash completion for {s}\n", .{cmd.name});
  // bash.zig:106 -- cmd.name in function name:
  try w.print("_{s}() {{\n", .{cmd.name});
  // bash.zig:112 -- cmd.name in complete command:
  try w.print("complete -F _{s} {s}\n", .{ cmd.name, cmd.name });
  ```

- **Attack scenario:** A library consumer passes a command name containing shell metacharacters. The generated bash completion script would contain injectable function definitions. Likelihood is low because command names are typically hardcoded.
- **Fix guidance:** Validate `cmd.name` contains only `[a-zA-Z0-9_-]` before using it in shell syntax, or escape it appropriately.
- **Acceptance criteria:** Command names used in bash function definitions and `complete` commands are validated or escaped. Test confirms a name with `;` is either rejected or neutralized.
- **How to verify:** Generate bash completions with `cmd.name = "test;id"` and inspect the output.
- **Resolution:** Added `sanitizeBashIdentifier(name)` function in `bash.zig` that replaces non-`[a-zA-Z0-9_]` characters with underscores. Used for function names in `generateWithActiveHelp` and `generateActiveHelpSupport`. `complete -F` registration still uses the original `cmd.name`. Three tests added: hyphens/dots sanitized, alphanumerics preserved, cmd.name with hyphens produces valid function names.
- **Resolved:** 2026-03-24

### NS-015: PowerShell completion values not escaped [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 12 (Impact: 3, Likelihood: 1)
- **CWE:** CWE-74 (Improper Neutralization of Special Elements in Output)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (if CLI is used as a library with attacker-controlled input)
- **Confidence:** `confidence::confirmed` -- code inspection shows `flag.completions` values at powershell.zig:161 are interpolated into single-quoted PowerShell strings without escaping via `escapePowerShellString`.
- **Affected files:** `src/cli/completion/powershell.zig:161`
- **Evidence:**

  ```zig
  // powershell.zig:161 -- value written directly:
  try w.print("{s}    [CompletionResult]::new('{s}', '{s}', ...", .{
      indent, value, value, flag.name,
  });
  ```

- **Attack scenario:** A flag completion value containing a single quote (`'`) could break out of the PowerShell string literal and inject arbitrary PowerShell code.
- **Fix guidance:** Apply `escapePowerShellString()` to `value` before interpolation.
- **Acceptance criteria:** All `flag.completions` values in PowerShell output are escaped via `escapePowerShellString`. Test confirms a value containing `'` produces valid PowerShell.
- **How to verify:** Generate PowerShell completions for a flag with a completion value of `it's` and verify the output contains `it''s`.
- **Resolution:** Applied `escapePowerShellString()` to `flag.name` and `flag.completions` values in `writePowerShellFlag`. Single quotes in values are now doubled as `''`.
- **Resolved:** 2026-03-24

### NS-016: Secret flag values not zeroed from memory after use [Low] -- FALSE-RESOLVED (corrected 2026-06-11)

> **STATUS CORRECTION (2026-06-11):** Reassigning the slice header does NOT scrub the
> OS-owned argv/environ bytes. Status changed from Closed to **False-Resolved**. See the
> "Status Corrections -- codepros:audit iteration 1" section above. The resolution text below
> reflects the original (incorrect) 2026-03-24 determination and is retained for history.

- **Status:** ~~Closed / Implemented~~ -> **False-Resolved**
- **Risk Level:** Low
- **Risk Score:** 16 (Impact: 2, Likelihood: 2)
- **CWE:** CWE-316 (Cleartext Storage of Sensitive Information in Memory)
- **OWASP:** A02:2021 Cryptographic Failures
- **Exploit Surface:** Internal (requires memory access to the process)
- **Confidence:** `confidence::suspected` -- `Context.deinit()` (command.zig:134-146) frees flag storage but does not zero secret-flagged values before freeing. Would confirm by inspecting freed memory after `deinit()`.
- **Affected files:** `src/cli/command.zig:134-146`
- **Evidence:**

  ```zig
  // command.zig:134-146 -- no zeroing of secret values:
  pub fn deinit(self: *Context) void {
      var iter = self.flags.valueIterator();
      while (iter.next()) |val| {
          switch (val.*) {
              .string_array => |*arr| arr.deinit(self.allocator),
              else => {},
          }
      }
      self.flags.deinit();
      // ... no @memset of secret flag values before freeing
  }
  ```

- **Attack scenario:** A process uses secret-flagged CLI arguments (passwords, tokens). After `Context.deinit()`, the secret values remain in freed heap memory and could be read by a memory dump, core dump, or heap spray attack.
- **Fix guidance:** In `deinit()`, iterate flags and check if the corresponding `FlagSpec` has `secret != .none`. For those flags, zero the string value before freeing. This mirrors the pattern used in `prompt.zig` for password buffers.
- **Acceptance criteria:** `Context.deinit()` zeros all flag values where the corresponding `FlagSpec.secret` is set. Unit test confirms secret flag memory is zeroed after deinit.
- **How to verify:** Set a secret flag value, call `deinit()`, and inspect the memory region (or verify via test that the value is overwritten).
- **Resolution:** `Context.deinit()` now zeros string flag values by setting `val.* = FlagValue{ .string = "" }` before HashMap deallocation. All string flag values (not just secrets) are zeroed as a defense-in-depth measure.
- **Resolved:** 2026-03-24

### NS-017: Pager command splitting cannot handle quoted arguments [Low] -- CLOSED

- **Status:** Closed / Documented
- **Risk Level:** Low
- **Risk Score:** 8 (Impact: 1, Likelihood: 2)
- **CWE:** CWE-88 (Improper Neutralization of Argument Delimiters in a Command)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internal (user sets PAGER env var for their own shell)
- **Confidence:** `confidence::confirmed` -- code inspection shows `pager.zig:58-80` splits the PAGER command on whitespace using `tokenizeAny`. This means `PAGER="less -R"` works, but `PAGER='my pager' --opt` does not (the space inside quotes is treated as a delimiter).
- **Affected files:** `src/term/pager.zig:58-80`
- **Evidence:**

  ```zig
  // pager.zig:63-68 -- naive whitespace split:
  var iter = std.mem.tokenizeAny(u8, pager_cmd, " \t");
  while (iter.next()) |token| {
      if (argv_len >= argv_buf.len) break;
      argv_buf[argv_len] = token;
      argv_len += 1;
  }
  ```

- **Attack scenario:** A user sets `PAGER="/usr/local/bin/my pager"` (path with space). The pager fails to launch because the path is split into two tokens. This is a usability issue rather than a security vulnerability.
- **Fix guidance:** Implement basic shell-style quote parsing (handle `'...'` and `"..."` segments) or document the limitation.
- **Acceptance criteria:** Either (a) pager command parsing handles quoted arguments, or (b) the limitation is documented in a doc comment.
- **How to verify:** Set `PAGER="'/usr/bin/less' -R"` and verify the pager launches correctly.
- **Resolution:** Added doc comment on pager command splitting documenting the limitation: no quoted args, max 8 tokens. Acceptance criteria met via documentation path (option b).
- **Resolved:** 2026-03-24

### NS-018: writeFileAtomic temp file inherits umask (world-readable risk) [Low]

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 8 (Impact: 2, Likelihood: 1)
- **CWE:** CWE-377 (Insecure Temporary File)
- **OWASP:** A05:2021 Security Misconfiguration
- **Exploit Surface:** Internal (requires shared filesystem access)
- **Confidence:** `confidence::confirmed` -- code inspection shows `writeFileAtomic` (fs.zig:54-79) creates the temp file via `dir.createFile(temp_path, .{})` with default options. Zig's `createFile` uses mode 0o666 masked by umask. With a permissive umask (e.g., 0o000), the temp file is world-readable/writable.
- **Affected files:** `src/util/fs.zig:54-79`
- **Evidence:**

  ```zig
  // fs.zig:62 -- default file creation options:
  const temp_file = dir.createFile(temp_path, .{}) catch |err| { ... };
  ```

- **Attack scenario:** On a shared system with permissive umask, the temp file is briefly world-readable before being renamed to the target. An attacker with filesystem access could read or replace the temp file contents during this window.
- **Fix guidance:** Set explicit file mode in `createFile` options: `.{ .mode = 0o600 }` to ensure owner-only access regardless of umask.
- **Acceptance criteria:** `writeFileAtomic` creates temp files with mode 0o600. Test confirms temp file permissions.
- **How to verify:** Call `writeFileAtomic`, inspect the temp file permissions (e.g., via `stat`) before the rename completes.
- **Resolution:** `createFile` now uses `.{ .mode = 0o600 }` for owner-only access. Also adds fsync before rename and errdefer cleanup. Closed together with NQ-033.
- **Resolved:** 2026-03-24

### NS-019: Windows active_config race condition [Low] -- CLOSED

- **Status:** Closed / Implemented
- **Risk Level:** Low
- **Risk Score:** 8 (Impact: 2, Likelihood: 1)
- **CWE:** CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization)
- **OWASP:** A04:2021 Insecure Design
- **Exploit Surface:** Internal (Windows only, requires specific call timing)
- **Confidence:** `confidence::suspected` -- code inspection shows `active_config` (signal.zig:63) is a plain global variable written at `installWindows` (signal.zig:194) and read by `windowsCtrlHandler` (signal.zig:243). No synchronization protects this access. Would confirm by testing concurrent `install()` calls on Windows.
- **Affected files:** `src/signal.zig:63,194`
- **Evidence:**

  ```zig
  // signal.zig:63 -- plain global, no synchronization:
  var active_config: Config = .{};
  // signal.zig:194 -- written without lock:
  active_config = config;
  // signal.zig:243 -- read in handler without lock:
  if (!active_config.handle_interrupt) return 0;
  ```

- **Attack scenario:** If `install()` is called from one thread while a console control event fires on another, the handler could read a partially-written `active_config`, leading to incorrect signal handling (e.g., not running cleanup when it should, or vice versa).
- **Fix guidance:** Make `active_config` an atomic or protect it with the existing `mutex`. Alternatively, since `Config` is small (two bools), use an atomic bitfield.
- **Acceptance criteria:** `active_config` reads and writes are synchronized. Unit test or code review confirms no unsynchronized access.
- **How to verify:** Code review confirms `active_config` is either atomic or protected by mutex on both read and write paths.
- **Resolution:** Replaced plain `active_config: Config` with two `std.atomic.Value(bool)` fields: `win_handle_interrupt` and `win_handle_terminate`. `installWindows` stores with `.release` ordering; `windowsCtrlHandler` loads with `.acquire` ordering.
- **Resolved:** 2026-03-24

### NS-020: generateMarkdown has no Markdown escaping [Low] -- PARTIALLY FALSE-RESOLVED (corrected 2026-06-11)

> **STATUS CORRECTION (2026-06-11):** Only table cells are escaped; headings, prose, and
> code-fence content (`help.zig:807,810,823,830,882`) are emitted raw. Status changed from
> Closed to **Partially False-Resolved**. Open remediation tracked as **NS-060** ([#131](https://gitlab.com/devnw/zig/cli/-/issues/131)).
> The resolution text below reflects the original (partial) 2026-03-24 determination.

- **Status:** ~~Closed / Implemented~~ -> **Partially False-Resolved**
- **Risk Level:** Low
- **Risk Score:** 16 (Impact: 2, Likelihood: 2)
- **CWE:** CWE-79 (Improper Neutralization of Input During Web Page Generation)
- **OWASP:** A03:2021 Injection
- **Exploit Surface:** Internet-facing (if generated Markdown is rendered in a web context)
- **Confidence:** `confidence::confirmed` -- code inspection shows `generateMarkdownCommand` (help.zig:681-776) writes `cmd.name`, `cmd.summary`, `cmd.long_help`, `flag.help`, `flag.default_str`, `flag.env`, `subcmd.name`, and `subcmd.summary` directly into Markdown table cells and headings without escaping pipe characters (`|`), backticks, or HTML.
- **Affected files:** `src/cli/help.zig:681-776`
- **Evidence:**

  ```zig
  // help.zig:723 -- flag.help in table cell, no escaping:
  try w.print("`--{s}` | {s}", .{ flag.name, flag.help });
  // help.zig:763 -- subcmd.summary in table cell:
  try w.print("| `{s}` | {s} |\n", .{ subcmd.name, subcmd.summary });
  ```

- **Attack scenario:** A command with `flag.help` containing `|` would break the Markdown table structure. A value containing raw HTML (e.g., `<script>`) could lead to XSS if the generated Markdown is rendered in a web context without sanitization.
- **Fix guidance:** Escape pipe characters (`|` -> `\|`), angle brackets (`<` -> `&lt;`), and backticks in Markdown table cells. For headings, escape `#` at start of lines.
- **Acceptance criteria:** `generateMarkdown` escapes Markdown-significant characters in all user-controlled strings. Test confirms a help string containing `|` and `<script>` produces safe Markdown output.
- **How to verify:** Generate Markdown for a command with `help = "col1 | col2 <script>alert(1)</script>"` and verify the output is properly escaped.
- **Resolution:** Added `writeMarkdownEscaped(w, s)` function that escapes `|` as `\|` in Markdown table cells. Applied to all table cell outputs in `generateMarkdownCommand`. Two tests added verifying pipe escaping.
- **Resolved:** 2026-03-24

---

## Won't Do

### NS-001: CI catalog components pinned to mutable git tags [Medium]

- **Status:** Won't Do
- **Risk Level:** Medium
- **Risk Score:** 24 (Impact: 3, Likelihood: 2)
- **CWE:** CWE-829 (Inclusion of Functionality from Untrusted Control Sphere)
- **Affected files:** `.gitlab-ci.yml` (lines 7-20)
- **Issue:** [#35](https://gitlab.com/devnw/zig/cli/-/issues/35)
- **Reason:** CI catalog components are first-party (devnw). Pinning to SHAs would break the auto-update workflow for these internal components.

### GAP-S022: Fixed-size buffers silently truncate [Low]

- **Status:** Won't Do
- **Risk Level:** Low
- **Risk Score:** 15
- **CWE:** CWE-120 (Buffer Copy without Checking Size of Input)
- **Affected files:** Multiple completion generators, `src/cli/help.zig`
- **Reason:** Fixed-size buffers in completion generators use `catch prefix`/`catch path` fallback patterns for graceful degradation. Command names realistically never approach 256-byte limits. The zsh value_buf was separately addressed in GAP-S014 (now regressed). The risk is accepted as negligible for CLI tooling.
- **Phase 3 note:** Findings BB-1 (bash.zig:121-131, zsh.zig:130-140), BB-2 (bash.zig:159-163), and BB-3 (zsh.zig:248-268) are duplicate/overlap with this entry and do not require separate tracking.

### NS-055: Gitleaks custom rule private-key-file too broad [Info]

- **Status:** Won't Do
- **Risk Level:** Info
- **Risk Score:** 4 (Impact: 1, Likelihood: 1)
- **Affected files:** `.gitleaks.toml:26-31`
- **Evidence:**

  ```toml
  [[rules]]
  id = "private-key-file"
  description = "Private key file reference"
  regex = '''(?i)(private_key|privkey|id_rsa|id_ed25519)'''
  path = '''\.zig$'''
  ```

- **Reason:** The regex matches any mention of `private_key`, `id_rsa`, etc. in Zig source files, creating false positives from test data, documentation strings, and configuration parsing code. This reduces signal-to-noise ratio in secret scanning but does not create a vulnerability. The rule errs on the side of caution, which is acceptable for a secret detection tool.

## Informational Findings (Won't Do / Positive)

### NS-004: Pager executes PAGER env var [Info]

- **Status:** Won't Do
- **Risk Level:** Info
- **Risk Score:** 4 (Impact: 1, Likelihood: 1)
- **Affected files:** `src/term/pager.zig:58-83`
- **Reason:** Standard POSIX behavior. Respecting the `PAGER` environment variable is expected for CLI tools. The implementation now uses direct argv execution (GAP-0008 closed).

### NS-005: isSafePath doesn't resolve symlinks [Info]

- **Status:** Won't Do (documented)
- **Risk Level:** Info
- **Risk Score:** 4 (Impact: 1, Likelihood: 1)
- **CWE:** CWE-59
- **Affected files:** `src/util/fs.zig:126-162`
- **Reason:** Already documented with doc comment (GAP-S018). The function checks string patterns only and recommends `realpathAlloc()` for callers needing stronger guarantees.
- **Phase 3 note:** Finding FS-1 (fs.zig:121-147) is a duplicate of this entry and does not require separate tracking.

### NS-006: 16-level command depth limit in path arrays [Info]

- **Status:** Won't Do
- **Risk Level:** Info
- **Risk Score:** 4 (Impact: 1, Likelihood: 1)
- **CWE:** CWE-120
- **Affected files:** `src/cli/completion/fish.zig:131`
- **Reason:** 16 levels is more than sufficient for any practical CLI application.

### SC-2: Zig dependency hash-pinned (good practice) [Info]

- **Status:** Won't Do (positive -- no action needed)
- **Risk Level:** Info
- **Risk Score:** 4 (Impact: 1, Likelihood: 1)
- **Affected files:** `build.zig.zon:36-38`
- **Reason:** The `config` dependency uses content-hash pinning, which ensures reproducible builds and prevents silent upstream changes. This is a positive security practice already in place.

---

## Closed Findings (Pre-existing -- 4)

### NS-003: Heap-allocated password not zeroed on free [Low]

- **Status:** Closed / Documented
- **Risk Level:** Low
- **Risk Score:** 8 (Impact: 2, Likelihood: 1)
- **CWE:** CWE-316 (Cleartext Storage of Sensitive Information in Memory)
- **Affected files:** `src/prompt.zig:127-133`
- **Resolution:** Password zeroing documented with caller responsibility pattern. Doc comment with code example is present at lines 127-133.
- **Verified:** 2026-03-24 (doc comment confirmed present)

### NS-007: .gitignore does not exclude .env files [Info]

- **Status:** Closed / Implemented
- **Risk Level:** Info
- **Risk Score:** 4 (Impact: 1, Likelihood: 1)
- **CWE:** CWE-540 (Inclusion of Sensitive Information in Source Code)
- **Affected files:** `.gitignore:22-24`
- **Resolution:** .gitignore now excludes `.env`, `.env.*`, and `*.env` patterns.
- **Verified:** 2026-03-24 (confirmed at `.gitignore:22-24`)

### GAP-S018: isSafePath symlink documentation [Low]

- **Status:** Closed / Implemented (partial)
- **Risk Level:** Low
- **Risk Score:** 20
- **CWE:** CWE-59
- **Affected files:** `src/util/fs.zig`
- **Resolution:** Doc comment present on `isSafePath()` documenting the symlink limitation.
- **Verified:** 2026-03-24

### GAP-S019: Signal async-signal-safety documentation [Low]

- **Status:** Closed / Implemented (minimal)
- **Risk Level:** Low
- **Risk Score:** 20
- **CWE:** CWE-364
- **Affected files:** `src/signal.zig`
- **Resolution:** Documentation present on signal cleanup functions.
- **Verified:** 2026-03-24
- **Phase 3 note:** NS-013 tracks the runtime behavior (callbacks still invoked in signal context) as a separate finding. This entry covers only the documentation aspect.

---

## Duplicate/Overlap Notes

The following Phase 3 findings overlap with existing entries and do not require new tracking:

- **FINDING-010** (Fixed-size buffers with silent truncation): Duplicate of existing GAP-S022 (Won't Do).
- **FINDING-012** (Signal cleanup race window): Overlaps with GAP-S019 (Closed, minimal doc).
- **SAFE-PATH-SYMLINK**: Overlaps with GAP-S018 (Closed, partial doc).
- **NS-002** is now largely subsumed by GAP-0011 regression (no escape functions exist at all).
- **SC-1** (CI components pinned by tag not SHA): Already tracked as NS-001 (Won't Do).
- **SC-2** (Zig dependency hash-pinned): Already tracked as positive security posture item.
- **SP-1** (SecretPolicy bypass through subcommand flag inheritance): Already tracked as GAP-0037 (Closed). Phase 3 confirms it is coincidentally safe.
- **BB-1** (env_var_buf 256-byte truncation): Covered by GAP-S022 (Won't Do).
- **BB-2** (func_name_buf 256-byte overflow): Covered by GAP-S022 (Won't Do).
- **BB-3** (writeZshFlag value_buf 512-byte overflow): Covered by GAP-S022 (Won't Do).
- **FS-1** (isSafePath doesn't resolve symlinks): Already tracked as NS-005 / GAP-S018 (Won't Do / Closed).

---

## Findings by Area

### Authentication / Credential Handling

- GAP-0015 (Closed): POSIX password buffer zeroed via defer
- GAP-S012 (Closed): Windows password buffer zeroed via defer
- NS-003 (Closed): Heap-allocated password not zeroed on free -- documented caller responsibility
- **NS-016 (False-Resolved):** Secret flag "zeroing" reassigns a slice header, not OS-owned argv/environ bytes
- **NS-047 (Closed):** Windows password echo not suppressed (primary path) -- falls back to inputSimple() ([#111](https://gitlab.com/devnw/zig/cli/-/issues/111))
- **NS-050 (Closed):** applyEnvDefaults ignores subcommand flags -- env-based secret delivery fails ([#118](https://gitlab.com/devnw/zig/cli/-/issues/118))
- **NS-059 (Open):** Windows `password()` echoes input when GetConsoleMode fails (fallback path) ([#130](https://gitlab.com/devnw/zig/cli/-/issues/130))

### Shell Completion / Injection

- GAP-0008 (Closed): PAGER shell injection -- direct argv exec
- GAP-0009 (Closed): PowerShell `escapePowerShellString()` -- real escaping
- GAP-0010 (Closed): PowerShell `escapeRegex()` -- real escaping
- GAP-0011 (Closed): Shell completion injection -- escape functions in all 4 generators
- GAP-S013 (Closed): Zsh writeZshFlag() help text escaped
- GAP-S015 (Closed): Fish completion values escaped
- GAP-S016 (Closed): PowerShell subcmd.name escaped
- GAP-S017 (Closed): Fish subcmd.name escaped
- GAP-S020 (Closed): Bash flag.name escaped
- GAP-S021 (Closed): Zsh subcmd.name escaped in case pattern
- NEW-S001 (Closed): Active help message shell injection -- escaped
- NEW-S002 (Closed): Fish flag.help/subcmd.summary escaped
- NS-002 (Closed): Inconsistent shell escaping -- subsumed by GAP-0011
- **NS-008 (Closed):** Bash escape NUL/newline filtering implemented
- **NS-009 (Closed):** Zsh escape NUL/newline filtering implemented
- **NS-010 (Closed):** Fish completion names escaped
- **NS-014 (Closed):** Bash function names sanitized via `sanitizeBashIdentifier`
- **NS-015 (Closed):** PowerShell completion values escaped via `escapePowerShellString`
- **NS-048 (Closed):** Fish escapeFishSingleQuote does not strip NUL/newline/CR ([#115](https://gitlab.com/devnw/zig/cli/-/issues/115))
- **NS-049 (Closed):** PowerShell escapePowerShellString does not strip NUL/newline/CR ([#117](https://gitlab.com/devnw/zig/cli/-/issues/117))
- **NS-051 (Closed):** Fish buildCondition emits unescaped command names ([#119](https://gitlab.com/devnw/zig/cli/-/issues/119))
- **NS-052 (Closed):** sanitizeBashIdentifier static mutable buffer ([#120](https://gitlab.com/devnw/zig/cli/-/issues/120))
- **NS-061 (Open):** Completion generator hardening -- PowerShell `-CommandName`, zsh case/identifier, fish [16] OOB ([#132](https://gitlab.com/devnw/zig/cli/-/issues/132))

### Input Validation / Encoding

- GAP-0012 (Closed): JSON help output -- `writeJsonEscapedString` added
- GAP-0013 (Closed): Man page roff injection -- `writeRoffEscaped` added
- GAP-0037 (Closed): SecretPolicy bypass -- secret flags skipped in defaults
- **NS-011 (Closed):** writeRoffEscaped newline handling fixed
- **NS-012 (Closed):** printVersionImpl JSON output escaped via writeJsonEscapedString
- **NS-020 (Partially False-Resolved):** Markdown escaping covers table cells only; headings/prose/fences raw -> NS-060
- **NS-053 (Closed):** writeMarkdownEscaped incomplete -- backticks not escaped ([#121](https://gitlab.com/devnw/zig/cli/-/issues/121))
- **NS-060 (Open):** Markdown headings/prose/code-fences emitted raw ([#131](https://gitlab.com/devnw/zig/cli/-/issues/131))

### Memory Safety

- GAP-S014 (Closed): Zsh @memcpy bounds check added
- NEW-S003 (Closed): Levenshtein buffer overflow -- bounds check added
- GAP-S022 (Won't Do): Fixed-size buffers silently truncate

### Filesystem / Path Handling

- GAP-0016 (Closed): Predictable temp file -- random suffix
- GAP-0017 (Closed): isSafePath() -- expanded blocklist + traversal detection
- GAP-S018 (Closed): isSafePath symlink limitation documented
- **NS-018 (Closed):** writeFileAtomic permissions fixed (mode 0o600)

### Signal Handling / Concurrency

- GAP-0014 (Closed): Signal handler data race -- atomic callback_count
- GAP-S019 (Closed): Signal cleanup callbacks documented
- **NS-013 (Closed):** Signal handler async-safety documented
- **NS-019 (Closed):** Windows active_config replaced with atomic booleans
- **NS-057 (Won't Do):** runCleanupCallbacks reads callback_count without mutex -- refuted (acquire/release pairing is sound)

### Terminal / TTY / Output Encoding

- **NS-054 (Closed):** @intCast on potentially negative terminal dimension on Windows ([#122](https://gitlab.com/devnw/zig/cli/-/issues/122))
- **NS-056 (Open):** Terminal escape-sequence injection -- no ESC stripping on TTY output (live-by-default via unknown-command path) ([#128](https://gitlab.com/devnw/zig/cli/-/issues/128))
- **NS-058 (Open):** ProgressBar.init u16 underflow panic (DoS) when terminal width < 20 ([#129](https://gitlab.com/devnw/zig/cli/-/issues/129))
- **NS-062 (Open):** UTF-8 codepoint splitting / byte-vs-column width math in truncate + table renderer ([#133](https://gitlab.com/devnw/zig/cli/-/issues/133))

### Pager

- **NS-017 (Closed):** Pager command splitting limitation documented in doc comment

### Supply Chain / CI/CD

- NS-001 (Won't Do): CI catalog components pinned to mutable git tags

### Repository Configuration

- NS-007 (Closed): .gitignore now excludes .env files
- **NS-055 (Won't Do):** Gitleaks private-key-file rule too broad -- false positives from test data

---

## Positive Security Posture

The following security practices are observed and remain in effect:

1. **No secrets detected.** Gitleaks, TruffleHog, and Trivy scans all returned clean. No hardcoded credentials, API keys, or tokens in the codebase.

2. **Zig toolchain download SHA-256 verified.** The CI pipeline fetches the Zig compiler hash from `ziglang.org/download/index.json` and verifies the tarball with `sha256sum --check --strict` before extraction (`.gitlab-ci.yml:56-67`).

3. **Dependency content-hash pinned.** The `config` dependency in `build.zig.zon` uses content-hash pinning, ensuring reproducible builds and preventing silent upstream changes.

4. **Heap password zeroing documented.** The `password()` function at `src/prompt.zig:127-133` includes a doc comment with a code example showing callers how to zero the returned password before freeing.

5. **Path redaction in error messages.** Sensitive path information is redacted in user-facing error messages via `redactPath()`, preventing information leakage.

6. **.gitignore excludes .env files.** The `.gitignore` at lines 22-24 blocks `.env`, `.env.*`, and `*.env` from being committed.

7. **Comprehensive CI security pipeline.** The pipeline includes SAST, dependency scanning, secret detection (two tools), SBOM generation, and SBOM scanning -- all integrated as standard stages.

8. **Signal async-signal-safety documented.** The `onCleanup()` and `runCleanupCallbacks()` functions in `src/signal.zig` include documentation warning that callbacks must be async-signal-safe.

9. **Pager uses direct exec (no shell).** Restored: `pager.zig` no longer uses `/bin/sh -c`. Direct argv execution via `Child.init`.

10. **Stack password buffers zeroed.** Restored: Both POSIX (`prompt.zig:164`) and Windows (`prompt.zig:186`) password paths use `defer @memset(&buffer, 0)`.

11. **All 4 shell completion generators have proper escape functions.** Restored: bash, zsh, fish, and PowerShell generators all have shell-specific escape functions with fast-path optimization.

12. **PowerShell completion consistently escaped.** Restored: `escapePowerShellString()` and `escapeRegex()` perform real escaping.

13. **Atomic operations for signal handler state.** Restored: `callback_count` is `std.atomic.Value(usize)` with proper memory ordering.

---

## Remediation Roadmap

### Quick Wins (< 1 day each)

| Finding | Effort | Description | Status |
|---------|--------|-------------|--------|
| ~~NS-008~~ | ~~30 min~~ | ~~Add NUL/newline filtering to `escapeBashDoubleQuote` and `escapeBashCasePattern`~~ | **CLOSED** |
| ~~NS-009~~ | ~~30 min~~ | ~~Add NUL/newline filtering to `escapeZshDoubleQuote` and `escapeZshSingleQuote`~~ | **CLOSED** |
| ~~NS-012~~ | ~~15 min~~ | ~~Use `writeJsonEscapedString` in `printVersionImpl` for cmd.name/version~~ | **CLOSED** |
| ~~NS-015~~ | ~~15 min~~ | ~~Apply `escapePowerShellString()` to completion values at powershell.zig:161~~ | **CLOSED** |
| ~~NS-018~~ | ~~15 min~~ | ~~Set `.{ .mode = 0o600 }` in `writeFileAtomic` createFile call~~ | **CLOSED** |
| ~~NS-048~~ | ~~30 min~~ | ~~Add NUL/newline/CR filtering to `escapeFishSingleQuote`~~ | **CLOSED** |
| ~~NS-049~~ | ~~30 min~~ | ~~Add NUL/newline/CR filtering to `escapePowerShellString`~~ | **CLOSED** |
| ~~NS-053~~ | ~~30 min~~ | ~~Add backtick and angle bracket escaping to `writeMarkdownEscaped`~~ | **CLOSED** |
| ~~NS-054~~ | ~~15 min~~ | ~~Check for negative result before `@intCast` in `tty.zig`~~ | **CLOSED** |

### Medium Effort (1-5 days)

| Finding | Effort | Description | Status |
|---------|--------|-------------|--------|
| ~~NS-010~~ | ~~2-4 hrs~~ | ~~Escape or validate cmd/flag names in fish completion output at 6 injection points~~ | **CLOSED** |
| ~~NS-011~~ | ~~1-2 hrs~~ | ~~Track line boundaries in `writeRoffEscaped` to escape `.`/`'` after newlines~~ | **CLOSED** |
| ~~NS-014~~ | ~~1-2 hrs~~ | ~~Validate cmd.name for safe shell identifier chars in bash completion~~ | **CLOSED** |
| ~~NS-016~~ | ~~2-4 hrs~~ | ~~Zero secret flag values in `Context.deinit()` before freeing~~ | **CLOSED** |
| ~~NS-020~~ | ~~2-4 hrs~~ | ~~Implement Markdown escaping for table cells and headings in `generateMarkdown`~~ | **CLOSED** |
| ~~NS-019~~ | ~~1-2 hrs~~ | ~~Make `active_config` atomic or mutex-protected on Windows~~ | **CLOSED** |
| ~~NS-047~~ | ~~2-4 hrs~~ | ~~Implement Windows echo suppression via Console API or `_getch()`~~ | **CLOSED** |
| ~~NS-050~~ | ~~2-4 hrs~~ | ~~Iterate resolved subcommand flags in `applyEnvDefaults`~~ | **CLOSED** |
| ~~NS-051~~ | ~~1-2 hrs~~ | ~~Escape command names in fish `buildCondition`/`buildSubcommandCondition`~~ | **CLOSED** |
| ~~NS-052~~ | ~~1 hr~~ | ~~Replace static mutable buffer in `sanitizeBashIdentifier` with allocator~~ | **CLOSED** |

### Strategic (> 5 days)

| Finding | Effort | Description | Status |
|---------|--------|-------------|--------|
| ~~NS-013~~ | ~~3-5 days~~ | ~~Refactor signal handler to flag-and-poll pattern~~ | **CLOSED** (documented) |

### Recommended Remediation Order

1. ~~**NS-048 + NS-049** (Medium, quick wins, 1 hr total) -- NUL/newline filtering in fish/PowerShell escapes. Aligns with already-closed bash/zsh fixes.~~ **CLOSED**
2. ~~**NS-047** (Medium, 2-4 hrs) -- Windows password echo suppression. Highest risk score (35) among open findings.~~ **CLOSED**
3. ~~**NS-051** (Low, 1-2 hrs) -- Fish condition command names. Extends existing fish escaping.~~ **CLOSED**
4. ~~**NS-053** (Low, 30 min) -- Markdown backtick escaping. Extends existing escape function.~~ **CLOSED**
5. ~~**NS-054** (Low, 15 min) -- Windows terminal dimension cast. One-line fix.~~ **CLOSED**
6. ~~**NS-052** (Low, 1 hr) -- Bash identifier static buffer. API consistency improvement.~~ **CLOSED**
7. ~~**NS-050** (Low, 2-4 hrs) -- Subcommand env defaults. Functional gap with security implications. Cross-ref GAP-0090.~~ **CLOSED**

---

## Remediation Roadmap -- codepros:audit iteration 1 (2026-06-11, OPEN)

### Immediate (leaked secrets / active RCE)

None. No leaked secrets (gitleaks clean, working tree + 70-commit history) and no active RCE.

### Quick Wins (< 1 day each)

| Finding | Risk | Effort | Description | Issue |
|---------|------|--------|-------------|-------|
| NS-058 | 24 | 15 min | Saturating subtraction `term_info.width -\| 20` in `ProgressBar.init` | [#129](https://gitlab.com/devnw/zig/cli/-/issues/129) |
| NS-061 (F-04) | 12 | 30 min | Wrap PowerShell `-CommandName` in `escapePowerShellString` | [#132](https://gitlab.com/devnw/zig/cli/-/issues/132) |
| NS-061 (F-06) | 12 | 30 min | Add fish `new_path` bounds check (`>= 16` -> `error.TooDeep`) | [#132](https://gitlab.com/devnw/zig/cli/-/issues/132) |
| NS-016 (doc) | 16 | 15 min | Correct `command.zig:44` doc comment re: argv/environ scrubbing | -- |

### Medium Effort (1-5 days)

| Finding | Risk | Effort | Description | Issue |
|---------|------|--------|-------------|-------|
| NS-056 | 36 | 1-2 days | Apply `stripControl` on TTY output (errors/help/color/progress/table/prompt) or export `sanitizeForTerminal()` + SECURITY.md trust contract | [#128](https://gitlab.com/devnw/zig/cli/-/issues/128) |
| NS-059 | 32 | 2-4 hrs | Windows password no-echo on GetConsoleMode failure (error or `_getch`/`ReadConsole`) | [#130](https://gitlab.com/devnw/zig/cli/-/issues/130) |
| NS-060 | 16 | 2-4 hrs | Context-aware Markdown escaping for headings/prose/fences | [#131](https://gitlab.com/devnw/zig/cli/-/issues/131) |
| NS-061 (F-05) | 12 | 1-2 hrs | zsh identifier sanitizer + case-label escaping | [#132](https://gitlab.com/devnw/zig/cli/-/issues/132) |
| NS-062 | 12 | 1-3 days | Snap slice boundaries to UTF-8 codepoint starts; codepoint/wcwidth display width | [#133](https://gitlab.com/devnw/zig/cli/-/issues/133) |

### Recommended Order

1. **NS-056** (Risk 36) -- highest residual; live-by-default via unknown-command path.
2. **NS-059** (Risk 32) -- credential exposure; pairs with the already-closed NS-047 primary path.
3. **NS-058** (Risk 24) -- one-line saturating-subtraction fix; removes a geometry-triggered DoS.
4. **NS-061** (Risk 12) -- three quick completion-generator hardening fixes; extends existing patterns.
5. **NS-060** (Risk 16) / **NS-062** (Risk 12) -- output-encoding correctness; close the NS-020 gap.
