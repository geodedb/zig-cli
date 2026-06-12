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
| Low | 1 |
| **Total Open** | **1** |

The single remaining open item (GAP-0083) is future roadmap work, **not an
implementation gap**. Genuinely open implementation gaps: **0**.

audit iteration 2 (merge 3e2d804, 2026-06-12): the refactor merge resolved the
last two implementation/process gaps. GAP-0096 (file-size guidance) RESOLVED --
every tracked `.zig` file is now <= 800 lines (`bash scripts/check_file_size.sh
$(git ls-files '*.zig')` exits 0; largest is `src/cli/completion/bash.zig` at
768) and a `check-zig-file-size` pre-commit gate enforces it; `parse()` is now 47
lines (`parser.zig:165-211`). GAP-0084 (issue-tracker hygiene, #61) RESOLVED --
its blocking dependency #46 (parse() decomposition) is closed, the previously
stale-open issues (#29, #31, #32, #38, #43) are all closed, and #61 is closed;
the only remaining open issues are #35 (accepted-risk CI-tag-pinning policy,
NS-001 Won't-Do) and #12 (roadmap). Both GAP-0096 and GAP-0084 moved to RESOLVED
with merge 3e2d804 evidence. GAP-0083 (registry, #12) re-framed below as future
roadmap, kept open for visibility only.

audit iteration 1 fix merge (188bf5a, 2026-06-12): GAP-0097 (residual parser
`catch continue`) and GAP-0099 (prompt secret zeroing helper) resolved and moved
to RESOLVED with fix-commit evidence (d595798, 022e4cf). GAP-0098 (stale tracking
docs) resolved -- ROADMAP/GAPS reconciled, #123 closed -- and moved to RESOLVED.

---

## Open Gaps

### GAP-0083: Package not published to Zig package registry (future roadmap, not an implementation gap)

- **Issue:** [#12](https://gitlab.com/devnw/zig/cli/-/issues/12)
- **Category:** Roadmap / Feature (future)
- **Severity:** Low
- **Status:** Open for visibility only. This is **future roadmap work, not an
  implementation gap** in the current codebase. Registry publication requires an
  external registry action at release time, not a code change here (cf. the
  earlier GAP-0003 Won't-Do with the same rationale).
- **Requirement source:** Issue #12; `docs/ROADMAP.md` (v0.2.0)
- **Current state (evidence):**
  - `docs/ROADMAP.md` lists registry publication as planned v0.2.0 work; intentionally not yet implemented.
- **Why it is tracked:** Library is not yet consumable from the Zig package registry; consumers depend via git URL in the meantime.
- **Impact/Risk:** Low. Deferred roadmap item; no current functionality is missing or broken.
- **Planned action:** Publish to the Zig package registry when the project reaches v0.2.0 stability.
- **Acceptance criteria:**
  - [ ] Package is resolvable from the Zig package registry
  - [ ] ROADMAP reflects publication status

---

## Gap Priority Matrix

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 0 | -- |
| Low | 1 | GAP-0083 (roadmap, not an implementation gap) |

Genuinely open **implementation** gaps: **0**.

---

## Closed / Resolved

Resolved and won't-do items have been moved to
[GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md). Recent resolutions:

- **audit iteration 2 refactor merge (3e2d804, 2026-06-12):** GAP-0096
  (file-size guidance -- all `.zig` <= 800 + pre-commit gate; `parse()` 47 lines)
  and GAP-0084 (issue-tracker hygiene -- #46/#61 and remaining stale-open issues
  closed) resolved and moved to RESOLVED.
- **audit iteration 1 fix merge (2026-06-12):** GAP-0097 (parser env/default
  `catch continue` removed, fix d595798), GAP-0098 (stale tracking docs
  reconciled, #123 closed), GAP-0099 (prompt `freeSecret` zeroing helper, fix
  022e4cf).
- **codepros:audit Phase 4 (2026-06-11):** GAP-0091 (integration deadlock fixed
  in 2db1dc9), GAP-0082 (DeprecatedWriter resolved by Zig 0.16 upgrade).
- **Phase 4 Gap Closure (2026-03-25):** GAP-0085 through GAP-0090, GAP-0092
  through GAP-0094.
- **Waves 1-2:** GAP-0060 through GAP-0080 and earlier.
