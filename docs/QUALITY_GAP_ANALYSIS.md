# Quality Gap Analysis

> Comprehensive quality tracking for the Zig CLI framework library.
> Combines initial codebase audit (2026-03-24) with Phase 3/4 quality-reviewer findings.

Last updated: 2026-06-12

## Summary

| Severity | Open | Closed | Won't Do |
|----------|------|--------|----------|
| Critical | 0 | 1 | 0 |
| High | 0 | 14 | 1 |
| Medium | 0 | 40 | 3 |
| Low | 1 | 36 | 6 |
| **Total** | **1** | **91** | **10** |

**1 open finding** after the audit-iteration-1 fix merge (188bf5a, 2026-06-12). The 21 Phase 4 findings (NQ-NEW-001..021) were addressed: **20 Closed**, **1 open** (NQ-NEW-014, generator duplication, deferred to a refactor — tracked under [#140](https://gitlab.com/devnw/zig/cli/-/issues/140)).

**Cross-domain (owned by the security tracker, NOT counted here):** NQ-NEW-007/008-injection-scope (markdown injection = security F-03/NS-060, issue #131 — now Closed), NQ-NEW-010 (deinit secret-zeroing doc = security F-02/NS-016 — now Closed), NQ-NEW-015 (Windows password echo on GetConsoleMode failure = security NS-059, issue #130 — now Closed).

**Sole open item:** NQ-NEW-014 ([#140](https://gitlab.com/devnw/zig/cli/-/issues/140)) — completion-generator duplication across bash/zsh/fish/powershell. Deferred to a structural refactor; no functional or security impact.

20 of 21 Phase 4 findings closed in the 188bf5a merge. 929/929 unit + integration tests pass; `pre-commit run --all-files` green; `zig fmt`/`check` clean.

---

## Stack-Ranked Findings

### Phase 4 codepros:audit Iteration (found 2026-06-11, mostly fixed 2026-06-12)

PriorityScore = Impact(1-5) x Likelihood(1-5) x 4. Grouped issues are ranked by their top sub-finding. 20 of 21 closed in the 188bf5a merge; only NQ-NEW-014 (generator duplication) remains open, deferred to a refactor under [#140](https://gitlab.com/devnw/zig/cli/-/issues/140).

| Rank | ID(s) | Severity | PriorityScore | Category | Finding | Component | Fix commit / Evidence | Issue | Status |
|------|-------|----------|---------------|----------|---------|-----------|----------------------|-------|--------|
| 1 | NQ-NEW-003 | Medium | 48 | maintainability | Version drift: root.zig vs build.zig.zon/tag; CHANGELOG missing 3 releases (REGRESSION of NQ-053) | root.zig:67, build.zig.zon | `aca86b4`: `version = @import("build_options").version` single-sourced from `manifest.version` (build.zig:42) | [#106](https://gitlab.com/devnw/zig/cli/-/issues/106) | **Closed** |
| 2 | NQ-NEW-008 | Medium | 36 | api-contract | writeMarkdownEscaped misses newlines -> broken markdown options table | help.zig | `efaf9a7`,`22c374d`: cell newline -> `<br>`; context-aware escapers (NS-060) | [#136](https://gitlab.com/devnw/zig/cli/-/issues/136) | **Closed** |
| 3 | NQ-NEW-001/002/005 | Low | 32 | docs/ci-gate | Pre-commit + markdownlint failures (16x MD040, 1x MD056, whitespace/EOF/ruff) | docs/*, README.md, templates | `0bdede5..6e9b078`: `pre-commit run --all-files` green | [#134](https://gitlab.com/devnw/zig/cli/-/issues/134) | **Closed** |
| 4 | NQ-NEW-017 | Low->Med | 24 | maintainability | pager silently loses output on invalid PAGER (re-triage NQ-064 Won't Do) | pager.zig | `6dbc3e2`,`0c94c9b`: `writeDirect` fallback on spawn/exec/write failure (pager.zig:24-29,59) | [#137](https://gitlab.com/devnw/zig/cli/-/issues/137) | **Closed** |
| 5 | NQ-NEW-006 | Low | 24 | docs | CHANGELOG missing entries for v0.1.2/v0.1.3/v0.1.4 | CHANGELOG.md | `a4ab5cd`,`a553820`: [0.1.2]/[0.1.3]/[0.1.4] sections added | [#135](https://gitlab.com/devnw/zig/cli/-/issues/135) | **Closed** |
| 6 | NQ-NEW-012 | Low | 24 | api-contract | getBool returns bool while sibling accessors return ?T | command.zig | `aca86b4`: `getBoolOpt() ?bool` added (command.zig:246); default-false documented | [#138](https://gitlab.com/devnw/zig/cli/-/issues/138) | **Closed** |
| 7 | NQ-NEW-016 | Low | 24 | architecture | parallel pool_started guard non-atomic -> initPool/deinitPool race | parallel.zig | `f723199`: `pool_started: std.atomic.Value(bool)` with acquire/release (parallel.zig:72,80,87,97) | [#139](https://gitlab.com/devnw/zig/cli/-/issues/139) | **Closed** |
| 8a | NQ-NEW-011/009/013 | Low | 24 | maintainability | parser reuse reset, JSON short-flag escape, env[8] cap doc | parser.zig, help.zig | `d595798` (reset error state per parse), `26fa7c6`/`3978b13` (JSON short-flag escape), env-cap documented | [#140](https://gitlab.com/devnw/zig/cli/-/issues/140) | **Closed** |
| 8b | NQ-NEW-014 | Low | 24 | maintainability | completion-generator duplication across 4 files | bash/zsh/fish/powershell.zig | Deferred to structural refactor; no functional/security impact | [#140](https://gitlab.com/devnw/zig/cli/-/issues/140) | **Open (deferred)** |
| 9 | NQ-NEW-021 | Low | 24 | tests | Missing adversarial/edge tests (parser reuse, escaping, getBool) | cli test blocks | `3978b13` + audit batch: parser-reuse, fence-breakout, JSON short, getBoolOpt tests added (#142 closed) | [#142](https://gitlab.com/devnw/zig/cli/-/issues/142) | **Closed** |
| 10 | NQ-NEW-004 | Low | 24 | docs | Makefile says Zig 0.15.2; minimum is 0.16.0 (REGRESSION of NQ-061) | Makefile:185 | Makefile now "Zig 0.16.0 or compatible" | [#94](https://gitlab.com/devnw/zig/cli/-/issues/94) | **Closed** |
| 11 | NQ-NEW-019/020/018 | Low | 12 | docs | Public-API doc gaps (tty.zig, root.zig aliases) + misleading onCleanup doc | tty.zig, root.zig, signal.zig | `928f603`,`6b061c4`,`a4ab5cd`: doc comments added (tty.zig 26 `///`); onCleanup contract corrected | [#141](https://gitlab.com/devnw/zig/cli/-/issues/141) | **Closed** |

**Cross-referenced (security-owned, not tracked as quality issues):**

| ID | Finding | Owner | Issue |
|----|---------|-------|-------|
| NQ-NEW-007 | Markdown injection — name/summary/long_help/examples emitted raw into headings/prose/fences | security F-03 | [#131](https://gitlab.com/devnw/zig/cli/-/issues/131) |
| NQ-NEW-010 | `deinit` doc claims secrets "zeroed before deallocation" but bytes are neither zeroed nor freed | security F-02 | (security tracker) |
| NQ-NEW-015 | Windows `password()` echoes typed chars when GetConsoleMode fails (secret exposure) | security | [#130](https://gitlab.com/devnw/zig/cli/-/issues/130) |

**Won't-Do re-triage:** NQ-064 (pager silent error swallowing) scope was underestimated; the content-loss path is now tracked as NQ-NEW-017 (#137).

#### Findings by Category (2026-06-11 iteration)

- **docs:** NQ-NEW-001/002/005 (#134), NQ-NEW-006 (#135), NQ-NEW-004 (#94), NQ-NEW-019/020/018 (#141)
- **api-contract:** NQ-NEW-008 (#136), NQ-NEW-012 (#138), NQ-NEW-009 (in #140)
- **maintainability:** NQ-NEW-003 (#106), NQ-NEW-017 (#137), NQ-NEW-014/011/013 (#140)
- **architecture/concurrency:** NQ-NEW-016 (#139)
- **tests:** NQ-NEW-021 (#142)

#### Roadmap (2026-06-12 -- post-merge status)

- **Quick wins (< 1 day) -- DONE:** #134 (markdownlint/pre-commit green), #135 (CHANGELOG backfilled), #94 (Makefile 0.16.0), #106 (root.zig version single-sourced from build.zig.zon at comptime, closing the NQ-053/NQ-061 regression class), #141 (doc comments).
- **Medium (1-5 days) -- DONE:** #136 (markdown newline -> `<br>`), #137 (pager content-loss + direct-output fallback), #138 (getBoolOpt), #139 (atomic pool guard), #142 (adversarial tests), #140 NQ-NEW-011/009/013 (parser reuse reset, JSON short escape, env-cap doc).
- **Deferred (remaining open):** #140 NQ-NEW-014 -- shared format-generator walk across the 4 completion generators to structurally prevent missed-escaping regressions. Deferred to a dedicated refactor.

---

## Stack-Ranked Findings

### Phase 4 Quality Review Findings (Open)

| Rank | ID | Severity | PriorityScore | Category | Finding | Component | Issue | Status |
|------|----|----------|---------------|----------|---------|-----------|-------|--------|
| 1 | NQ-050 | High | 64 | maintainability | applyEnvDefaults skips subcommand flags -- functional bug | parser.zig:508-544 | [#101](https://gitlab.com/devnw/zig/cli/-/issues/101) | **Closed** |
| 2 | NQ-051 | High | 64 | api-contract | DeprecatedWriter in public Context API will break on Zig upgrade | command.zig:107-109 | [#102](https://gitlab.com/devnw/zig/cli/-/issues/102) | **Won't Do** |
| 3 | NQ-052 | High | 48 | maintainability | Windows password echo not disabled -- security concern | prompt.zig:179-183 | [#104](https://gitlab.com/devnw/zig/cli/-/issues/104) | **Closed** |
| 4 | NQ-053 | Medium | 48 | maintainability | Version string drift 0.1.0 vs v0.1.1 tag | root.zig:66, build.zig.zon:12 | [#106](https://gitlab.com/devnw/zig/cli/-/issues/106) | **Closed** |
| 5 | NQ-054 | Medium | 48 | ci-cd | No cross-compilation CI for Windows code paths | .gitlab-ci.yml | [#108](https://gitlab.com/devnw/zig/cli/-/issues/108) | **Closed** |
| 6 | NQ-055 | Medium | 36 | maintainability | sanitizeBashIdentifier global mutable static buffer -- fragile API | bash.zig:86-99 | [#109](https://gitlab.com/devnw/zig/cli/-/issues/109) | **Closed** |
| 7 | NQ-058 | Medium | 36 | tests | Windows signal tests completely skipped | signal.zig:309-312 | [#116](https://gitlab.com/devnw/zig/cli/-/issues/116) | **Closed** |
| 8 | NQ-056 | Medium | 36 | api-contract | Prompt inputInternal buffer caps at 1024 regardless of config.max_length | prompt.zig:99 | [#112](https://gitlab.com/devnw/zig/cli/-/issues/112) | **Closed** |
| 9 | NQ-057 | Medium | 32 | docs | ARCHITECTURE.md Command struct stale | docs/ARCHITECTURE.md:50-82 | [#114](https://gitlab.com/devnw/zig/cli/-/issues/114) | **Closed** |
| 10 | NQ-059 | Low | 24 | cleanup | 51 lines dead code: handleFlag, findFlagInChain, findFlagByShortInChain | parser.zig:280,453,482 | -- | **Closed** |
| 11 | NQ-060 | Low | 24 | architecture | parser.zig getEnvVar duplicates env.zig getEnvValueRuntime | parser.zig:550, env.zig:37 | -- | **Won't Do** |
| 12 | NQ-063 | Low | 16 | readability | Completion generator boilerplate duplication across 4 files | bash/zsh/fish/powershell.zig | -- | **Won't Do** |
| 13 | NQ-064 | Low | 16 | maintainability | Pager silent error swallowing | pager.zig:88,93 | -- | **Won't Do** |
| 14 | NQ-061 | Low | 12 | docs | Makefile version says 0.15.1 vs actual 0.15.2 | Makefile:145 | -- | **Closed** |
| 15 | NQ-062 | Low | 12 | docs | ROADMAP v0.2.0 lists shipped features as unreleased | docs/ROADMAP.md:120-128 | -- | **Closed** |
| 16 | NQ-065 | Low | 8 | readability | Inconsistent stdout access pattern (std.io.getStdOut vs std.fs.File.stdout) | multiple files | -- | **Won't Do** |

### Phase 3 Quality Review Findings (All Closed)

| Rank | ID | Severity | PriorityScore | Category | Finding | Component | Issue | Status |
|------|----|----------|---------------|----------|---------|-----------|-------|--------|
| 1 | NQ-035 | High | 80 | tests | No test coverage for run() function lifecycle | parser.zig:597-752 | [#75](https://gitlab.com/devnw/zig/cli/-/issues/75) | **Closed** |
| 2 | NQ-032 | High | 60 | architecture | Signal handler calls non-async-signal-safe user callbacks | signal.zig:161-177 | [#69](https://gitlab.com/devnw/zig/cli/-/issues/69) | **Closed** |
| 3 | NQ-031 | High | 48 | maintainability | OOM silently swallowed in applyEnvDefaults/applyDefaultsForCommand | parser.zig:450,484 | [#67](https://gitlab.com/devnw/zig/cli/-/issues/67) | **Closed** |
| 4 | NQ-033 | High | 48 | maintainability | writeFileAtomic missing fsync before rename, no cleanup on rename failure | fs.zig:54-79 | [#72](https://gitlab.com/devnw/zig/cli/-/issues/72) | **Closed** |
| 5 | NQ-036 | High | 48 | architecture | Subcommand flag inheritance only checks root, not intermediate parents | parser.zig:389-399 | [#76](https://gitlab.com/devnw/zig/cli/-/issues/76) | **Closed** |
| 6 | NQ-034 | Medium | 48 | maintainability | Pager writeIfTty has inverted min_lines logic | pager.zig:45 | [#74](https://gitlab.com/devnw/zig/cli/-/issues/74) | **Closed** |
| 7 | NQ-041 | Medium | 48 | api-contract | printHelp/printVersion swallow all errors via catch {} | help.zig:141-146,649-650 | [#81](https://gitlab.com/devnw/zig/cli/-/issues/81) | **Closed** |
| 8 | NQ-040 | Medium | 36 | api-contract | ColorContext.colored()/styled() are no-op stubs despite doc comments | color.zig:70-82 | [#80](https://gitlab.com/devnw/zig/cli/-/issues/80) | **Closed** |
| 9 | NQ-046 | Medium | 36 | maintainability | Global flags dual-maintenance: command.zig constant vs parser.zig strings | command.zig, parser.zig:305-311 | [#86](https://gitlab.com/devnw/zig/cli/-/issues/86) | **Closed** |
| 10 | NQ-037 | Medium | 32 | readability | Inline ANSI escape codes duplicated in help.zig (9+ sites) | help.zig | [#77](https://gitlab.com/devnw/zig/cli/-/issues/77) | **Closed** |
| 11 | NQ-044 | Medium | 32 | architecture | command_chain ArrayList deinit requires caller to pass correct allocator | parser.zig:56-62 | [#84](https://gitlab.com/devnw/zig/cli/-/issues/84) | **Closed** |
| 12 | NQ-047 | Medium | 32 | readability | run() 150-line monolith: extract formatParseError() and executeHooks() | parser.zig:597-752 | [#87](https://gitlab.com/devnw/zig/cli/-/issues/87) | **Closed** |
| 13 | NQ-038 | Medium | 24 | maintainability | Fixed-size buffers with silent data drop in parser, help, and fish completion | help.zig:220, parser.zig:86, fish.zig:161 | [#78](https://gitlab.com/devnw/zig/cli/-/issues/78) | **Closed** |
| 14 | NQ-039 | Medium | 24 | readability | Version fallback "0.0.0" magic string duplicated in 3 locations | parser.zig:598, help.zig:659,666 | [#79](https://gitlab.com/devnw/zig/cli/-/issues/79) | **Closed** |
| 15 | NQ-042 | Low | 24 | api-contract | JSON help output missing help/description fields for flags | help.zig:525-544 | [#82](https://gitlab.com/devnw/zig/cli/-/issues/82) | **Closed** |
| 16 | NQ-043 | Low | 16 | api-contract | Command.usage() returns hardcoded string ignoring command structure | command.zig:492-495 | [#83](https://gitlab.com/devnw/zig/cli/-/issues/83) | **Closed** |
| 17 | NQ-048 | Low | 16 | docs | Secret handling workflow not documented end-to-end | command.zig, parser.zig | [#88](https://gitlab.com/devnw/zig/cli/-/issues/88) | **Closed** |
| 18 | NQ-045 | Low | 12 | api-contract | Inconsistent allocator parameter ordering in prompt functions | prompt.zig:65,140,321 | [#85](https://gitlab.com/devnw/zig/cli/-/issues/85) | **Closed** |
| 19 | NQ-049 | Low | 8 | docs | ArgsValidator.only_valid silently accepts empty args (undocumented) | command.zig:318,366-377 | [#89](https://gitlab.com/devnw/zig/cli/-/issues/89) | **Closed** |

### Closed/Won't Do Findings (Rounds 1-2)

| Rank | ID | Severity | PriorityScore | Category | Finding | Component | Issue | Status |
|------|----|----------|---------------|----------|---------|-----------|-------|--------|
| 1 | GAP-0005 | Critical | 95 | maintainability | run() leaks ParseResult -- no defer deinit | parser.zig:601 | [#27](https://gitlab.com/devnw/zig/cli/-/issues/27) | **Closed** |
| 2 | GAP-0007 | High | 80 | api-contract | Version hardcoded "0.0.0" in run() | parser.zig:598 | [#29](https://gitlab.com/devnw/zig/cli/-/issues/29) | **Closed** |
| 3 | GAP-Q001 | High | 70 | maintainability | pager.zig uses std.posix.getenv directly | pager.zig:57 | -- | **Closed** |
| 4 | GAP-0019 | Medium | 65 | api-contract | redactPath() inconsistent ownership | fs.zig:117 | -- | **Closed** |
| 5 | GAP-0025 | Medium | 55 | maintainability | Global flags hardcoded in help + 4 completion generators | help.zig, bash/zsh/fish/powershell | -- | **Closed** |
| 6 | NEW-Q003 | Medium | 48 | api-contract | printJsonHelp no JSON escaping for cmd.name/summary | help.zig:450 | -- | **Closed** |
| 7 | NEW-Q002 | Medium | 48 | maintainability | printSectionFlags hardcodes 8 global flags | help.zig:289-290 | -- | **Closed** |
| 8 | GAP-Q006 | Medium | 45 | maintainability | Windows password buffer not zeroed | prompt.zig:186 | -- | **Closed** |
| 9 | GAP-Q007 | Medium | 45 | api-contract | handleGlobalFlag unused next_arg parameter | parser.zig:303 | -- | **Closed** |
| 10 | GAP-0022 | Medium | 40 | cleanup | Dead code printTextHelp/printFlag (~215 lines) | help.zig | -- | **Closed** |
| 11 | NQ-001 | High | 8 | maintainability | Silent error swallowing in env/default parsing | parser.zig:439 | [#39](https://gitlab.com/devnw/zig/cli/-/issues/39) | **Closed** |
| 12 | NQ-008 | Medium | 6 | tests | Prompt tests only cover NotInteractive paths | prompt.zig | [#52](https://gitlab.com/devnw/zig/cli/-/issues/52) | **Closed** |
| 13 | NQ-013 | Medium | 5 | docs | run() doc comment incomplete | parser.zig:584 | [#56](https://gitlab.com/devnw/zig/cli/-/issues/56) | **Closed** |
| 14 | NQ-026 | Low | 3 | architecture | ParseResult.deinit vs Context.deinit inconsistent allocator | parser.zig, command.zig | -- | **Won't Do** |
| 15 | NQ-029 | Low | 2 | readability | Duplicate comma-separated parsing logic | parser.zig:335 | -- | **Closed** |
| 16 | NQ-030 | Low | 2 | architecture | Hand-built JSON in printJsonHelp | help.zig:468 | -- | Won't Do |
| 17 | NEW-Q001 | Low | 8 | cleanup | FlagValue.deinit() dead code with broken API | command.zig | -- | **Closed** |
| 18 | GAP-0039 | Low | 15 | docs | suggestAll()/findByPrefix() ownership undocumented | suggest.zig:72,104 | -- | **Closed** |
| 19 | GAP-0026 | Low | 10 | cleanup | `or true` dead branch in help.zig | help.zig | -- | **Closed** |
| 20 | NEW-Q004 | Low | 8 | api-contract | escapePowerShellString/escapeRegex are no-op stubs | powershell.zig | -- | **Closed** |
| 21 | NEW-Q005 | Low | 8 | maintainability | POSIX password buffer not zeroed | prompt.zig:164 | -- | **Closed** |
| 22 | NQ-002 | High | 8 | api-contract | SecretPolicy error references non-existent --name-file | parser.zig:548 | [#42](https://gitlab.com/devnw/zig/cli/-/issues/42) | Closed |
| 24 | NQ-003 | High | 8 | tests | command.zig has 3 tests for 615 lines | command.zig | [#44](https://gitlab.com/devnw/zig/cli/-/issues/44) | Closed |
| 25 | NQ-004 | Medium | 6 | readability | parse() is 149 lines with 5 nesting levels | parser.zig:101-249 | [#46](https://gitlab.com/devnw/zig/cli/-/issues/46) | Won't Do |
| 26 | NQ-005 | Medium | 6 | cleanup | FlagValue.deinit() dead code, _ = allocator | command.zig:238-245 | [#48](https://gitlab.com/devnw/zig/cli/-/issues/48) | Closed |
| 27 | NQ-006 | Medium | 6 | api-contract | Missing getFloat() accessor | command.zig:148-195 | [#49](https://gitlab.com/devnw/zig/cli/-/issues/49) | Closed |
| 28 | NQ-007 | Medium | 6 | readability | Hardcoded "DevNW" author in man page | help.zig:565-566 | [#51](https://gitlab.com/devnw/zig/cli/-/issues/51) | Closed |
| 29 | NQ-009 | Medium | 6 | maintainability | Pager min_lines logic inverted | pager.zig:46 | [#53](https://gitlab.com/devnw/zig/cli/-/issues/53) | Closed |
| 30 | NQ-010 | Medium | 6 | architecture | parser.zig getEnvVar() bypasses env.zig | parser.zig:417-422 | [#29](https://gitlab.com/devnw/zig/cli/-/issues/29) | Closed |
| 31 | NQ-011 | Medium | 6 | architecture | Context.useColor() redundant env allocation | command.zig:210-227 | [#55](https://gitlab.com/devnw/zig/cli/-/issues/55) | Closed |
| 32 | NQ-012 | Medium | 6 | readability | run() is 144 lines, monolithic error switch | parser.zig:529-672 | [#56](https://gitlab.com/devnw/zig/cli/-/issues/56) | Won't Do |
| 33 | NQ-014 | Medium | 5 | api-contract | installWindows() ignores config parameter | signal.zig:191-215 | [#57](https://gitlab.com/devnw/zig/cli/-/issues/57) | Closed |
| 34 | NQ-015 | Medium | 4 | maintainability | ArgsValidator dedup | command.zig:328-339 | -- | Closed |
| 35 | NQ-017 | Medium | 4 | tests | signal.zig global state not reset between tests | signal.zig | -- | Closed |
| 36 | NQ-018 | Medium | 4 | ci-cd | No Zig toolchain caching in CI | .gitlab-ci.yml | -- | Closed |
| 37 | NQ-019 | Low | 4 | ci-cd | build.zig duplicates module definitions for check vs test | build.zig | -- | Closed |
| 38 | NQ-020 | Low | 4 | docs | Context.useColor() doc omits allocation | command.zig:210 | -- | Closed |
| 39 | NQ-021 | Low | 4 | readability | visibleSubcommands() counts hidden then returns all | command.zig:500-506 | -- | Closed |
| 40 | NQ-022 | Low | 3 | readability | collectUniqueGroups silently truncates at 32 | help.zig:199-222 | -- | Closed |
| 41 | NQ-023 | Low | 3 | maintainability | 3 old-style ArrayList.init() calls | suggest.zig:80,111 text.zig:166 | -- | Closed |
| 42 | NQ-024 | Low | 3 | docs | Parser has no doc comments on 10/12 methods | parser.zig | -- | Closed |
| 43 | NQ-025 | Low | 3 | docs | config.zig has zero tests, no doc on re-export nature | config.zig | -- | Closed |
| 44 | NQ-027 | Low | 2 | readability | 3 repeated @import("help.zig") in run() body | parser.zig:595,606,646 | -- | Closed |
| 45 | NQ-028 | Low | 2 | cleanup | Unused tty import in prompt.zig | prompt.zig:35 | -- | Closed |
| 46 | GAP-0006 | High | 90 | maintainability | Parser error paths leak Context memory | parser.zig | -- | Closed |
| 47 | GAP-0020 | High | 85 | ci-cd | No CI build/test pipeline | .gitlab-ci.yml | -- | Closed |
| 48 | GAP-0021 | Medium | 75 | tests | Unit test failures (2 test suites crash) | -- | -- | Closed |
| 49 | GAP-Q002 | Medium | 60 | api-contract | DeprecatedWriter used throughout codebase | command.zig, progress.zig | -- | Won't Do |
| 50 | GAP-Q003 | Medium | 55 | maintainability | Duplicated envVarExists/getEnvValue in tty/color | tty.zig, color.zig | -- | Closed |
| 51 | GAP-Q005 | Medium | 50 | tests | prompt.zig has only 2 trivial tests for 371 lines | prompt.zig | -- | Closed |

---

## Open Findings (Phase 4 Quality Review -- 2026-03-25)

### NQ-050: applyEnvDefaults skips subcommand flags -- functional bug [High] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 64 (Impact: 4, Likelihood: 4)
- **Category:** maintainability
- **Confidence:** confirmed
- **Issue:** [#101](https://gitlab.com/devnw/zig/cli/-/issues/101)
- **Evidence:** `src/cli/parser.zig:508-544` -- `applyEnvDefaults()` only iterates `self.root.flags`. Subcommand flags with `env` declarations are never checked.
- **Root cause:** Env-default application was implemented for root flags only; subcommand resolution happens earlier but `applyEnvDefaults` was not updated.
- **Fix:** After iterating root flags, also iterate the resolved command's flags.
- **Effort:** S
- **Cross-reference:** GAP-0090

### NQ-051: DeprecatedWriter in public Context API will break on Zig upgrade [High] -- WON'T DO

- **Status:** **Won't Do**
- **PriorityScore:** 64 (Impact: 4, Likelihood: 4)
- **Category:** api-contract
- **Confidence:** confirmed
- **Issue:** [#102](https://gitlab.com/devnw/zig/cli/-/issues/102)
- **Evidence:** `src/cli/command.zig:107-109` -- `Context.stdout` and `Context.stderr` are typed as `std.fs.File.DeprecatedWriter`.
- **Root cause:** `DeprecatedWriter` is a transitional type in Zig 0.15.x; migration to `AnyWriter`/`GenericWriter` deferred.
- **Fix:** Migrate to non-deprecated writer type. Batch with v0.2.0 API-breaking release.
- **Effort:** M
- **Cross-reference:** GAP-Q002 (Won't Do -- deferred until Zig removes type), GAP-0082

### NQ-052: Windows password echo not disabled -- security concern [High] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 48 (Impact: 4, Likelihood: 3)
- **Category:** maintainability
- **Confidence:** confirmed
- **Issue:** [#104](https://gitlab.com/devnw/zig/cli/-/issues/104)
- **Evidence:** `src/prompt.zig:179-183` -- Windows path falls back to `inputSimple()` with echo enabled. POSIX path correctly disables echo via `tcsetattr`.
- **Root cause:** Windows console mode manipulation was deferred (TODO comment in code).
- **Fix:** Use Windows `SetConsoleMode` to disable `ENABLE_ECHO_INPUT` before reading.
- **Effort:** S

### NQ-053: Version string drift -- root.zig 0.1.0 vs v0.1.1 tag [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 48 (Impact: 3, Likelihood: 4)
- **Category:** maintainability
- **Confidence:** confirmed
- **Issue:** [#106](https://gitlab.com/devnw/zig/cli/-/issues/106)
- **Evidence:** `src/root.zig:66` has `version = "0.1.0"`, `build.zig.zon:12` has `.version = "0.1.0"`, but `git tag` shows `v0.1.1` as latest.
- **Root cause:** Git tag bumped without updating source version constants.
- **Fix:** Update both files to `"0.1.1"`. Consider automating version sync.
- **Effort:** S
- **Cross-reference:** GAP-0088

### NQ-054: No cross-compilation CI for Windows code paths [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 48 (Impact: 3, Likelihood: 4)
- **Category:** ci-cd
- **Confidence:** confirmed
- **Issue:** [#108](https://gitlab.com/devnw/zig/cli/-/issues/108)
- **Evidence:** `.gitlab-ci.yml` has no Windows target. Windows-conditional code in `prompt.zig`, `signal.zig`, `parser.zig` is never compiled in CI.
- **Root cause:** Initial CI focused on native Linux testing only.
- **Fix:** Add `zig build -Dtarget=x86_64-windows` CI job.
- **Effort:** S
- **Cross-reference:** GAP-0094

### NQ-055: sanitizeBashIdentifier global mutable static buffer -- fragile API [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 36 (Impact: 3, Likelihood: 3)
- **Category:** maintainability
- **Confidence:** confirmed
- **Issue:** [#109](https://gitlab.com/devnw/zig/cli/-/issues/109)
- **Evidence:** `src/cli/completion/bash.zig:86-99` -- uses `var buf: [256]u8 = undefined` in nested struct (global mutable static). Returned slice points into this buffer; subsequent calls overwrite previous results.
- **Root cause:** C-style static buffer pattern avoids allocation but creates aliasing hazard.
- **Fix:** Accept allocator parameter or caller-provided buffer.
- **Effort:** S

### NQ-056: Prompt inputInternal buffer caps at 1024 regardless of config.max_length [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 36 (Impact: 3, Likelihood: 3)
- **Category:** api-contract
- **Confidence:** confirmed
- **Issue:** [#112](https://gitlab.com/devnw/zig/cli/-/issues/112)
- **Evidence:** `src/prompt.zig:99` -- `var buffer: [1024]u8 = undefined;` is hardcoded. The `config.max_length` field is never used to size the buffer.
- **Root cause:** Buffer was hardcoded during initial implementation; `max_length` config added later without updating buffer allocation.
- **Fix:** Use allocator-backed buffer sized to `config.max_length`.
- **Effort:** S

### NQ-057: ARCHITECTURE.md Command struct stale [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 32 (Impact: 2, Likelihood: 4)
- **Category:** docs
- **Confidence:** confirmed
- **Issue:** [#114](https://gitlab.com/devnw/zig/cli/-/issues/114)
- **Evidence:** `docs/ARCHITECTURE.md:50-61` shows a simplified Command struct missing `group`, `hidden`, `deprecated`, `aliases`, `args_validator`, `secret`, hooks, etc.
- **Root cause:** Architecture docs written early, not updated as Command struct evolved.
- **Fix:** Update struct example to match current `src/cli/command.zig`.
- **Effort:** S
- **Cross-reference:** GAP-0085

### NQ-058: Windows signal tests completely skipped [Medium] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 36 (Impact: 3, Likelihood: 3)
- **Category:** tests
- **Confidence:** confirmed
- **Issue:** [#116](https://gitlab.com/devnw/zig/cli/-/issues/116)
- **Evidence:** `src/signal.zig:309-312` -- all signal tests early-return on Windows, leaving `installWindows()` with 0% coverage.
- **Root cause:** Signal tests rely on POSIX signal delivery; no Windows-specific alternatives written.
- **Fix:** Add unit tests for `installWindows()` that validate config handling and state management.
- **Effort:** S

### NQ-059: 51 lines dead code -- handleFlag, findFlagInChain, findFlagByShortInChain [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 24 (Impact: 2, Likelihood: 3)
- **Category:** cleanup
- **Confidence:** confirmed
- **Evidence:** `src/cli/parser.zig:280` (`handleFlag`), `:453` (`findFlagInChain`), `:482` (`findFlagByShortInChain`) -- these functions contain dead or stub code paths that are unreachable.
- **Fix:** Remove dead code or complete stub implementations.
- **Effort:** S
- **Cross-reference:** GAP-0092

### NQ-060: parser.zig getEnvVar duplicates env.zig getEnvValueRuntime [Low] -- WON'T DO

- **Status:** **Won't Do**
- **PriorityScore:** 24 (Impact: 2, Likelihood: 3)
- **Category:** architecture
- **Confidence:** confirmed
- **Evidence:** `src/cli/parser.zig:550` defines `getEnvVar()` using `std.posix.getenv(name)` directly. `src/term/env.zig:37` defines `getEnvValueRuntime()` with the same cross-platform logic. Pager already uses the shared version.
- **Fix:** Replace `parser.getEnvVar` with `env.getEnvValueRuntime`.
- **Effort:** S
- **Cross-reference:** GAP-0093

### NQ-061: Makefile version says 0.15.1 vs actual 0.15.2 [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 12 (Impact: 1, Likelihood: 3)
- **Category:** docs
- **Confidence:** confirmed
- **Evidence:** `Makefile:145` says `Zig 0.15.1` but `zig version` returns `0.15.2`.
- **Fix:** Update Makefile to say `0.15.2` or `0.15.x`.
- **Effort:** S
- **Cross-reference:** GAP-0089

### NQ-062: ROADMAP v0.2.0 lists shipped features as unreleased [Low] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PriorityScore:** 12 (Impact: 1, Likelihood: 3)
- **Category:** docs
- **Confidence:** confirmed
- **Evidence:** `docs/ROADMAP.md:120-128` -- v0.2.0 "Unreleased" section lists features (command groups, markdown generation, table formatter) that appear to already be implemented.
- **Fix:** Move shipped features to the correct version section.
- **Effort:** S
- **Cross-reference:** GAP-0087

### NQ-063: Completion generator boilerplate duplication across 4 files [Low] -- WON'T DO

- **Status:** **Won't Do**
- **PriorityScore:** 16 (Impact: 2, Likelihood: 2)
- **Category:** readability
- **Confidence:** suspected
- **Evidence:** `src/cli/completion/bash.zig`, `zsh.zig`, `fish.zig`, `powershell.zig` -- each completion generator has similar flag-iteration and escaping boilerplate. Would need measurement to confirm how much could be extracted.
- **Fix:** Extract shared completion helpers (flag iteration, escaping) into a common module.
- **Effort:** M

### NQ-064: Pager silent error swallowing [Low] -- WON'T DO

- **Status:** **Won't Do**
- **PriorityScore:** 16 (Impact: 2, Likelihood: 2)
- **Category:** maintainability
- **Confidence:** confirmed
- **Evidence:** `src/term/pager.zig:88` -- `stdin.writeAll(content) catch {};` and `:93` -- `child.wait() catch {};` silently discard errors.
- **Fix:** Log or propagate errors from pager subprocess I/O.
- **Effort:** S

### NQ-065: Inconsistent stdout access pattern [Low] -- WON'T DO

- **Status:** **Won't Do**
- **PriorityScore:** 8 (Impact: 1, Likelihood: 2)
- **Category:** readability
- **Confidence:** suspected
- **Evidence:** Some files use `std.io.getStdOut()` while others use `std.fs.File.stdout`. Would need a full audit to confirm scope.
- **Fix:** Standardize on one pattern across the codebase.
- **Effort:** S

---

## Closed Findings (Phase 3 Quality Review -- Gap-Close Round 4, 2026-03-24)

### NQ-035: No test coverage for run() function lifecycle [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 80 (Impact: 4, Likelihood: 5)
- **Category:** tests
- **Issue:** [#75](https://gitlab.com/devnw/zig/cli/-/issues/75)
- **Resolution:** Added run() lifecycle tests exercising error variants, hook execution, help/version dispatch, and exit codes. 50 new tests added (710 -> 760 total).
- **Evidence:** `src/cli/parser.zig` -- run() test coverage via dedicated test cases.
- **Resolved:** 2026-03-24

### NQ-032: Signal handler calls non-async-signal-safe user callbacks [High] -- CLOSED

- **Status:** Closed / Documented
- **PriorityScore:** 60 (Impact: 5, Likelihood: 3)
- **Category:** architecture
- **Issue:** [#69](https://gitlab.com/devnw/zig/cli/-/issues/69)
- **Resolution:** Signal handler async-safety constraints documented with clear API contract. Doc comments on `onCleanup()` and `posixSignalHandler` state that registered callbacks must be async-signal-safe. Also closes NS-013.
- **Evidence:** `src/signal.zig` -- doc comments on `onCleanup()` and signal handler functions.
- **Resolved:** 2026-03-24

### NQ-031: OOM silently swallowed in applyEnvDefaults/applyDefaultsForCommand [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48 (Impact: 4, Likelihood: 3)
- **Category:** maintainability
- **Issue:** [#67](https://gitlab.com/devnw/zig/cli/-/issues/67)
- **Resolution:** OOM errors now propagated in `applyEnvDefaults` and `applyDefaultsForCommand`. Both functions return `ParseError!void` and callers handle OOM.
- **Evidence:** `src/cli/parser.zig` -- `applyEnvDefaults`, `applyDefaultsForCommand` return error unions.
- **Resolved:** 2026-03-24

### NQ-033: writeFileAtomic missing fsync before rename, no cleanup on rename failure [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48 (Impact: 4, Likelihood: 3)
- **Category:** maintainability
- **Issue:** [#72](https://gitlab.com/devnw/zig/cli/-/issues/72)
- **Resolution:** writeFileAtomic hardened: fsync before rename, mode 0o600, errdefer cleanup on rename failure. Also closes NS-018.
- **Evidence:** `src/util/fs.zig` -- `sync()` call before `close()`, explicit mode in `createFile`, errdefer `deleteFile`.
- **Resolved:** 2026-03-24

### NQ-036: Subcommand flag inheritance only checks root, not intermediate parents [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48 (Impact: 4, Likelihood: 3)
- **Category:** architecture
- **Issue:** [#76](https://gitlab.com/devnw/zig/cli/-/issues/76)
- **Resolution:** Flag inheritance now walks the full command chain (all ancestors), not just root. Applied to both `findFlagInChain()` and `findFlagByShortInChain()`.
- **Evidence:** `src/cli/parser.zig` -- `findFlagInChain`, `findFlagByShortInChain` iterate `command_chain` ArrayList.
- **Resolved:** 2026-03-24

### NQ-034: Pager writeIfTty has inverted min_lines logic [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48 (Impact: 3, Likelihood: 4)
- **Category:** maintainability
- **Issue:** [#74](https://gitlab.com/devnw/zig/cli/-/issues/74)
- **Resolution:** Pager min_lines logic fixed. Short content (below min_lines) is now written directly; only content exceeding terminal height is piped to pager.
- **Evidence:** `src/term/pager.zig` -- separate conditions for `min_lines` early return and terminal height check.
- **Resolved:** 2026-03-24

### NQ-041: printHelp/printVersion swallow all errors via catch {} [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48 (Impact: 3, Likelihood: 4)
- **Category:** api-contract
- **Issue:** [#81](https://gitlab.com/devnw/zig/cli/-/issues/81)
- **Resolution:** printHelp and printVersion now propagate errors to callers instead of discarding via `catch {}`.
- **Evidence:** `src/cli/help.zig` -- `printHelp`, `printVersion` return error unions.
- **Resolved:** 2026-03-24

### NQ-040: ColorContext.colored()/styled() are no-op stubs despite doc comments [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 36 (Impact: 3, Likelihood: 3)
- **Category:** api-contract
- **Issue:** [#80](https://gitlab.com/devnw/zig/cli/-/issues/80)
- **Resolution:** ColorContext stubs removed. Users directed to use `writeColored()`/`writeStyled()` writer-based alternatives.
- **Evidence:** `src/term/color.zig` -- stubs removed, doc comments updated.
- **Resolved:** 2026-03-24

### NQ-046: Global flags dual-maintenance: command.zig constant vs parser.zig strings [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 36 (Impact: 3, Likelihood: 3)
- **Category:** maintainability
- **Issue:** [#86](https://gitlab.com/devnw/zig/cli/-/issues/86)
- **Resolution:** Global flags single-sourced from `command.global_flags`. `handleGlobalFlag()` now derives from the constant array. Also closes NP-018.
- **Evidence:** `src/cli/parser.zig` -- `handleGlobalFlag` references `command.global_flags`; `src/cli/completion/bash.zig` -- global flags emitted from shared source.
- **Resolved:** 2026-03-24

### NQ-037: Inline ANSI escape codes duplicated in help.zig (9+ sites) [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 32 (Impact: 2, Likelihood: 4)
- **Category:** readability
- **Issue:** [#77](https://gitlab.com/devnw/zig/cli/-/issues/77)
- **Resolution:** ANSI escape codes replaced with named constants (e.g., `ansi_bold`, `ansi_reset`, `ansi_cyan`, `ansi_yellow`, `ansi_red`).
- **Evidence:** `src/cli/help.zig` -- named constants defined and used at all escape code sites.
- **Resolved:** 2026-03-24

### NQ-044: command_chain ArrayList deinit requires caller to pass correct allocator [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 32 (Impact: 4, Likelihood: 2)
- **Category:** architecture
- **Issue:** [#84](https://gitlab.com/devnw/zig/cli/-/issues/84)
- **Resolution:** ParseResult now stores allocator internally. `deinit()` uses stored allocator, removing the parameter.
- **Evidence:** `src/cli/parser.zig` -- `ParseResult` struct stores `allocator` field; `deinit()` is parameterless.
- **Resolved:** 2026-03-24

### NQ-047: run() 150-line monolith: extract formatParseError() and executeHooks() [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 32 (Impact: 2, Likelihood: 4)
- **Category:** readability
- **Issue:** [#87](https://gitlab.com/devnw/zig/cli/-/issues/87)
- **Resolution:** `run()` decomposed into helper functions: `formatParseError()` and `executeHooks()` extracted as separate functions.
- **Evidence:** `src/cli/parser.zig` -- `formatParseError`, `executeHooks` helper functions.
- **Resolved:** 2026-03-24

### NQ-038: Fixed-size buffers with silent data drop [Medium] -- CLOSED

- **Status:** Closed / Documented
- **PriorityScore:** 24 (Impact: 3, Likelihood: 2)
- **Category:** maintainability
- **Issue:** [#78](https://gitlab.com/devnw/zig/cli/-/issues/78)
- **Resolution:** Fixed-size buffer limits documented with doc comments at each buffer declaration. Limits are practical for CLI tooling (32 groups, 8 env errors, 16 nesting levels).
- **Evidence:** `src/cli/help.zig:220`, `src/cli/parser.zig:86`, `src/cli/completion/fish.zig:161` -- doc comments on buffer limits.
- **Resolved:** 2026-03-24

### NQ-039: Version fallback "0.0.0" magic string duplicated in 3 locations [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 24 (Impact: 2, Likelihood: 3)
- **Category:** readability
- **Issue:** [#79](https://gitlab.com/devnw/zig/cli/-/issues/79)
- **Resolution:** Version fallback constant extracted as shared `default_version`. All 3 locations reference the constant. Also closes NS-012 (JSON version output now uses escaped constant).
- **Evidence:** `src/cli/parser.zig`, `src/cli/help.zig` -- shared `default_version` constant.
- **Resolved:** 2026-03-24

### NQ-042: JSON help output missing help/description fields for flags [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 24 (Impact: 2, Likelihood: 3)
- **Category:** api-contract
- **Issue:** [#82](https://gitlab.com/devnw/zig/cli/-/issues/82)
- **Resolution:** JSON help output now includes `"help"` field for flag descriptions in `printJsonFlag()`.
- **Evidence:** `src/cli/help.zig` -- `printJsonFlag` emits `help` field.
- **Resolved:** 2026-03-24

### NQ-043: Command.usage() returns hardcoded string ignoring command structure [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 16 (Impact: 2, Likelihood: 2)
- **Category:** api-contract
- **Issue:** [#83](https://gitlab.com/devnw/zig/cli/-/issues/83)
- **Resolution:** `Command.usage()` now generates usage string from command structure, reflecting actual subcommands and flags.
- **Evidence:** `src/cli/command.zig` -- `usage()` dynamically generates from structure.
- **Resolved:** 2026-03-24

### NQ-048: Secret handling workflow not documented end-to-end [Low] -- CLOSED

- **Status:** Closed / Documented
- **PriorityScore:** 16 (Impact: 2, Likelihood: 2)
- **Category:** docs
- **Issue:** [#88](https://gitlab.com/devnw/zig/cli/-/issues/88)
- **Resolution:** Secret handling documented: SecretPolicy definition, usage pattern, error handling, and memory zeroing behavior.
- **Evidence:** `src/cli/command.zig` -- SecretPolicy doc comments; user-facing documentation added.
- **Resolved:** 2026-03-24

### NQ-045: Inconsistent allocator parameter ordering in prompt functions [Low] -- CLOSED

- **Status:** Closed / Documented
- **PriorityScore:** 12 (Impact: 1, Likelihood: 3)
- **Category:** api-contract
- **Issue:** [#85](https://gitlab.com/devnw/zig/cli/-/issues/85)
- **Resolution:** Allocator inconsistency documented for v0.2.0 API-breaking change. Current API preserved for stability.
- **Evidence:** `src/prompt.zig` -- doc comments note allocator position will be standardized in v0.2.0.
- **Resolved:** 2026-03-24

### NQ-049: ArgsValidator.only_valid silently accepts empty args (undocumented) [Low] -- CLOSED

- **Status:** Closed / Documented
- **PriorityScore:** 8 (Impact: 1, Likelihood: 2)
- **Category:** docs
- **Issue:** [#89](https://gitlab.com/devnw/zig/cli/-/issues/89)
- **Resolution:** Doc comment added documenting that empty args pass `.only_valid` validation.
- **Evidence:** `src/cli/command.zig:366` -- doc comment on `.only_valid` behavior with empty args.
- **Resolved:** 2026-03-24

---

## Recently Resolved (Gap-Close Round 2)

### NQ-008: Prompt tests only cover NotInteractive error paths [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** tests
- **Confidence:** confirmed
- **Issue:** [#52](https://gitlab.com/devnw/zig/cli/-/issues/52)
- **Resolution:** Refactored all 5 prompt functions (`input`, `password`, `confirm`, `select`, `multiSelect`) to delegate to internal `*Internal` variants that accept generic `reader: anytype, writer: anytype` parameters. 30 new tests added using `std.io.fixedBufferStream` covering: valid input, defaults, empty handling, max_length, validators, EOF/Cancelled, confirm y/Y/yes/n/N/no/empty/invalid-retry, select valid/out-of-range/non-numeric, multiSelect comma-parsing/out-of-range/single-selection. Total tests: 710 (up from 680).
- **Resolved:** 2026-03-24

### NQ-030: Hand-built JSON in printJsonHelp [Low] -- WON'T DO

- **Status:** Won't Do
- **PriorityScore:** 2 (Impact: 1, Likelihood: 2)
- **Category:** architecture
- **Confidence:** confirmed
- **Evidence:** `src/cli/help.zig:468` -- Manual string concatenation to build JSON output.
- **Reason:** Zig 0.15.2 has no `std.json` streaming writer. The existing `writeJsonEscapedString` helper (NEW-Q003 closure) already handles escaping correctly with 7 dedicated tests. A structural rewrite to a JSON builder would be a high-risk refactor with no safety benefit, since the output is structurally correct and properly escaped.

---

## Closed Findings (Wave 2 -- 2026-03-24)

### GAP-0005: run() leaks ParseResult on every invocation [Critical] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 95
- **Category:** maintainability
- **Issue:** [#27](https://gitlab.com/devnw/zig/cli/-/issues/27)
- **Resolution:** Changed `const result` to `var result` with `defer result.deinit(allocator)` at `parser.zig:601,685`. All 680 tests pass with 0 leaks under GeneralPurposeAllocator.
- **Resolved:** 2026-03-24

### GAP-0007: Version string drift -- hardcoded "0.0.0" in run() [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 80
- **Category:** api-contract
- **Issue:** [#29](https://gitlab.com/devnw/zig/cli/-/issues/29)
- **Resolution:** `run()` now derives version from `root.version` with `"0.0.0"` fallback at `parser.zig:598`. `root.zig` exports `version = "0.1.0"`. `--version` prints correct version.
- **Resolved:** 2026-03-24

### GAP-Q001: pager.zig uses std.posix.getenv directly [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 70
- **Category:** maintainability
- **Resolution:** `pager.zig:57-58` now uses `env_mod.getEnvValueRuntime(config.pager_env)` via `@import("env.zig")`. Cross-platform compatible.
- **Resolved:** 2026-03-24

### GAP-0019: redactPath() returns inconsistent ownership [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 65
- **Category:** api-contract
- **Resolution:** Non-sensitive paths now return `allocator.dupe(u8, path)` at `fs.zig:117`, ensuring all return values are caller-owned.
- **Resolved:** 2026-03-24

### GAP-0025: Global flags partially hardcoded in 5+ locations [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 55
- **Category:** maintainability
- **Resolution:** All locations now iterate `command.global_flags`. `help.zig:289-290` uses `for (command.global_flags)`, and all 4 completion generators iterate the same array. Dead `printTextHelp`/`printFlag` code removed (GAP-0022).
- **Resolved:** 2026-03-24

### NEW-Q003: printJsonHelp has no JSON escaping [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48
- **Category:** api-contract
- **Resolution:** `writeJsonEscapedString` helper added at `help.zig:450` and applied to all string interpolations in `printJsonHelp`/`printJsonFlag`. Escapes `"`, `\`, `\n`, `\r`, `\t`, and control chars. Unit tests added.
- **Resolved:** 2026-03-24

### NEW-Q002: printSectionFlags hardcodes 8 global flags instead of iterating [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 48
- **Category:** maintainability
- **Resolution:** `help.zig:289-290` now iterates `command.global_flags` via `for (command.global_flags) |*gflag|`. Inline struct literals removed. Subsumed by GAP-0025 closure.
- **Resolved:** 2026-03-24

### GAP-Q006: Windows password buffer not zeroed after use [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 45
- **Category:** maintainability
- **Resolution:** `defer @memset(&buffer, 0)` added at `prompt.zig:186` in `inputSimple()` Windows path.
- **Resolved:** 2026-03-24

### GAP-Q007: handleGlobalFlag accepts unused next_arg parameter [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 45
- **Category:** api-contract
- **Resolution:** `next_arg` parameter removed from `handleGlobalFlag` at `parser.zig:303`. Caller updated at `parser.zig:192`.
- **Resolved:** 2026-03-24

### GAP-0022: ~215 lines dead code in help.zig (printTextHelp/printFlag) [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 40
- **Category:** cleanup
- **Resolution:** `printTextHelp()` and `printFlag()` deleted. Active code uses `printHelp()` -> `printHelpWithTemplate()` -> `printSectionFlags()` -> `printFlagWithTemplate()`. ~215 lines removed.
- **Resolved:** 2026-03-24

### NQ-001: Silent error swallowing in parser env/default resolution [High] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 8
- **Category:** maintainability
- **Issue:** [#39](https://gitlab.com/devnw/zig/cli/-/issues/39)
- **Resolution:** Added `env_parse_errors` array to Parser struct at `parser.zig:86-87`. Env parse errors are now recorded with flag name, env var name, and raw value at `parser.zig:439-440`. On "missing required flag", the error message references the failed env parse attempt at `parser.zig:491-497`. Users now see "failed to parse env var FOO_BAR" instead of generic "missing required flag".
- **Resolved:** 2026-03-24

### NQ-013: run() doc comment incomplete [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 5
- **Category:** docs
- **Issue:** [#56](https://gitlab.com/devnw/zig/cli/-/issues/56)
- **Resolution:** Doc comment expanded at `parser.zig:584-596` to document full 9-step lifecycle: argument parsing, version/help dispatch, global flag handling, env/default resolution, validation, hooks, dispatch, post hooks, cleanup.
- **Resolved:** 2026-03-24

### NQ-016: resolveStdio() .stdout unreachable variant [Medium] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 4
- **Category:** architecture
- **Resolution:** `.stdout` variant removed from `resolveStdio()` return enum at `fs.zig:164`. Now returns `enum { stdin, path }` only.
- **Resolved:** 2026-03-24

### NQ-026: ParseResult.deinit vs Context.deinit inconsistent allocator pattern [Low] -- WON'T DO

- **Status:** Won't Do
- **PriorityScore:** 3
- **Category:** architecture
- **Reason:** Changing from parameter-based to stored allocator would alter the public API with no functional benefit. `Context.deinit()` already stores its allocator. `ParseResult.deinit(allocator)` is a thin wrapper that correctly delegates. Changing would break downstream callers for aesthetic consistency only.

### NQ-029: Duplicate comma-separated parsing logic [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 2
- **Category:** readability
- **Resolution:** `splitAndAppendCsv()` helper extracted at `parser.zig:335`. Both `parseValue` (line 355) and `appendToStringArray` (line 367) now call the shared helper.
- **Resolved:** 2026-03-24

### NEW-Q001: FlagValue.deinit() dead code with broken API [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 8
- **Category:** cleanup
- **Resolution:** `FlagValue.deinit()` removed as dead code. Cleanup is handled by `Context.deinit()` which owns all flag value memory.
- **Resolved:** 2026-03-24

### GAP-0039: suggestAll()/findByPrefix() ownership undocumented [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 15
- **Category:** docs
- **Resolution:** Ownership doc comments added at `suggest.zig:72` ("Caller owns the returned slice and must free it with `allocator`.") and `suggest.zig:104` (same pattern).
- **Resolved:** 2026-03-24

### GAP-0026: `or true` dead branch in help.zig [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 10
- **Category:** cleanup
- **Resolution:** Resolved as part of GAP-0022 dead code removal. The `printTextHelp` function containing the `or true` branch has been deleted entirely.
- **Resolved:** 2026-03-24

### NEW-Q004: escapePowerShellString/escapeRegex are no-op stubs [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 8
- **Category:** api-contract
- **Resolution:** Both functions now implement real escaping in `powershell.zig`. `escapePowerShellString` doubles single quotes (`'` -> `''`). `escapeRegex` escapes all regex metacharacters. Unit tests added for both. Subsumed by GAP-0009/GAP-0010 security closure.
- **Resolved:** 2026-03-24

### NEW-Q005: POSIX password buffer not zeroed after use [Low] -- CLOSED

- **Status:** Closed / Implemented
- **PriorityScore:** 8
- **Category:** maintainability
- **Resolution:** `defer @memset(&buffer, 0)` added at `prompt.zig:164` in POSIX `password()` path. Subsumed by GAP-0015/GAP-0066 security closure.
- **Resolved:** 2026-03-24

---

## Closed Findings

### NQ-015: ArgsValidator validate/getErrorDetails near-identical [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 4 (Impact: 2, Likelihood: 2)
- **Category:** maintainability
- **Resolution:** `validate()` now delegates to `getErrorDetails()` and maps the result, eliminating the duplicated switch statement. Fix confirmed at `command.zig:328-339`.
- **Resolved:** 2026-03-24

### NQ-002: SecretPolicy error references non-existent --name-file mechanism [High]

- **Status:** Closed / Implemented
- **PriorityScore:** 8 (Impact: 4, Likelihood: 2)
- **Category:** api-contract
- **Resolution:** Fixed error message to reference stdin only, removing the non-existent `--<name>-file` guidance.
- **Resolved:** 2026-03-24

### NQ-003: command.zig has only 3 tests for 615 lines [High]

- **Status:** Closed / Implemented
- **PriorityScore:** 8 (Impact: 4, Likelihood: 2)
- **Category:** tests
- **Resolution:** Added 134 new tests to command.zig covering ArgsValidator variants, typed accessors, findFlag, findFlagByShort, and other core data model paths.
- **Resolved:** 2026-03-24

### NQ-005: FlagValue.deinit() dead code, _ = allocator [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** cleanup
- **Resolution:** Removed dead allocator parameter from FlagValue.deinit().
- **Resolved:** 2026-03-24

### NQ-006: Missing getFloat() accessor breaks typed accessor pattern [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** api-contract
- **Resolution:** getFloat() was already implemented (found existing during implementation review).
- **Resolved:** 2026-03-24

### NQ-007: Hardcoded "DevNW" author in man page generation [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** readability
- **Resolution:** Man page author now falls back to cmd.name when the author field is empty.
- **Resolved:** 2026-03-24

### NQ-009: Pager min_lines logic is inverted [Medium]

- **Status:** Closed / Verified -- **Reopened as NQ-034** [#74](https://gitlab.com/devnw/zig/cli/-/issues/74)
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** maintainability
- **Resolution:** Logic verified as correct after review. The condition properly handles the min_lines threshold.
- **Reopened:** Phase 3 quality review disagrees with the verification. See NQ-034 for detailed logic trace.
- **Resolved:** 2026-03-24

### NQ-010: parser.zig getEnvVar() bypasses shared env.zig module [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** architecture
- **Resolution:** parser.zig now uses env.getEnvValueRuntime() instead of std.posix.getenv directly.
- **Resolved:** 2026-03-24

### NQ-011: Context.useColor() redundantly allocates for env checks [Medium]

- **Status:** Closed / Verified
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** architecture
- **Resolution:** useColor() already simplified to use parsed no_color/plain fields. No allocation occurs.
- **Resolved:** 2026-03-24

### NQ-014: installWindows() ignores config parameter [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 5 (Impact: 2.5, Likelihood: 2)
- **Category:** api-contract
- **Resolution:** installWindows() now uses the config parameter to check handle_interrupt before installing the handler.
- **Resolved:** 2026-03-24

### NQ-017: signal.zig global state not reset between tests [Medium]

- **Status:** Closed / Verified
- **PriorityScore:** 4 (Impact: 2, Likelihood: 2)
- **Category:** tests
- **Resolution:** signal.zig has clearInterrupted/clearTerminated functions. A separate resetForTesting is not needed.
- **Resolved:** 2026-03-24

### NQ-018: No Zig toolchain caching in CI [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 4 (Impact: 2, Likelihood: 2)
- **Category:** ci-cd
- **Resolution:** Added `zig-build` and `zig-test` stages to `.gitlab-ci.yml` using `devnw/zig:0.15` image.
- **Resolved:** 2026-03-24

### NQ-019: build.zig duplicates module definitions for check vs test [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 4 (Impact: 2, Likelihood: 2)
- **Category:** ci-cd
- **Resolution:** Build script de-duplicated.
- **Resolved:** 2026-03-24

### NQ-020: Context.useColor() doc comment does not mention allocation [Low]

- **Status:** Closed / Verified
- **PriorityScore:** 4 (Impact: 2, Likelihood: 2)
- **Category:** docs
- **Resolution:** useColor() no longer allocates (uses parsed fields), so the doc comment is accurate.
- **Resolved:** 2026-03-24

### NQ-021: visibleSubcommands() counts hidden then returns all [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 4 (Impact: 2, Likelihood: 2)
- **Category:** readability
- **Resolution:** Renamed to visibleSubcommandCount() and now returns the count of visible subcommands.
- **Resolved:** 2026-03-24

### NQ-022: collectUniqueGroups silently truncates at 32 groups [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 3 (Impact: 1.5, Likelihood: 2)
- **Category:** readability
- **Resolution:** Truncation behavior documented at all 3 call sites.
- **Resolved:** 2026-03-24

### NQ-023: 3 old-style ArrayList.init() calls [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 3 (Impact: 1.5, Likelihood: 2)
- **Category:** maintainability
- **Resolution:** ArrayList.init(allocator) replaced with .empty in suggest.zig, text.zig, and prompt.zig.
- **Resolved:** 2026-03-24

### NQ-024: Parser has no doc comments on 10/12 methods [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 3 (Impact: 1.5, Likelihood: 2)
- **Category:** docs
- **Resolution:** Parser doc comments added (10+ methods documented).
- **Resolved:** 2026-03-24

### NQ-025: config.zig has zero tests and no doc comment explaining re-export [Low]

- **Status:** Closed / Verified
- **PriorityScore:** 3 (Impact: 1.5, Likelihood: 2)
- **Category:** docs
- **Resolution:** config.zig already has tests and doc comments.
- **Resolved:** 2026-03-24

### NQ-027: 3 repeated @import("help.zig") inside run() body [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 2 (Impact: 1, Likelihood: 2)
- **Category:** readability
- **Resolution:** 3 inline help.zig imports replaced with file-scope const.
- **Resolved:** 2026-03-24

### NQ-028: Unused tty import in prompt.zig [Low]

- **Status:** Closed / Implemented
- **PriorityScore:** 2 (Impact: 1, Likelihood: 2)
- **Category:** cleanup
- **Resolution:** Unused tty import removed from prompt.zig.
- **Resolved:** 2026-03-24

### GAP-0006: Parser error paths leak Context memory [High]

- **Status:** Closed / Implemented
- **PriorityScore:** 90 (Impact: 5, Likelihood: 4)
- **Category:** maintainability
- **Resolution:** Added `errdefer ctx.deinit();` after `Context.init(self.allocator)` in `parse()`. All error paths now clean up properly.
- **Resolved:** 2026-03-24

### GAP-0020: No CI build/test pipeline [High]

- **Status:** Closed / Implemented
- **PriorityScore:** 85 (Impact: 4, Likelihood: 5)
- **Category:** ci-cd
- **Resolution:** Added `zig-build` and `zig-test` stages to `.gitlab-ci.yml` using `devnw/zig:0.15` image. Removed stale "Zig 0.15.x not yet released" comment.
- **Resolved:** 2026-03-24

### GAP-0021: Unit test failures (2 test suites crash) [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 75 (Impact: 4, Likelihood: 4)
- **Category:** tests
- **Resolution:** Test crashes were caused by memory leaks (GAP-0005, GAP-0006) and escape function issues (GAP-0009, GAP-0010). All 528/528 tests now pass clean.
- **Resolved:** 2026-03-24

### GAP-Q003: Duplicated envVarExists/getEnvValue in tty.zig and color.zig [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 55 (Impact: 3, Likelihood: 4)
- **Category:** maintainability
- **Resolution:** Extracted helpers to `src/term/env.zig`. `tty.zig` and `color.zig` import from the shared module. Single definition of each function.
- **Resolved:** 2026-03-24

### GAP-Q005: prompt.zig has only 2 trivial tests for 371 lines [Medium]

- **Status:** Closed / Implemented
- **PriorityScore:** 50 (Impact: 3, Likelihood: 3)
- **Category:** tests
- **Resolution:** Added 8 new tests to `prompt.zig` covering NotInteractive guards for all 5 prompt functions, InvalidInput for empty options, and InputConfig field validation. 10 tests total.
- **Resolved:** 2026-03-24

---

## Findings by Category

### maintainability

- **NQ-050 (High/64): applyEnvDefaults skips subcommand flags -- CLOSED** [#101](https://gitlab.com/devnw/zig/cli/-/issues/101)
- **NQ-052 (High/48): Windows password echo not disabled -- CLOSED** [#104](https://gitlab.com/devnw/zig/cli/-/issues/104)
- **NQ-053 (Medium/48): Version string drift 0.1.0 vs v0.1.1 -- CLOSED** [#106](https://gitlab.com/devnw/zig/cli/-/issues/106)
- **NQ-055 (Medium/36): sanitizeBashIdentifier global mutable static buffer -- CLOSED** [#109](https://gitlab.com/devnw/zig/cli/-/issues/109)
- **NQ-064 (Low/16): Pager silent error swallowing -- WON'T DO**
- NQ-031 (High/48): OOM silently swallowed in applyEnvDefaults/applyDefaultsForCommand -- **Closed** [#67](https://gitlab.com/devnw/zig/cli/-/issues/67)
- NQ-033 (High/48): writeFileAtomic missing fsync/cleanup -- **Closed** [#72](https://gitlab.com/devnw/zig/cli/-/issues/72)
- NQ-034 (Medium/48): Pager writeIfTty inverted min_lines logic -- **Closed** [#74](https://gitlab.com/devnw/zig/cli/-/issues/74)
- NQ-046 (Medium/36): Global flags dual-maintenance -- **Closed** [#86](https://gitlab.com/devnw/zig/cli/-/issues/86)
- NQ-038 (Medium/24): Fixed-size buffers with silent data drop -- **Closed** [#78](https://gitlab.com/devnw/zig/cli/-/issues/78)
- GAP-0005 (Critical/95): run() leaks ParseResult -- **Closed**
- GAP-Q001 (High/70): pager.zig uses std.posix.getenv directly -- **Closed**
- NQ-001 (High/8): Silent error swallowing in env/default parsing -- **Closed**
- GAP-0025 (Medium/55): Global flags hardcoded in 5+ locations -- **Closed**
- NEW-Q002 (Medium/48): printSectionFlags hardcodes 8 global flags -- **Closed**
- GAP-Q006 (Medium/45): Windows password buffer not zeroed -- **Closed**
- NEW-Q005 (Low/8): POSIX password buffer not zeroed -- **Closed**
- NQ-009 (Medium/6): Pager min_lines logic inverted -- **Closed**
- NQ-023 (Low/3): Old-style ArrayList.init() calls -- **Closed**
- GAP-Q003 (Medium/55): Duplicated envVarExists/getEnvValue -- **Closed**

### api-contract

- **NQ-051 (High/64): DeprecatedWriter in public Context API -- WON'T DO** [#102](https://gitlab.com/devnw/zig/cli/-/issues/102)
- **NQ-056 (Medium/36): Prompt inputInternal buffer caps at 1024 ignoring config.max_length -- CLOSED** [#112](https://gitlab.com/devnw/zig/cli/-/issues/112)
- NQ-041 (Medium/48): printHelp/printVersion swallow all errors -- **Closed** [#81](https://gitlab.com/devnw/zig/cli/-/issues/81)
- NQ-040 (Medium/36): ColorContext.colored()/styled() are no-op stubs -- **Closed** [#80](https://gitlab.com/devnw/zig/cli/-/issues/80)
- NQ-042 (Low/24): JSON help output missing help/description fields -- **Closed** [#82](https://gitlab.com/devnw/zig/cli/-/issues/82)
- NQ-043 (Low/16): Command.usage() returns hardcoded string -- **Closed** [#83](https://gitlab.com/devnw/zig/cli/-/issues/83)
- NQ-045 (Low/12): Inconsistent allocator parameter ordering -- **Closed** [#85](https://gitlab.com/devnw/zig/cli/-/issues/85)
- GAP-0007 (High/80): Version hardcoded "0.0.0" -- **Closed**
- GAP-0019 (Medium/65): redactPath inconsistent ownership -- **Closed**
- NEW-Q003 (Medium/48): printJsonHelp no JSON escaping -- **Closed**
- GAP-Q007 (Medium/45): handleGlobalFlag unused next_arg -- **Closed**
- NEW-Q004 (Low/8): PowerShell escape stubs -- **Closed**
- NQ-002 (High/8): SecretPolicy error references non-existent mechanism -- **Closed**
- NQ-006 (Medium/6): Missing getFloat() accessor -- **Closed**
- NQ-014 (Medium/5): installWindows() ignores config -- **Closed**
- NQ-026 (Low/3): ParseResult.deinit vs Context.deinit inconsistent allocator -- **Won't Do**

### tests

- **NQ-058 (Medium/36): Windows signal tests completely skipped -- CLOSED** [#116](https://gitlab.com/devnw/zig/cli/-/issues/116)
- NQ-035 (High/80): No test coverage for run() function lifecycle -- **Closed** [#75](https://gitlab.com/devnw/zig/cli/-/issues/75)
- NQ-008 (Medium/6): Prompt tests only cover NotInteractive -- **Closed**
- NQ-003 (High/8): command.zig has 3 tests for 615 lines -- **Closed**
- NQ-017 (Medium/4): signal.zig global state not reset between tests -- **Closed**
- GAP-Q005 (Medium/50): prompt.zig has only 2 trivial tests -- **Closed**

### readability

- **NQ-063 (Low/16): Completion generator boilerplate duplication across 4 files -- WON'T DO**
- **NQ-065 (Low/8): Inconsistent stdout access pattern -- WON'T DO**
- NQ-037 (Medium/32): Inline ANSI escape codes duplicated in help.zig -- **Closed** [#77](https://gitlab.com/devnw/zig/cli/-/issues/77)
- NQ-047 (Medium/32): run() monolith: extract formatParseError/executeHooks -- **Closed** [#87](https://gitlab.com/devnw/zig/cli/-/issues/87)
- NQ-039 (Medium/24): Version fallback "0.0.0" magic string duplicated -- **Closed** [#79](https://gitlab.com/devnw/zig/cli/-/issues/79)
- NQ-004 (Medium/6): parse() 149 lines, 5 nesting levels -- **Won't Do**
- NQ-007 (Medium/6): Hardcoded "DevNW" author -- **Closed**
- NQ-012 (Medium/6): run() 144 lines, monolithic error switch -- **Won't Do**
- NQ-021 (Low/4): visibleSubcommands() dead counting -- **Closed**
- NQ-022 (Low/3): collectUniqueGroups truncates at 32 -- **Closed**
- NQ-027 (Low/2): Repeated @import("help.zig") -- **Closed**
- NQ-029 (Low/2): Duplicate comma parsing -- **Closed**

### architecture

- **NQ-060 (Low/24): parser.zig getEnvVar duplicates env.zig getEnvValueRuntime -- WON'T DO**
- NQ-032 (High/60): Signal handler calls non-async-signal-safe callbacks -- **Closed** [#69](https://gitlab.com/devnw/zig/cli/-/issues/69)
- NQ-036 (High/48): Subcommand flag inheritance only checks root -- **Closed** [#76](https://gitlab.com/devnw/zig/cli/-/issues/76)
- NQ-044 (Medium/32): command_chain ArrayList deinit allocator mismatch risk -- **Closed** [#84](https://gitlab.com/devnw/zig/cli/-/issues/84)
- NQ-016 (Medium/4): resolveStdio .stdout unreachable -- **Closed**
- NQ-010 (Medium/6): parser getEnvVar bypasses env.zig -- **Closed**
- NQ-011 (Medium/6): useColor() redundant allocation -- **Closed**
- NQ-030 (Low/2): Hand-built JSON in help -- **Won't Do**
- NQ-026 (Low/3): Inconsistent allocator pattern -- **Won't Do**

### cleanup

- **NQ-059 (Low/24): 51 lines dead code in parser.zig -- CLOSED**
- GAP-0022 (Medium/40): Dead code printTextHelp/printFlag -- **Closed**
- GAP-0026 (Low/10): `or true` dead branch -- **Closed**
- NEW-Q001 (Low/8): FlagValue.deinit dead code -- **Closed**
- NQ-005 (Medium/6): FlagValue.deinit dead code (old) -- **Closed**
- NQ-028 (Low/2): Unused tty import -- **Closed**

### docs

- **NQ-057 (Medium/32): ARCHITECTURE.md Command struct stale -- CLOSED** [#114](https://gitlab.com/devnw/zig/cli/-/issues/114)
- **NQ-061 (Low/12): Makefile version says 0.15.1 vs 0.15.2 -- CLOSED**
- **NQ-062 (Low/12): ROADMAP v0.2.0 lists shipped features -- CLOSED**
- NQ-048 (Low/16): Secret handling workflow not documented -- **Closed** [#88](https://gitlab.com/devnw/zig/cli/-/issues/88)
- NQ-049 (Low/8): ArgsValidator.only_valid empty args undocumented -- **Closed** [#89](https://gitlab.com/devnw/zig/cli/-/issues/89)
- GAP-0039 (Low/15): suggestAll/findByPrefix ownership documented -- **Closed**
- NQ-013 (Medium/5): run() doc comment lifecycle -- **Closed**
- NQ-020 (Low/4): useColor() doc omits allocation -- **Closed**
- NQ-024 (Low/3): Parser 10/12 methods undocumented -- **Closed**
- NQ-025 (Low/3): config.zig no tests or re-export docs -- **Closed**

### ci-cd

- **NQ-054 (Medium/48): No cross-compilation CI for Windows -- CLOSED** [#108](https://gitlab.com/devnw/zig/cli/-/issues/108)
- NQ-018 (Medium/4): No Zig toolchain caching -- **Closed**
- NQ-019 (Low/4): build.zig duplicate module definitions -- **Closed**
- GAP-0020 (High/85): No CI build/test pipeline -- **Closed**

---

## Roadmap

### Quick Wins (< 1 day)

| ID | Finding | Effort | Issue |
|----|---------|--------|-------|
| NQ-053 | Version string drift 0.1.0 vs v0.1.1 | S | [#106](https://gitlab.com/devnw/zig/cli/-/issues/106) |
| NQ-054 | Add Windows cross-compilation CI job | S | [#108](https://gitlab.com/devnw/zig/cli/-/issues/108) |
| NQ-057 | Update ARCHITECTURE.md Command struct | S | [#114](https://gitlab.com/devnw/zig/cli/-/issues/114) |
| NQ-059 | Remove 51 lines dead code in parser.zig | S | -- |
| NQ-060 | Replace parser.getEnvVar with env.getEnvValueRuntime | S | -- |
| NQ-061 | Fix Makefile Zig version string | S | -- |
| NQ-062 | Move shipped ROADMAP items to correct version | S | -- |
| NQ-064 | Propagate pager subprocess errors | S | -- |
| NQ-065 | Standardize stdout access pattern | S | -- |

### Medium (1-5 days)

| ID | Finding | Effort | Issue |
|----|---------|--------|-------|
| NQ-050 | applyEnvDefaults skips subcommand flags | S | [#101](https://gitlab.com/devnw/zig/cli/-/issues/101) |
| NQ-052 | Windows password echo not disabled | S | [#104](https://gitlab.com/devnw/zig/cli/-/issues/104) |
| NQ-055 | sanitizeBashIdentifier global mutable static | S | [#109](https://gitlab.com/devnw/zig/cli/-/issues/109) |
| NQ-056 | Prompt buffer caps at 1024 ignoring max_length | S | [#112](https://gitlab.com/devnw/zig/cli/-/issues/112) |
| NQ-058 | Windows signal tests completely skipped | S | [#116](https://gitlab.com/devnw/zig/cli/-/issues/116) |

### Strategic (> 5 days)

| ID | Finding | Effort | Issue |
|----|---------|--------|-------|
| NQ-051 | DeprecatedWriter migration (v0.2.0 API break) | M | [#102](https://gitlab.com/devnw/zig/cli/-/issues/102) |
| NQ-063 | Completion generator boilerplate extraction | M | -- |

Previous roadmap items (NQ-031 through NQ-049) were all completed in Gap-Close
Round 4 (2026-03-24).

---

## Won't Do

### NQ-004: parse() is 149 lines with 5 nesting levels [Medium]

- **Status:** Won't Do
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** readability
- **Reason:** Decomposing parse() into sub-functions is a large refactor with marginal benefit. The function is well-structured internally and the nesting is driven by the parser's inherent logic flow.
- **Resolved:** 2026-03-24

### NQ-012: run() is 144 lines with monolithic error switch [Medium]

- **Status:** Won't Do
- **PriorityScore:** 6 (Impact: 3, Likelihood: 2)
- **Category:** readability
- **Reason:** Decomposing run() is a large refactor with marginal benefit. The error switch centralizes error handling in one visible location.
- **Resolved:** 2026-03-24

### GAP-Q002: DeprecatedWriter used throughout codebase [Medium]

- **Status:** Won't Do
- **PriorityScore:** 60
- **Category:** api-contract
- **Reason:** `DeprecatedWriter` migration requires Zig API stabilization. The writer type is transitional in Zig 0.15 and the replacement API (`AnyWriter`/`GenericWriter`) is not yet finalized. Tracked for when Zig removes the type.
- **Affected files:** `src/cli/command.zig`, `src/term/progress.zig`

### NQ-030: Hand-built JSON in printJsonHelp [Low]

- **Status:** Won't Do
- **PriorityScore:** 2 (Impact: 1, Likelihood: 2)
- **Category:** architecture
- **Reason:** Zig 0.15.2 has no `std.json` streaming writer. The existing `writeJsonEscapedString` helper already handles escaping correctly with 7 dedicated tests. A structural rewrite to a JSON builder would be a high-risk refactor with no safety benefit, since the output is structurally correct and properly escaped.
- **Affected files:** `src/cli/help.zig:468`
- **Resolved:** 2026-03-24

---

## Scoring Framework

**PriorityScore** = Impact (1-5) x Likelihood (1-5) x 4, yielding a 0-100 scale.

For findings originally scored on the older 1-10 scale (NQ-series), the original scores are preserved for continuity.

| Impact | Description |
|--------|-------------|
| 5 | Outages, data integrity, major perf cost |
| 4 | Frequent bugs, major developer drag |
| 3 | Moderate impact on maintainability/perf |
| 2 | Minor impact |
| 1 | Polish |

| Likelihood | Description |
|------------|-------------|
| 5 | Ubiquitous / touched often |
| 4 | Often encountered |
| 3 | Sometimes encountered |
| 2 | Rare |
| 1 | Edge-case |

**Confidence tags:** `confirmed` (verified via code evidence), `suspected` (plausible, needs measurement).
