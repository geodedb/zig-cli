# Gap Analysis

> This file contains ONLY open gaps. Resolved and won't-do items are in
> [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md).

Last updated: 2026-03-30

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 0 |
| Low | 1 |
| **Total Open** | **2** |

Phase 4 gap closure completed 2026-03-25. 9 gaps closed (GAP-0085 through
GAP-0090, GAP-0092 through GAP-0094). 1 marked Won't Do (GAP-0095). 1 marked
Blocked (GAP-0091). GAP-0084 remains open (manual review required).
786/786 tests pass. Format and build clean.

---

## Open Gaps

### GAP-0084: GitLab issue hygiene -- 20+ issues still open despite being resolved

- **Issue:** #61
- **Category:** Project Management
- **Severity:** Low
- **Requirement source:** Issue #61
- **Current state (evidence):**
  - Multiple GitLab issues remain in "open" state despite their corresponding gap items being resolved in code and tracking files
- **Why this is a gap:** Issue tracker does not reflect actual project state. Users and contributors see stale open issues.
- **Impact/Risk:** Low. Cosmetic inconsistency between tracking files and issue tracker.
- **Recommended fix:** Close resolved GitLab issues with evidence comments. Requires manual review of each issue.
- **Acceptance criteria:**
  - [ ] All resolved gap items have corresponding GitLab issues in "closed" state
  - [ ] Closed issues include resolution evidence in comments

---

### GAP-0091: Integration tests hang/timeout -- printHelp stdout deadlock

- **Issue:** [#96](https://gitlab.com/devnw/zig/cli/-/issues/96)
- **Category:** Bug
- **Severity:** High
- **Status:** **Blocked**
- **Requirement source:** CI pipeline -- test-integration stage; test/integration/
- **Current state (evidence):**
  - `zig build test-integration` hangs indefinitely
  - printHelp writes to stdout which deadlocks in the test harness
  - Tests cannot complete, blocking CI validation of integration scenarios
- **Why this is a gap:** Integration test suite is non-functional due to stdout deadlock, preventing CI from catching integration regressions.
- **Impact/Risk:** High. Integration test suite is effectively unusable. Regressions in CLI integration behavior cannot be caught by CI.
- **Blocker:** Pre-existing issue predating Phase 4. Requires investigation into Zig test runner stdout IPC protocol interaction with printHelp. Separate investigation track needed.
- **Unblock steps:**
  1. Investigate stdout deadlock in printHelp during test execution
  2. Use buffered writer or capture output to avoid pipe deadlock
  3. Add timeout guards to integration test runner
  4. Verify `zig build test-integration` completes within reasonable time
- **Acceptance criteria:**
  - [ ] `zig build test-integration` completes without hanging
  - [ ] All integration tests pass or fail with clear diagnostics (no deadlocks)
  - [ ] CI can run integration tests reliably

---

## Won't Do (Phase 3-4)

| Gap-ID | Title | Severity | Reason |
|--------|-------|----------|--------|
| GAP-0082 | DeprecatedWriter usage in command.zig and progress.zig | Medium | `DeprecatedWriter` is the Zig 0.15 name for the writer type. Migration to the renamed type requires Zig 0.16 which is not yet released. Will be addressed when the project upgrades to Zig 0.16. Tracked as issue #41. |
| GAP-0083 | Package not published to Zig registry | Low | Publishing to the Zig package registry is planned for v0.2.0. The project is not yet stable enough for registry publication. Tracked as issue #12. |
| GAP-0095 | No test coverage reporting in CI | Low | Zig 0.15 test coverage tooling is immature. `zig build test` does not produce standard coverage output. Adding coverage would require third-party tooling with significant maintenance burden for limited value. CHANGELOG coverage claim addressed separately. |

---

## Gap Priority Matrix

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 1 | GAP-0091 (Blocked) |
| Medium | 0 | -- |
| Low | 1 | GAP-0084 |

## Stash Data Loss Regression Summary

6 of 10 new gaps are regressions of previously-resolved documentation fixes
lost in git stash data loss:

| Original Gap | New Gap | Component | Status |
|-------------|---------|-----------|--------|
| GAP-0050 | GAP-0075 | API.md wrong type names | Closed |
| GAP-0052, GAP-0056 | GAP-0076 | GETTING_STARTED.md field names + std.os.argv | Closed |
| GAP-0056 | GAP-0077 | Guide docs std.os.argv | Closed |
| GAP-0033 | GAP-0078 | GAPS.md stale feature claims | Closed |
| GAP-0040 | GAP-0079 | ROADMAP.md version label | Closed |
| GAP-0035 | GAP-0080 | README.md stale feature list | Closed |

### Previous Stash Data Loss (Waves 1-2, all re-closed)

The following previously-closed gaps regressed due to git stash data loss
and have been re-implemented:

| Original Gap | New Gap | Component | Wave | Status |
|-------------|---------|-----------|------|--------|
| GAP-0009, GAP-0010, GAP-0011, GAP-S013--GAP-S021, GAP-P008, GAP-P009 | GAP-0060 | Completion escape functions | 1 | Closed |
| GAP-0008 | GAP-0061 | Pager shell injection | 1 | Closed |
| GAP-0014 | GAP-0062 | Signal atomic callback_count | 1 | Closed |
| GAP-0016, GAP-0017, GAP-S018 | GAP-0063 | fs.zig security hardening | 1 | Closed |
| GAP-0012 | GAP-0064 | JSON help escaping | 1 | Closed |
| GAP-0013 | GAP-0065 | Man page roff escaping | 2 | Closed |
| GAP-0015, GAP-S012 | GAP-0066 | Password buffer zeroing | 2 | Closed |
| GAP-0022, GAP-0026 | GAP-0067 | Help dead code removal | 2 | Closed |
| GAP-0007 | GAP-0068 | Version string drift | 2 | Closed |
| GAP-0046 | GAP-0069 | Root doc comment | 2 | Closed |
| GAP-0042, GAP-Q003 | GAP-0070 | color/tty env.zig migration | 2 | Closed |
| GAP-0019 | GAP-0071 | redactPath ownership | 2 | Closed |
| GAP-P003 | GAP-0072 | Levenshtein bounds check | 2 | Closed |
| GAP-0025 | GAP-0073 | Global flags dedup | 2 | Closed |
| GAP-P004 | GAP-0074 | Pager line_count overflow | 2 | Closed |

---

## Closed (Previous Waves)

Closed gaps have been moved to [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md).
Summary of closures:

- **Phase 4 Gap Closure (2026-03-25):** GAP-0085 through GAP-0090, GAP-0092 through GAP-0094 (9 gaps)
- **Wave 1 (Critical/High):** GAP-0060 through GAP-0064 (5 gaps)
- **Wave 2 (Medium/Low):** GAP-0054, GAP-0065 through GAP-0074 (11 gaps)
- **Gap-Close Round 2:** NQ-008, NP-010, NEW-P003, NEW-P004 (4 gaps)
- **Gap-Close Round 3:** GAP-0078, GAP-0079, GAP-0080 (3 gaps -- docs updates)
- **Gap-Close Round 4:** GAP-0075, GAP-0076, GAP-0077, GAP-0081 (4 gaps -- docs + integration test fix)
- **Phase 4 Parallelism:** GAP-0085, GAP-0086, GAP-0087, GAP-0088, GAP-0089 (5 gaps -- spice integration, thread safety, signal refactor, docs)
- **Initial Audit:** GAP-0001, GAP-0002, GAP-0004, GAP-0032 through GAP-0036, GAP-0040 through GAP-0056, GAP-0058 (18 gaps)
