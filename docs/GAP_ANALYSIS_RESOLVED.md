# Gap Analysis -- Resolved

> Items moved from `docs/GAP_ANALYSIS.md` when resolved or marked as won't-do.

Last updated: 2026-06-12

## Closed (audit iteration 2 refactor merge -- 2026-06-12)

### GAP-0096: help.zig, parser.zig, command.zig exceed 800-line file-size guidance [RESOLVED]

- **Issue:** [#34](https://gitlab.com/devnw/zig/cli/-/issues/34) (closed)
- **Category:** Code Quality
- **Severity:** Low
- **Resolution:** The refactor merge split the three oversized files along
  existing seams with public APIs preserved via re-exports. Every tracked `.zig`
  file is now <= 800 lines, and a `check-zig-file-size` pre-commit hook enforces
  the limit going forward. `parse()` was decomposed into named phase helpers
  (issue #46, closed).
- **Evidence:**
  - `bash scripts/check_file_size.sh $(git ls-files '*.zig')` -> exit 0 (no violations).
  - Largest files post-split: `src/cli/completion/bash.zig` 768, `src/cli/parser.zig` 759 (was 2096), `src/cli/parser_test.zig` 747, `src/cli/command.zig` 738 (was 1261); `src/cli/help.zig` (was 1836) split into `src/cli/help/{markdown,man,json,text,common}.zig` (largest 692).
  - Pre-commit gate: `.pre-commit-config.yaml` hook `check-zig-file-size` -> `entry: scripts/check_file_size.sh`, `files: \.zig$`; `scripts/check_file_size.sh` enforces `LIMIT=800`.
  - `parse()` at `src/cli/parser.zig:165-211` = 47 lines (issue #46 required < 80).
  - Merge `3e2d804`; pre-commit gate commit `5c5022e`.
- **Resolved date:** 2026-06-12

### GAP-0084: GitLab issue hygiene -- resolved issues still open [RESOLVED]

- **Issue:** [#61](https://gitlab.com/devnw/zig/cli/-/issues/61) (closed)
- **Category:** Project Management
- **Severity:** Low
- **Resolution:** The one item that kept GAP-0084 open -- #46 (parse()
  decomposition), which was genuinely unimplemented in iteration 1 -- is now
  implemented and closed. The remaining previously stale-open issues
  (#29, #31, #32, #38, #43) are all closed, and the GAP-0084 tracking issue #61
  is closed. The only issues that remain open are #35 (CI catalog tag pinning --
  a deliberate accepted-risk policy item, NS-001 Won't-Do) and #12 (registry
  publication -- v0.2.0 roadmap, GAP-0083); neither is a tracker-hygiene defect.
  The issue tracker now reflects actual project state.
- **Evidence:** #61, #46, #29, #31, #32, #38, #43 all `state: closed` (verified via `glab issue view`); `glab issue list` returns exactly 2 open issues (#35, #12); merge `3e2d804` (closed #46/#34 via the refactor).
- **Resolved date:** 2026-06-12

## Closed (audit iteration 1 fix merge -- 2026-06-12)

### GAP-0097: Residual silent `catch continue` in parser env/default resolution [RESOLVED]

- **Issue:** [#39](https://gitlab.com/devnw/zig/cli/-/issues/39) (closed earlier; this completes the residual paths)
- **Category:** Code Quality (reliability / error-handling)
- **Severity:** Low
- **Resolution:** Both residual silent-swallow paths in `parser.zig` were fixed. The env-application write now propagates OOM (`parser.zig:537` -- `try self.setFlagValue(ctx, flag.name, fval);` instead of `catch continue`), and a malformed `default_str` now fails loudly: `applyDefaultsForCommand` records `invalid_default_flag` and returns `ParseError.InvalidValue` (`parser.zig:581-587`) rather than silently continuing. Env *parse* failures continue to be recorded into `env_parse_errors[]` with an overflow drop-count (`parser.zig:518-533`).
- **Evidence:** `src/cli/parser.zig:537` (propagating write), `:581-587` (invalid default_str surfaced); commit `d595798` ("fix(parser): propagate OOM from env defaults, error on invalid default_str, cap-count env errors, reset error state per parse"); merge `188bf5a`. 929/929 tests pass.
- **Resolved date:** 2026-06-12

### GAP-0098: Stale gap-tracking docs (Makefile/version refs, ROADMAP "Closed" markers) [RESOLVED]

- **Issue:** [#123](https://gitlab.com/devnw/zig/cli/-/issues/123) (closed; folded #31, #32)
- **Category:** Docs (tracking-doc accuracy)
- **Severity:** Low
- **Resolution:** Stale-doc remediation completed. `Makefile:185` now reads "Zig 0.16.0 or compatible"; the library version is single-sourced from `build.zig.zon` at comptime (`root.zig:67` -> `build.zig:42`), removing the version-drift class; CHANGELOG backfilled with [0.1.2]/[0.1.3]/[0.1.4]; `docs/ROADMAP.md` verified to contain no stale "in progress" claims about completed work; `docs/GAPS.md` reconciled. Tracking docs updated this pass to reflect the 188bf5a merge.
- **Evidence:** `Makefile:185`; `src/root.zig:67`; `build.zig:42`; `CHANGELOG.md` release sections; `grep -niE 'in progress|wip|hang' docs/ROADMAP.md` returns nothing; #123 closed.
- **Resolved date:** 2026-06-12

### GAP-0099: prompt.password() returned secret not zeroed by library on free [RESOLVED]

- **Issue:** [#40](https://gitlab.com/devnw/zig/cli/-/issues/40)
- **Category:** Security (hardening)
- **Severity:** Low
- **Resolution:** A library-provided zeroizing free helper `freeSecret(allocator, secret)` (`prompt.zig:280`) memsets-then-frees the returned secret; the public `password()` doc comment now directs callers to use it (`prompt.zig:190-195`). A unit test asserts the buffer is zeroed after teardown ("freeSecret zeroes before freeing", `prompt.zig:651`). Related: the Windows echoed-fallback path was also closed (NS-059).
- **Evidence:** `src/prompt.zig:280` (`freeSecret`), `:190-195` (doc), `:651` (zeroing test); commit `022e4cf` ("fix(prompt): refuse echoed Windows password fallback; add freeSecret zeroing helper"); merge `188bf5a`. 929/929 tests pass.
- **Resolved date:** 2026-06-12

## Closed (codepros:audit Phase 4 -- 2026-06-11)

### GAP-0091: Integration tests hang/timeout -- printHelp stdout deadlock [RESOLVED]

- **Issue:** [#96](https://gitlab.com/devnw/zig/cli/-/issues/96) (closed)
- **Category:** Bug
- **Severity:** High
- **Resolution:** The integration test harness pipe deadlock was fixed by redirecting stdout to `/dev/null` before the only `cli.printHelp` call in the suite. Fix landed in commit `2db1dc9` ("fix: zig 0.16.0 compat", 2026-04-15), after this doc was previously last-updated (2026-03-30), which is why it lingered as "Blocked".
- **Evidence:** `tests/integration.zig:39-46` (`ctx.stdout = .{ .file = devnull }` before `cli.printHelp(&cmd, &ctx)`); commit `2db1dc9`; 34 integration tests present and passing.
- **Resolved date:** 2026-06-11

### GAP-0082: DeprecatedWriter usage in command.zig and progress.zig [RESOLVED]

- **Issue:** [#41](https://gitlab.com/devnw/zig/cli/-/issues/41) (closed)
- **Category:** Code Quality / Performance
- **Severity:** Medium
- **Resolution:** Resolved by the Zig 0.16 upgrade. `DeprecatedWriter` was the Zig 0.15 writer type name; the project now requires Zig 0.16 and the type no longer exists anywhere in the codebase. The migration to buffered `file.writer(io, &buf)` happened automatically with the 0.16 API rename. Previously parked as Won't-Do "pending 0.16, not yet released" -- that rationale is now obsolete.
- **Evidence:** `build.zig.zon:28` (`minimum_zig_version = "0.16.0"`); `.gitlab-ci.yml:26` (`ZIG_VERSION: "0.16.0"`); `src/cli/command.zig` uses `file.writer(io, &buf)`; grep for `DeprecatedWriter` returns nothing; migration in commit `2db1dc9`.
- **Resolved date:** 2026-06-11

## Closed (Wave 1 -- Critical/High -- 2026-03-24)

### GAP-0060: Shell escape functions in all 4 completion generators [RESOLVED]

- **Category:** Security
- **Severity:** Critical
- **Resolution:** Escape functions implemented in all 4 generators (bash, zsh, fish, PowerShell) with ArenaAllocator and fast-path scan. Covers GAP-0009, GAP-0010, GAP-0011, GAP-S013-S021, GAP-P008, GAP-P009.
- **Evidence:** `bash.zig:87` ArenaAllocator + 41 escape references; `zsh.zig:77`; `fish.zig:47`; `powershell.zig:16`.
- **Resolved date:** 2026-03-24

### GAP-0061: Pager shell injection + env.zig migration [RESOLVED]

- **Category:** Security
- **Severity:** Critical
- **Resolution:** `/bin/sh -c` replaced with direct argv execution. `std.posix.getenv` replaced with `env.getEnvValueRuntime()`. Covers GAP-0008, GAP-Q001.
- **Evidence:** `pager.zig:57-58` uses `env_mod.getEnvValueRuntime()` + direct argv.
- **Resolved date:** 2026-03-24

### GAP-0062: Signal callback_count atomic [RESOLVED]

- **Category:** Security
- **Severity:** High
- **Resolution:** `callback_count` changed from plain `usize` to `std.atomic.Value(usize)` with `.store(.release)` and `.load(.acquire)`. Covers GAP-0014.
- **Evidence:** `signal.zig:60`
- **Resolved date:** 2026-03-24

### GAP-0063: fs.zig writeFileAtomic + isSafePath [RESOLVED]

- **Category:** Security
- **Severity:** High
- **Resolution:** Random temp suffix via `std.crypto.random.int(u32)`. `isSafePath` expanded blocklist includes `/etc/passwd`, `/etc/gshadow`, `/proc/self/`, `.ssh/`, and `..` traversal detection. Covers GAP-0016, GAP-0017, GAP-S018.
- **Evidence:** `fs.zig:59` random suffix; `fs.zig:127-142` expanded blocklist.
- **Resolved date:** 2026-03-24

### GAP-0064: JSON help escaping [RESOLVED]

- **Category:** Security
- **Severity:** Critical
- **Resolution:** `writeJsonEscapedString` helper added and applied to all string interpolations in `printJsonHelp`/`printJsonFlag`. Covers GAP-0012.
- **Evidence:** `help.zig:450`
- **Resolved date:** 2026-03-24

## Closed (Wave 2 -- Medium/Low -- 2026-03-24)

### GAP-0054: Issue #23 env var help section [RESOLVED]

- **Category:** Feature
- **Severity:** Medium
- **Resolution:** `show_env_section`, `env_header`, `show_standard_env_vars` added to HelpTemplate; `printSectionEnvVars()` implemented; `env_vars` HelpSection variant added; standard env vars (NO_COLOR, TERM) documented; 6 unit tests added.
- **Resolved date:** 2026-03-24

### GAP-0065: Man page roff escaping [RESOLVED]

- **Category:** Security
- **Severity:** Medium
- **Resolution:** `writeRoffEscaped` added at `help.zig:549` and applied to all user strings in `generateMan`. Covers GAP-0013.
- **Resolved date:** 2026-03-24

### GAP-0066: Password buffer zeroing [RESOLVED]

- **Category:** Security
- **Severity:** Medium
- **Resolution:** `defer @memset(&buffer, 0)` added to `password()` (POSIX) at `prompt.zig:164` and `inputSimple()` (Windows) at `prompt.zig:186`. Covers GAP-0015, GAP-S012, GAP-Q006, NEW-Q005.
- **Resolved date:** 2026-03-24

### GAP-0067: Dead code removal [RESOLVED]

- **Category:** Quality
- **Severity:** Medium
- **Resolution:** `printTextHelp` and `printFlag` (~215 lines) removed. `FlagValue.deinit()` removed. `or true` dead branch eliminated. `handleGlobalFlag` unused `next_arg` parameter removed. `resolveStdio` `.stdout` variant removed. Covers GAP-0022, GAP-0026, NEW-Q001, GAP-Q007, NQ-016.
- **Resolved date:** 2026-03-24

### GAP-0068: Version string "0.1.0" [RESOLVED]

- **Category:** Quality
- **Severity:** Medium
- **Resolution:** `root.zig` version updated to `"0.1.0"`. `run()` derives from `root.version` with `"0.0.0"` fallback. Covers GAP-0007.
- **Evidence:** `root.zig:66`, `parser.zig:598`
- **Resolved date:** 2026-03-24

### GAP-0069: PowerShell doc comment [RESOLVED]

- **Category:** Docs
- **Severity:** Low
- **Resolution:** `root.zig` doc comment updated to list all 4 shells including PowerShell.
- **Evidence:** `root.zig:15`
- **Resolved date:** 2026-03-24

### GAP-0070: color/tty env.zig migration [RESOLVED]

- **Category:** Quality
- **Severity:** Medium
- **Resolution:** All `std.posix.getenv` replaced with `env.zig` calls in color.zig and tty.zig. Covers GAP-0042, GAP-Q003.
- **Resolved date:** 2026-03-24

### GAP-0071: redactPath ownership fix [RESOLVED]

- **Category:** Quality
- **Severity:** Low
- **Resolution:** Non-sensitive path returns `allocator.dupe(u8, path)` ensuring all return values are caller-owned. Covers GAP-0019.
- **Evidence:** `fs.zig:117`
- **Resolved date:** 2026-03-24

### GAP-0072: Levenshtein bounds check [RESOLVED]

- **Category:** Performance/Security
- **Severity:** Low
- **Resolution:** Bounds check `if (b.len >= 256) return @max(a.len, b.len)` added for both `a` and `b`. Covers GAP-P003, NEW-S003.
- **Evidence:** `suggest.zig:16-17`
- **Resolved date:** 2026-03-24

### GAP-0073: Global flags dedup in completion generators [RESOLVED]

- **Category:** Quality
- **Severity:** Medium
- **Resolution:** All 4 completion generators + help.zig use `command.global_flags` iteration. Covers GAP-0025, NEW-Q002.
- **Resolved date:** 2026-03-24

### GAP-0074: Pager line_count usize [RESOLVED]

- **Category:** Performance
- **Severity:** Low
- **Resolution:** `line_count` changed from `u16` to `usize` at `pager.zig:36`. Covers GAP-P004.
- **Resolved date:** 2026-03-24

### Additional Wave 2 closures [RESOLVED]

- **NQ-001:** Silent error swallowing -- `env_parse_errors` array added to Parser; env parse failures surfaced with flag/env var context. `parser.zig:86-87,439-440,491-497`.
- **NQ-013:** run() doc comment expanded with full 9-step lifecycle at `parser.zig:584-596`.
- **NQ-029:** `splitAndAppendCsv` helper extracted at `parser.zig:335`.
- **GAP-0039:** Ownership doc comments added to `suggestAll`/`findByPrefix` at `suggest.zig:72,104`.
- **GAP-P013:** `collectUniqueGroups` helper extracted at `help.zig:220`.
- **GAP-P008/NP-001:** Escape functions with fast-path scan; no allocation for clean strings.
- **NEW-P001:** text.zig padding uses `appendNTimes` at lines 59, 72, 82, 96, 98.
- **NEW-P002:** stripAnsi uses span-based `appendSlice` at `color.zig:158`.
- **GAP-0037:** `applyDefaultsForCommand` skips secret flags at `parser.zig:434`.
- **NEW-Q004:** PowerShell escape stubs replaced with real implementations.
- **Resolved date:** 2026-03-24

## Won't Do (Wave 2 -- 2026-03-24)

### NQ-026: ParseResult.deinit allocator pattern consistency [WON'T DO]

- **Category:** Architecture
- **Severity:** Low
- **Reason:** Changing from parameter-based to stored allocator would alter the public API with no functional benefit. `Context.deinit()` already stores its allocator. API stability is prioritized.
- **Resolved date:** 2026-03-24

## Closed (Gap-Close Round 2 -- 2026-03-24)

### NQ-008: Prompt interactive tests [RESOLVED]

- **Category:** Quality / Tests
- **Severity:** Medium
- **Resolution:** Refactored all 5 prompt functions (`input`, `password`, `confirm`, `select`, `multiSelect`) to delegate to internal `*Internal` variants accepting generic `reader: anytype, writer: anytype` parameters. 30 new tests added using `std.io.fixedBufferStream` covering: valid input, defaults, empty handling, max_length, validators, EOF/Cancelled, confirm y/Y/yes/n/N/no/empty/invalid-retry, select valid/out-of-range/non-numeric, multiSelect comma-parsing/out-of-range/single-selection. Total tests: 710 (up from 680).
- **Evidence:** `src/prompt.zig` -- `inputInternal`, `passwordInternal`, `confirmInternal`, `selectInternal`, `multiSelectInternal` functions; 32 tests total in prompt.zig.
- **Resolved date:** 2026-03-24

### NP-010: Benchmark allocation tracking [RESOLVED]

- **Category:** Performance
- **Severity:** P3
- **Resolution:** Added `CountingAllocator` struct to `tests/bench.zig` that wraps the backing arena allocator via a full VTable implementation (alloc/resize/remap/free). Tracks `alloc_count`, `free_count`, and `total_bytes`. All benchmark functions now return `BenchResult` (timing + allocation stats). `printResult` displays allocs, frees, total bytes, and allocs/op alongside timing. Added `formatBytes` helper for human-readable byte output.
- **Evidence:** `tests/bench.zig` -- `CountingAllocator`, `BenchResult`, `formatBytes`, `printResult`.
- **Resolved date:** 2026-03-24

### NEW-P003: CI bench gate per-rule allow_failure [RESOLVED]

- **Category:** Performance / CI
- **Severity:** Info
- **Resolution:** Replaced job-level `allow_failure: true` with per-rule `allow_failure` in the `rules:` block of `.gitlab-ci.yml` bench-regression job. MR pipelines (`CI_PIPELINE_SOURCE == "merge_request_event"`) use `allow_failure: false` (blocking). Main branch and schedule pipelines retain `allow_failure: true` (soft).
- **Evidence:** `.gitlab-ci.yml` bench-regression job `rules:` block.
- **Resolved date:** 2026-03-24

### NEW-P004: CI apt caching conditional [RESOLVED]

- **Category:** Performance / CI
- **Severity:** Info
- **Resolution:** Wrapped `apt-get update && apt-get install` in `.gitlab-ci.yml` `.install-zig` template with a conditional check: `if ! command -v curl >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1`. When all three tools are already available, the apt-get step is skipped entirely.
- **Evidence:** `.gitlab-ci.yml` `.install-zig` template conditional guard.
- **Resolved date:** 2026-03-24

## Won't Do (Gap-Close Round 2 -- 2026-03-24)

### NQ-030: Hand-built JSON in printJsonHelp [WON'T DO]

- **Category:** Quality / Architecture
- **Severity:** Low
- **Reason:** Zig 0.15.2 has no `std.json` streaming writer. The existing `writeJsonEscapedString` helper already handles escaping correctly with 7 dedicated tests. A structural rewrite to a JSON builder would be a high-risk refactor with no safety benefit, since the output is structurally correct and properly escaped.
- **Resolved date:** 2026-03-24

### NP-012: PagerWriter streaming [WON'T DO]

- **Category:** Performance
- **Severity:** P3
- **Reason:** Pager buffers help text which is bounded by command tree size (typically a few KB). Streaming refactor would require significant architectural changes to the pager pipe model for marginal benefit. The buffered approach is correct for the bounded output size of CLI help text.
- **Resolved date:** 2026-03-24

## Closed (Gap-Close Session 2026-03-24)

### GAP-0051: Context missing getFloat() method [RESOLVED]

- **Category:** Feature
- **Severity:** Medium
- **Resolution:** getFloat() was already implemented (found existing during implementation review). No additional code changes needed.
- **Resolved date:** 2026-03-24

### GAP-0053: CI does not test minimum supported Zig version [RESOLVED]

- **Category:** CI-CD
- **Severity:** Low
- **Resolution:** Updated `build.zig.zon` `.minimum_zig_version` from `"0.15.1"` to `"0.15.2"` to match CI-tested version. Updated `README.md` Zig version references to `0.15.2+`.
- **Resolved date:** 2026-03-24

### GAP-0055: parser.zig getEnvVar() bypasses shared env.zig module [RESOLVED]

- **Category:** Code Quality
- **Severity:** Medium
- **Resolution:** parser.zig now uses `env.getEnvValueRuntime()` instead of `std.posix.getenv` directly, consistent with all other modules.
- **Resolved date:** 2026-03-24

### GAP-0058: SECURITY.md does not mention CI fuzz testing stage [RESOLVED]

- **Category:** Docs
- **Severity:** Low
- **Resolution:** SECURITY.md updated with fuzz testing mention, accurately reflecting the CI fuzz job implementation.
- **Resolved date:** 2026-03-24

## Closed (Initial Audit)

### GAP-0041: pager.zig uses raw std.posix.getenv instead of cross-platform helpers [REGRESSED]

- **Category:** Code Quality
- **Previous resolution:** `pager.zig` was updated to use shared `env.getEnvValueRuntime()` from `src/term/env.zig`.
- **Regression:** Fix lost in git stash data loss. `src/term/pager.zig:57` still uses `std.posix.getenv` directly. Re-tracked as part of GAP-0061.
- **Regression date:** 2026-03-24

### GAP-0042: Duplicated envVarExists/getEnvValue helpers in tty.zig and color.zig [REGRESSED]

- **Category:** Code Quality
- **Previous resolution:** Created `src/term/env.zig` with shared helpers. Both `tty.zig` and `color.zig` were updated to import from the shared module.
- **Regression:** Fix lost in git stash data loss. `color.zig` and `tty.zig` still use direct `std.posix.getenv` calls. Re-tracked as GAP-0070.
- **Regression date:** 2026-03-24

### GAP-0043: License header mismatch MIT vs Apache-2.0 in tests/integration.zig [RESOLVED]

- **Category:** Docs
- **Resolution:** Updated `tests/integration.zig` header from MIT to `SPDX-License-Identifier: Apache-2.0` / `Copyright (c) 2024-2025 CodePros`.
- **Evidence:** `tests/integration.zig:1-2` now matches all other source files.
- **Resolved date:** 2026-03-24

### GAP-0044: CI pipeline does not run integration tests [RESOLVED]

- **Category:** CI-CD
- **Resolution:** Added `zig-test-integration` and `zig-bench` jobs to `.gitlab-ci.yml`. Integration tests run `zig build test-integration`. 34 integration tests execute in CI.
- **Evidence:** `.gitlab-ci.yml` contains `zig-test-integration` job.
- **Resolved date:** 2026-03-24

### GAP-0045: ROADMAP.md claims issue #6 tests "hang" but they pass [RESOLVED]

- **Category:** Docs
- **Resolution:** Removed stale "Tests exist but hang" warning from ROADMAP.md for issue #6. The hang was resolved via GAP-0001.
- **Evidence:** `docs/ROADMAP.md` no longer contains the hang warning.
- **Resolved date:** 2026-03-24

### GAP-0046: root.zig doc comment omits PowerShell completions [REGRESSED]

- **Category:** Docs
- **Previous resolution:** Updated `src/root.zig` doc comment to include PowerShell.
- **Regression:** Fix lost in git stash data loss. `src/root.zig:15` still reads `(bash, zsh, fish)` without PowerShell. Re-tracked as GAP-0069.
- **Regression date:** 2026-03-24

### GAP-0049: Windows signal handler ignores Config parameter [RESOLVED]

- **Category:** Bug
- **Resolution:** Added comprehensive documentation to `Config` struct and `onCleanup()` noting which fields are POSIX-only vs cross-platform. Windows always handles CTRL_C_EVENT and CTRL_CLOSE_EVENT. The API contract is now explicit about platform behavior.
- **Evidence:** `src/signal.zig` doc comments on `Config` and `onCleanup()`.
- **Resolved date:** 2026-03-24

### GAP-0002: `zig build docs` step missing from build.zig [RESOLVED]

- **Category:** Docs
- **Resolution:** Zig 0.15 has no built-in autodoc build step. Updated Makefile `docs` target to generate man pages and shell completions instead of calling the nonexistent `zig build docs`. Acceptance criteria met: Makefile target corrected.
- **Resolved date:** 2026-03-24

### GAP-0001: Integration tests hang (timeout) [RESOLVED]

- **Category:** Bug
- **Resolution:** Root cause was the "help shows examples first" test calling `cli.printHelp()` which writes to stdout (fd 1). Under the Zig build system's test runner protocol (`--listen=-`), stdout is used as an IPC pipe between the build runner and the test binary. Help text written to stdout corrupted the protocol, causing a deadlock. Fixed by redirecting `ctx.stdout` to `/dev/null` in the test. All 34 integration tests and 528 unit tests (562 total) now pass.
- **Resolved date:** 2026-03-24

### GAP-0004: Fuzz testing claimed in SECURITY.md but not implemented [RESOLVED]

- **Category:** Docs
- **Resolution:** Removed false "Fuzz testing for parser inputs" claim from SECURITY.md. Replaced with "Input validation and bounds checking for parser inputs" which accurately reflects the codebase.
- **Resolved date:** 2026-03-24

### GAP-0032: ROADMAP.md lists 6 issues as closed that are open [RESOLVED]

- **Category:** Docs
- **Resolution:** Updated ROADMAP.md to reflect actual issue/implementation status. Issues #6, #8, #9 marked with appropriate warnings. Issues #19, #20, #23 marked as implemented with issues still open.
- **Resolved date:** 2026-03-24

### GAP-0033: GAPS.md is entirely stale [RESOLVED]

- **Category:** Docs
- **Resolution:** Rewrote GAPS.md to reflect that 10 of 11 Cobra gaps are now implemented. Only #12 (package registry) remains open.
- **Resolved date:** 2026-03-24

### GAP-0034: README.md lists wrong Zig version requirement [RESOLVED]

- **Category:** Docs
- **Resolution:** Fixed README to show "0.15.1+" matching build.zig.zon.
- **Resolved date:** 2026-03-24

### GAP-0035: README.md feature list omits implemented features [RESOLVED]

- **Category:** Docs
- **Resolution:** Expanded README feature list to include PowerShell completions, flag groups, persistent hooks, command groups, custom help templates, active help, markdown docs, table formatter, version command, and flag value completions.
- **Resolved date:** 2026-03-24

### GAP-0036: Pre-commit zig-fmt only covers src/ and build.zig [RESOLVED]

- **Category:** CI-CD
- **Resolution:** Added `tests/` and `examples/` to zig-fmt hook args in `.pre-commit-config.yaml`.
- **Resolved date:** 2026-03-24

### GAP-0040: ROADMAP.md claims v0.2.0 "Current" but no v0.2.0 exists [RESOLVED]

- **Category:** Docs
- **Resolution:** Changed v0.2.0 from "Current" to "Unreleased" in ROADMAP.md.
- **Resolved date:** 2026-03-24

### GAP-0050: API.md documents phantom types and wrong field names [RESOLVED]

- **Category:** Docs
- **Resolution:** Fixed all phantom types and wrong field names in `docs/API.md`: replaced `ArgsSpec` struct with `ArgsValidator` tagged union documentation, replaced `ActiveHelpFn` with actual function pointer type, replaced `ValidatorFn` with actual type `?*const fn ([]const u8) bool`, renamed `rule` to `group_type`, renamed `GroupRule` to `FlagGroupType`, fixed `help` and `ftype` to show no defaults (required fields), fixed custom validator example return type from `?[]const u8` to `bool`.
- **Evidence:** All type names, field names, and defaults in `docs/API.md` now match `src/cli/command.zig`.
- **Resolved date:** 2026-03-24

### GAP-0052: GETTING_STARTED.md uses wrong field names and non-portable API [RESOLVED]

- **Category:** Docs
- **Resolution:** Replaced `.callback` with `.run` (3 occurrences), `.default` with `.default_str`, and `std.os.argv` with `std.process.argsAlloc(allocator)`/`std.process.argsFree()` pattern in `docs/GETTING_STARTED.md`. All code examples now use field names matching the Command and FlagSpec structs.
- **Evidence:** `grep -n 'callback\|\.default[^_]\|std.os.argv' docs/GETTING_STARTED.md` returns no matches.
- **Resolved date:** 2026-03-24

### GAP-0056: Documentation examples use std.os.argv (POSIX-only) [RESOLVED]

- **Category:** Docs
- **Resolution:** Replaced all `std.os.argv` references with `std.process.argsAlloc(allocator)` pattern in `docs/GETTING_STARTED.md`, `docs/guides/CUSTOM_HELP_TEMPLATES.md`, and `docs/guides/ACTIVE_HELP.md`. Added bounds checking for args array access in ACTIVE_HELP.md example.
- **Evidence:** `grep -rn 'std.os.argv' docs/` returns no matches in documentation files (only GAP_ANALYSIS.md historical references remain).
- **Resolved date:** 2026-03-24

## Closed (Gap-Close Round 4 -- 2026-03-24)

### GAP-0075: API.md wrong type names [RESOLVED]

- **Category:** Docs
- **Severity:** Medium
- **Resolution:** All phantom type names replaced: `ArgsSpec` -> `ArgsValidator`, `GroupRule` -> `FlagGroupType`, `ValidatorFn` -> `?*const fn ([]const u8) bool`, `ActiveHelpFn` -> actual function pointer type. All type names verified against `src/cli/command.zig`.
- **Evidence:** `docs/API.md` -- all type names match `src/cli/command.zig` definitions.
- **Resolved date:** 2026-03-24

### GAP-0076: GETTING_STARTED.md wrong field names and deprecated std.os.argv [RESOLVED]

- **Category:** Docs
- **Severity:** High
- **Resolution:** Replaced `.callback` with `.run`, `.default` with `.default_str`, and `std.os.argv` with `std.process.argsAlloc(allocator)` / `std.process.argsFree()` throughout GETTING_STARTED.md.
- **Evidence:** `grep -n 'callback\|\.default[^_]\|std.os.argv' docs/GETTING_STARTED.md` returns no matches.
- **Resolved date:** 2026-03-24

### GAP-0077: Guide docs use deprecated std.os.argv [RESOLVED]

- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Replaced `std.os.argv` with `std.process.argsAlloc(allocator)` / `std.process.argsFree()` in `docs/guides/CUSTOM_HELP_TEMPLATES.md` and `docs/guides/ACTIVE_HELP.md`.
- **Evidence:** `grep -rn 'std.os.argv' docs/guides/` returns no matches.
- **Resolved date:** 2026-03-24

### GAP-0081: Integration tests fail -- module collision in build.zig [RESOLVED]

- **Category:** Bug
- **Severity:** High
- **Resolution:** Resolved `tty.zig` module collision in `build.zig` by deduplicating the module import so it is provided once and shared between `cli` and `term` modules. `zig build test-integration` compiles successfully.
- **Evidence:** `zig build test-integration` completes without module collision errors.
- **Resolved date:** 2026-03-24

### Quality Gap Closures (NQ-031 through NQ-049, 19 items) [RESOLVED]

All 19 Phase 3 quality findings closed. Key resolutions:

- **NQ-031:** OOM propagated in `applyEnvDefaults`/`applyDefaultsForCommand` (`parser.zig`)
- **NQ-032:** Signal handler async-safety documented (`signal.zig`)
- **NQ-033:** `writeFileAtomic` hardened -- fsync, mode 0o600, errdefer cleanup (`fs.zig`)
- **NQ-034:** Pager `min_lines` logic fixed (`pager.zig`)
- **NQ-035:** `run()` lifecycle tests added (50 new tests, 710->760 total)
- **NQ-036:** Flag inheritance walks full command chain (`parser.zig`)
- **NQ-037:** ANSI codes replaced with named constants (`help.zig`)
- **NQ-038:** Fixed-size buffer limits documented
- **NQ-039:** Version fallback constant extracted (`parser.zig`, `help.zig`)
- **NQ-040:** ColorContext stubs removed (`color.zig`)
- **NQ-041:** `printHelp`/`printVersion` error propagation (`help.zig`)
- **NQ-042:** JSON help includes flag descriptions (`help.zig`)
- **NQ-043:** `Command.usage()` generates from structure (`command.zig`)
- **NQ-044:** `ParseResult` stores allocator internally (`parser.zig`)
- **NQ-045:** Allocator inconsistency documented for v0.2.0 (`prompt.zig`)
- **NQ-046:** Global flags single-sourced (`command.zig`, `parser.zig`)
- **NQ-047:** `run()` decomposed into helpers (`parser.zig`)
- **NQ-048:** Secret handling documented (`command.zig`)
- **NQ-049:** `ArgsValidator.only_valid` empty behavior documented (`command.zig`)
- **Resolved date:** 2026-03-24

### Security Gap Closures (NS-008 through NS-020, 13 items) [RESOLVED]

All 13 Phase 3 security findings closed. Key resolutions:

- **NS-008:** Bash escape NUL/newline filtering (`bash.zig`)
- **NS-009:** Zsh escape NUL/newline filtering (`zsh.zig`)
- **NS-010:** Fish completion names escaped (`fish.zig`)
- **NS-011:** Roff newline injection fixed (`help.zig`)
- **NS-012:** JSON version output escaped (`help.zig`)
- **NS-013:** Signal handler documented (`signal.zig`)
- **NS-014:** Bash cmd.name validated (`bash.zig`)
- **NS-015:** PowerShell completion values escaped (`powershell.zig`)
- **NS-016:** Secret flag values zeroed (`command.zig`)
- **NS-017:** Pager limitations documented (`pager.zig`)
- **NS-018:** writeFileAtomic permissions fixed (`fs.zig`)
- **NS-019:** Windows active_config made atomic (`signal.zig`)
- **NS-020:** Markdown output escaping added (`help.zig`)
- **Resolved date:** 2026-03-24

### Performance Gap Closures (NP-013 through NP-018, 6 items) [RESOLVED]

All 6 Phase 3 performance findings closed. Key resolutions:

- **NP-013:** `ensureTotalCapacity` added to key ArrayLists (completion generators, parser)
- **NP-014:** CountingAllocator reset per iteration (`bench.zig`)
- **NP-015:** Medium-scale benchmarks added -- 20+ subcmds, 50+ flags (`bench.zig`)
- **NP-016:** CI bench warm-up and multi-run median (`.gitlab-ci.yml`, `bench.zig`)
- **NP-017:** `writeJsonEscapedString` span-based optimization (`help.zig`)
- **NP-018:** Global flags single-sourced (`bash.zig`, `command.zig`)
- **Resolved date:** 2026-03-24

## Won't Do (Gap-Close Session 2026-03-24)

### GAP-0057: build.zig.zon version 0.1.0 while v0.2.0 features implemented [WON'T DO]

- **Category:** Other
- **Severity:** Low
- **Reason:** Version bump is release management, not a code change. Tracked as GitLab issue #32 for when a release is prepared.
- **Resolved date:** 2026-03-24

### GAP-0059: help.zig and parser.zig exceed 800-line guidance [WON'T DO]

- **Category:** Code Quality
- **Severity:** Low
- **Reason:** Zig convention of colocated tests; production code portions are ~700-800 lines. The total file sizes are driven by colocated tests (Zig idiom), not poor separation of concerns. Splitting would add complexity with marginal readability benefit.
- **Resolved date:** 2026-03-24

## Won't Do (Initial)

### GAP-0003: Package not published to Zig registry [WON'T DO]

- **Category:** Other
- **Reason:** Requires external registry action, not a code change. Tracked as GitLab issue #12.
- **Resolved date:** 2026-03-24

### GAP-0047: Issues #19, #20, #23 implemented but GitLab issues still open [WON'T DO]

- **Category:** Other
- **Reason:** Closing GitLab issues requires human action on the GitLab platform, not a code change. This is a housekeeping task outside the scope of gap closure work.
- **Resolved date:** 2026-03-24

### GAP-0048: ColorContext.colored() and styled() are stub no-ops [WON'T DO]

- **Category:** Feature
- **Reason:** Implementing ANSI color wrapping in `colored()`/`styled()` is feature development, not a gap fix. The `writeColored()`/`writeStyled()` methods already provide working color output. Tracked for v0.2.0.
- **Resolved date:** 2026-03-24
