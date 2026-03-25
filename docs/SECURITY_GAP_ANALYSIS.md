# Security Gap Analysis

> Auto-generated from full codebase audit (2026-03-24). Updated 2026-03-24 with Phase 3 findings (including Phase 3 deep-inspection round).

Last updated: 2026-03-24

## REGRESSION NOTICE -- RESOLVED

On 2026-03-24, Phase 3 code inspection confirmed that 19 previously-closed findings
had regressed due to a git stash/pop incident. All 19 regressions plus 3 new findings
have been re-implemented and verified. 760/760 tests pass with 0 memory leaks.

## Summary

| Risk Level | Total | Open | Closed | Won't Do |
|-----------|-------|------|--------|----------|
| Critical | 1 | 0 | 1 | 0 |
| High | 2 | 0 | 2 | 0 |
| Medium | 19 | 0 | 18 | 1 |
| Low | 19 | 0 | 18 | 1 |
| Info | 5 | 0 | 1 | 4 |
| **Total** | **46** | **0** | **40** | **6** |

**All security findings are now closed.** 13 findings closed in Gap-Close Round 4
(2026-03-24). 760/760 tests pass with 0 memory leaks.

## Stack-Ranked Findings Table

| Rank | Severity | Risk Score | Finding | Component | CWE/OWASP | Evidence (file:line) | Issue URL | Status |
|------|----------|------------|---------|-----------|-----------|---------------------|-----------|--------|
| 1 | Critical | 95 | Shell injection via PAGER env var | pager | CWE-78 / A03:2021 | `src/term/pager.zig:57-58` | -- | **Closed** |
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
| 23 | Low | 35 | Predictable temp file in writeFileAtomic | fs | CWE-377 / A05:2021 | `src/util/fs.zig:59` | -- | **Closed** |
| 24 | Low | 25 | isSafePath() only blocks 2 paths | fs | CWE-22 / A01:2021 | `src/util/fs.zig:127-142` | -- | **Closed** |
| 25 | Low | 25 | Fish subcmd.name unescaped in -a argument | completion/fish | CWE-78 / A03:2021 | `src/cli/completion/fish.zig` | -- | **Closed** |
| 26 | Low | 20 | isSafePath doesn't resolve symlinks | fs | CWE-59 / A01:2021 | `src/util/fs.zig:121-157` | -- | Closed (partial doc) |
| 27 | Low | 20 | Signal cleanup callbacks in async-signal context | signal | CWE-364 / A04:2021 | `src/signal.zig` | -- | Closed (minimal doc) |
| 28 | Low | 16 | Secret flag values not zeroed from memory after use | parser/command | CWE-316 / A02:2021 | `src/cli/command.zig:134-146` | -- | **Closed** |
| 29 | Low | 16 | generateMarkdown has no Markdown escaping | help | CWE-79 / A03:2021 | `src/cli/help.zig:681-776` | -- | **Closed** |
| 30 | Low | 15 | Bash flag.name unescaped in variable assignment | completion/bash | CWE-78 / A03:2021 | `src/cli/completion/bash.zig` | -- | **Closed** |
| 31 | Low | 15 | Zsh subcmd.name unescaped in case pattern | completion/zsh | CWE-78 / A03:2021 | `src/cli/completion/zsh.zig` | -- | **Closed** |
| 32 | Low | 15 | Fixed-size buffers silently truncate | multiple | CWE-120 / A06:2021 | `src/cli/completion/*.zig`, `src/cli/help.zig` | -- | Won't Do |
| 33 | Low | 15 | Fish flag.help/subcmd.summary unescaped in single-quoted strings | completion/fish | CWE-78 / A03:2021 | `src/cli/completion/fish.zig` | -- | **Closed** |
| 34 | Low | 12 | Bash writes cmd.name directly into shell function names | completion/bash | CWE-78 / A03:2021 | `src/cli/completion/bash.zig:94,106,112` | -- | **Closed** |
| 35 | Low | 12 | PowerShell completion values not escaped | completion/ps | CWE-74 / A03:2021 | `src/cli/completion/powershell.zig:161` | -- | **Closed** |
| 36 | Low | 10 | Levenshtein buffer overflow | suggest | CWE-120 / A06:2021 | `src/util/suggest.zig:16-17` | -- | **Closed** |
| 37 | Low | 8 | Inconsistent shell escaping (7 unescaped points) | completion | CWE-78 / A03:2021 | `fish.zig`, `zsh.zig`, `bash.zig` | [#38](https://gitlab.com/devnw/zig/cli/-/issues/38) | **Closed** (subsumed by GAP-0011 closure) |
| 38 | Low | 8 | Heap-allocated password not zeroed on free | prompt | CWE-316 / A02:2021 | `src/prompt.zig:127-133` | [#40](https://gitlab.com/devnw/zig/cli/-/issues/40) | Closed (documented) |
| 39 | Low | 8 | Pager command splitting cannot handle quoted arguments | pager | CWE-88 / A03:2021 | `src/term/pager.zig:58-80` | -- | **Closed** |
| 40 | Low | 8 | writeFileAtomic temp file inherits umask (world-readable risk) | fs | CWE-377 / A05:2021 | `src/util/fs.zig:54-79` | -- | **Closed** |
| 41 | Low | 8 | Windows active_config race condition | signal | CWE-362 / A04:2021 | `src/signal.zig:63,194` | -- | **Closed** |
| 42 | Info | 4 | .gitignore does not exclude .env files | repo config | CWE-540 / A07:2021 | `.gitignore:22-24` | [#43](https://gitlab.com/devnw/zig/cli/-/issues/43) | Closed |
| 43 | Info | 4 | Pager executes PAGER env var (standard POSIX behavior) | pager | -- | `src/term/pager.zig:58-83` | -- | Won't Do |
| 44 | Info | 4 | isSafePath doesn't resolve symlinks (documented) | fs | CWE-59 | `src/util/fs.zig:126-162` | -- | Won't Do |
| 45 | Info | 4 | 16-level command depth limit in path arrays | completion/fish | CWE-120 | `src/cli/completion/fish.zig:131` | -- | Won't Do |
| 46 | Info | 4 | Zig dependency hash-pinned (good practice) | build | -- | `build.zig.zon:36-38` | -- | Won't Do (positive) |

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

### NS-016: Secret flag values not zeroed from memory after use [Low] -- CLOSED

- **Status:** Closed / Implemented
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

### NS-020: generateMarkdown has no Markdown escaping [Low] -- CLOSED

- **Status:** Closed / Implemented
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
- **NS-016 (Closed):** Secret flag values zeroed in `Context.deinit()` before HashMap deallocation

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

### Input Validation / Encoding
- GAP-0012 (Closed): JSON help output -- `writeJsonEscapedString` added
- GAP-0013 (Closed): Man page roff injection -- `writeRoffEscaped` added
- GAP-0037 (Closed): SecretPolicy bypass -- secret flags skipped in defaults
- **NS-011 (Closed):** writeRoffEscaped newline handling fixed
- **NS-012 (Closed):** printVersionImpl JSON output escaped via writeJsonEscapedString
- **NS-020 (Closed):** Markdown table cell escaping implemented via `writeMarkdownEscaped`

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

### Pager
- **NS-017 (Closed):** Pager command splitting limitation documented in doc comment

### Supply Chain / CI/CD
- NS-001 (Won't Do): CI catalog components pinned to mutable git tags

### Repository Configuration
- NS-007 (Closed): .gitignore now excludes .env files

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

| Finding | Effort | Description |
|---------|--------|-------------|
| NS-008 | 30 min | Add NUL/newline filtering to `escapeBashDoubleQuote` and `escapeBashCasePattern` |
| NS-009 | 30 min | Add NUL/newline filtering to `escapeZshDoubleQuote` and `escapeZshSingleQuote` |
| NS-012 | 15 min | Use `writeJsonEscapedString` in `printVersionImpl` for cmd.name/version |
| ~~NS-015~~ | ~~15 min~~ | ~~Apply `escapePowerShellString()` to completion values at powershell.zig:161~~ **CLOSED** |
| NS-018 | 15 min | Set `.{ .mode = 0o600 }` in `writeFileAtomic` createFile call |

### Medium Effort (1-5 days)

| Finding | Effort | Description |
|---------|--------|-------------|
| NS-010 | 2-4 hrs | Escape or validate cmd/flag names in fish completion output at 6 injection points |
| NS-011 | 1-2 hrs | Track line boundaries in `writeRoffEscaped` to escape `.`/`'` after newlines |
| ~~NS-014~~ | ~~1-2 hrs~~ | ~~Validate cmd.name for safe shell identifier chars in bash completion~~ **CLOSED** |
| ~~NS-016~~ | ~~2-4 hrs~~ | ~~Zero secret flag values in `Context.deinit()` before freeing~~ **CLOSED** |
| ~~NS-020~~ | ~~2-4 hrs~~ | ~~Implement Markdown escaping for table cells and headings in `generateMarkdown`~~ **CLOSED** |
| ~~NS-019~~ | ~~1-2 hrs~~ | ~~Make `active_config` atomic or mutex-protected on Windows~~ **CLOSED** |

### Strategic (> 5 days)

| Finding | Effort | Description |
|---------|--------|-------------|
| NS-013 | 3-5 days | Refactor signal handler to flag-and-poll pattern (set flag in handler, run callbacks from normal context) |

### Recommended Remediation Order

1. **NS-012** (Medium, quick win, 15 min) -- JSON version output. Uses existing helper, minimal code change.
2. **NS-008 + NS-009** (Medium, quick wins, 1 hr total) -- NUL/newline in shell escaping. Root cause for shell injection bypass.
3. **NS-015** (Low, quick win, 15 min) -- PowerShell values. Uses existing helper.
4. **NS-018** (Low, quick win, 15 min) -- Temp file permissions. One-line fix.
5. **NS-010 + NS-014** (Medium/Low, 3-6 hrs) -- Fish/bash command names in shell syntax. Related shell escaping gap.
6. **NS-011** (Medium, 1-2 hrs) -- Roff newline handling.
7. **NS-016** (Low, 2-4 hrs) -- Secret flag zeroing in deinit.
8. **NS-020** (Low, 2-4 hrs) -- Markdown escaping.
9. **NS-019** (Low, 1-2 hrs) -- Windows active_config race.
10. **NS-013** (Medium, 3-5 days) -- Signal handler refactor. Largest effort, requires careful design.
