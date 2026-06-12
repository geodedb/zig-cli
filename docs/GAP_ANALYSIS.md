# Gap Analysis

> This file contains ONLY open gaps. Resolved and won't-do items are in
> [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md).

Last updated: 2026-06-12

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 3 |
| **Total Open** | **3** |

audit iteration 1 fix merge (188bf5a, 2026-06-12): GAP-0097 (residual parser
`catch continue`) and GAP-0099 (prompt secret zeroing helper) resolved and moved
to RESOLVED with fix-commit evidence (d595798, 022e4cf). GAP-0098 (stale tracking
docs) resolved -- ROADMAP/GAPS reconciled, #123 closed -- and moved to RESOLVED.
GAP-0084 tracker hygiene: 14 of the remaining 15 stale-open issues closed with
evidence this pass; #46 (parse() decomposition) genuinely not implemented and
left open, so GAP-0084 stays OPEN with updated evidence. Remaining open gaps:
GAP-0083 (registry, future roadmap), GAP-0084 (tracker hygiene, near-complete),
GAP-0096 (file-size refactor, deferred). All Low severity.

---

## Open Gaps

### GAP-0083: Package not published to Zig package registry

- **Issue:** [#12](https://gitlab.com/devnw/zig/cli/-/issues/12)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** Issue #12; `docs/ROADMAP.md` (v0.2.0)
- **Current state (evidence):**
  - `docs/ROADMAP.md` lists registry publication as planned v0.2.0 work; not yet implemented
- **Why this is a gap:** Library is not yet consumable from the Zig package registry.
- **Impact/Risk:** Low. Deferred roadmap item; consumers can still depend via git URL.
- **Recommended fix:** Publish to the Zig package registry when the project reaches v0.2.0 stability.
- **Acceptance criteria:**
  - [ ] Package is resolvable from the Zig package registry
  - [ ] ROADMAP reflects publication status

---

### GAP-0084: GitLab issue hygiene -- resolved issues still open

- **Issue:** [#61](https://gitlab.com/devnw/zig/cli/-/issues/61)
- **Category:** Project Management
- **Severity:** Low
- **Requirement source:** Issue #61
- **Current state (evidence):**
  - 2026-06-12 pass: 14 of the prior 15 verified-resolved issues closed with file:line evidence comments (#36, #37, #42, #44, #45, #47, #48, #49, #50, #51, #53, #55, #56, #57)
  - **#46 (parse() decomposition) NOT closed:** verified partially-implemented only -- helpers exist (`handleFlagWithChain`) but `parse()` is still ~160 lines (`parser.zig:148-309`) with 4-level nesting; the issue's acceptance criteria (<80 lines, nesting <=3) are unmet. Left open as a deferred readability refactor.
  - Pre-existing stale-open issues outside this pass's scope still open: #29, #31, #32, #35, #38, #43 (triage in a follow-up).
- **Why this is a gap:** Issue tracker does not yet fully reflect actual project state. A handful of stale-open and one not-yet-implemented issue remain.
- **Impact/Risk:** Low. Cosmetic inconsistency between tracking files and issue tracker; #46 is a maintainability refactor with no functional impact.
- **Recommended fix:** Implement the #46 decomposition (or formally re-scope it), and triage the remaining pre-existing stale-open issues (#29, #31, #32, #35, #38, #43).
- **Acceptance criteria:**
  - [ ] All resolved gap items have corresponding GitLab issues in "closed" state (14/15 from this batch done; #46 pending implementation)
  - [x] Closed issues include resolution evidence in comments

---

### GAP-0096: help.zig, parser.zig, command.zig exceed 800-line file-size guidance

- **Issue:** [#34](https://gitlab.com/devnw/zig/cli/-/issues/34)
- **Category:** Code Quality
- **Severity:** Low
- **Requirement source:** Issue #34; R-011
- **Current state (evidence):**
  - `wc -l src/cli/help.zig src/cli/parser.zig src/cli/command.zig` -->
    - `src/cli/help.zig` -- 1836 lines (2.3x guidance)
    - `src/cli/parser.zig` -- 2096 lines (2.6x guidance)
    - `src/cli/command.zig` -- 1261 lines (1.6x guidance)
- **Why this is a gap:** Three core source files materially exceed the documented 800-line file-size guidance. Issue #34 tracked the requirement but no Gap-ID had been assigned, so it was invisible in the gap-tracking matrix.
- **Impact/Risk:** Low. Large files raise navigation/maintenance cost and review friction; no functional or security impact.
- **Recommended fix:** Split each file along existing seams without behavior change (e.g. extract env/default resolution from `parser.zig`, help-section/man-page rendering from `help.zig`, accessor/validator helpers from `command.zig`). Keep public API stable via re-exports.
- **Acceptance criteria:**
  - [ ] No file under `src/cli/` exceeds 800 lines, OR the guidance is formally amended with rationale
  - [ ] `zig build test --summary all` and `zig build test-integration` remain green
  - [ ] Public API surface (root.zig / cli.zig exports) unchanged

---

## Gap Priority Matrix

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 0 | -- |
| Low | 3 | GAP-0083, GAP-0084, GAP-0096 |

---

## Closed / Resolved

Resolved and won't-do items have been moved to
[GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md). Recent resolutions:

- **audit iteration 1 fix merge (2026-06-12):** GAP-0097 (parser env/default
  `catch continue` removed, fix d595798), GAP-0098 (stale tracking docs
  reconciled, #123 closed), GAP-0099 (prompt `freeSecret` zeroing helper, fix
  022e4cf).
- **codepros:audit Phase 4 (2026-06-11):** GAP-0091 (integration deadlock fixed
  in 2db1dc9), GAP-0082 (DeprecatedWriter resolved by Zig 0.16 upgrade).
- **Phase 4 Gap Closure (2026-03-25):** GAP-0085 through GAP-0090, GAP-0092
  through GAP-0094.
- **Waves 1-2:** GAP-0060 through GAP-0080 and earlier.
