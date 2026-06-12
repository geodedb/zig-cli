# Gap Analysis

> This file contains ONLY open gaps. Resolved and won't-do items are in
> [GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md).

Last updated: 2026-06-11

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 6 |
| **Total Open** | **6** |

codepros:audit Phase 4 (2026-06-11): 4 new gaps assigned stable IDs
(GAP-0096..GAP-0099). GAP-0091 resolved (fixed in commit 2db1dc9, integration
deadlock) and moved to RESOLVED. GAP-0082 retired from Won't-Do (resolved by Zig
0.16 upgrade) and moved to RESOLVED. 11 stale-open GitLab issues closed with
evidence as part of GAP-0084 tracker hygiene (15 remain). All open gaps are
Low severity.

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
  - 11 stale-open issues closed with evidence this run (#96, #41, #26, #8, #9, #19, #20, #23, #27, #28, #33)
  - 15 issues remain verified-resolved-in-code but OPEN in GitLab: #36, #37, #42, #44, #45, #46, #47, #48, #49, #50, #51, #53, #55, #56, #57
- **Why this is a gap:** Issue tracker does not yet fully reflect actual project state. Contributors see stale open issues.
- **Impact/Risk:** Low. Cosmetic inconsistency between tracking files and issue tracker.
- **Recommended fix:** Close the remaining 15 resolved GitLab issues with evidence comments (map to Closed NQ-/NP-/NS- items per gap-scan.md R-017..R-037 table).
- **Acceptance criteria:**
  - [ ] All resolved gap items have corresponding GitLab issues in "closed" state
  - [ ] Closed issues include resolution evidence in comments

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

### GAP-0097: Residual silent `catch continue` in parser env/default resolution

- **Issue:** [#39](https://gitlab.com/devnw/zig/cli/-/issues/39)
- **Category:** Code Quality (reliability / error-handling)
- **Severity:** Low
- **Requirement source:** Issue #39; R-019. Related closed work: NQ-001, NQ-031 (env *parse* errors now recorded).
- **Current state (evidence):**
  - `src/cli/parser.zig:503` -- `self.setFlagValue(ctx, flag.name, fval) catch continue;` -- a successfully-parsed env value that then fails to write to the context (e.g. OOM) is silently dropped. The `env_parse_error` recording only captures *parse* failures, not this *write* failure.
  - `src/cli/parser.zig:547` -- `const fval = self.parseValue(flag.ftype, def) catch continue;` -- a malformed `flag.default_str` is silently ignored; no diagnostic is recorded. (The next line uses `try self.setFlagValue(...)`, so the asymmetry is specifically the `parseValue` swallow.)
- **Why this is a gap:** Issue #39 / NQ-001 were closed because env *parse* errors are now surfaced, but these two paths still swallow errors silently, partially satisfying the "no silent error swallowing" requirement.
- **Impact/Risk:** Low. OOM during env application is rare; a malformed `default_str` is an author-time constant typically caught in dev/test. Both violate the documented "surface, don't swallow" intent.
- **Recommended fix:**
  - `parser.zig:503`: propagate the `setFlagValue` error, or record it into `env_parse_errors[]` like the parse-failure branch so it is reported via `formatParseError`.
  - `parser.zig:547`: record a developer-facing diagnostic (or debug-build assertion) for a bad `default_str` rather than `continue` silently.
- **Acceptance criteria:**
  - [ ] No bare `catch continue` remains on the env-application write path or default-resolution parse path in `parser.zig` without recording/propagating the error
  - [ ] A unit test asserts a malformed `default_str` produces a surfaced error/diagnostic
  - [ ] `zig build test --summary all` green

---

### GAP-0098: Stale gap-tracking docs (Makefile/version refs, ROADMAP "Closed" markers)

- **Issue:** [#123](https://gitlab.com/devnw/zig/cli/-/issues/123) (folds #31, #32)
- **Category:** Docs (tracking-doc accuracy)
- **Severity:** Low
- **Requirement source:** Issues #31 (ROADMAP/GAPS sync), #32 (version alignment); R-013, R-014. Phase 2 scan (gap-scan.md Key Discoveries 1 & 4).
- **Current state (evidence):**
  - This run: GAP-0091 moved to RESOLVED with commit evidence; GAP-0082 retired from Won't-Do; `docs/GAP_ANALYSIS.md` "Last updated" bumped to 2026-06-11; `Makefile:185` updated from "Zig 0.15.2" to "Zig 0.16.0 or compatible".
  - Residual: `docs/ROADMAP.md` marks #8/#9/#19/#20/#23 "Closed" -- now reconciled in GitLab by this run's closures, but ROADMAP/GAPS doc-to-tracker sync should be re-verified end-to-end.
- **Why this is a gap:** The canonical tracking docs have drifted from current state; reconciliation is in progress but ROADMAP/GAPS full sync remains to be verified.
- **Impact/Risk:** Low (cosmetic/process). Can cause duplicated investigation effort.
- **Recommended fix:** Re-verify `docs/ROADMAP.md` and `docs/GAPS.md` against the post-closure GitLab state; confirm no remaining stale "Closed"/"Open" mismatches (overlaps GAP-0084).
- **Acceptance criteria:**
  - [x] GAP-0091 no longer listed as open/Blocked; appears in RESOLVED with commit evidence
  - [x] GAP-0082 removed from Won't-Do (moved to RESOLVED as resolved-by-0.16)
  - [x] Makefile references Zig 0.16.0
  - [x] `docs/GAP_ANALYSIS.md` "Last updated" reflects this run
  - [ ] `docs/ROADMAP.md` / `docs/GAPS.md` reconciled with post-closure GitLab state

---

### GAP-0099: prompt.password() returned secret not zeroed by library on free

- **Issue:** [#40](https://gitlab.com/devnw/zig/cli/-/issues/40)
- **Category:** Security (hardening)
- **Severity:** Low
- **Requirement source:** Issue #40; R-029. Related closed work: NS-003, GAP-0066.
- **Current state (evidence):**
  - `src/prompt.zig:262-273` (`passwordInternal`) -- the intermediate `line` buffer IS zeroed (`defer { @memset(line, 0); allocator.free(line); }`), but the value RETURNED via `allocator.dupe(...)` at `:273` is **not** zeroed by the library.
  - `src/prompt.zig:188-197` -- the public `password()` doc comment delegates zeroing of the returned secret to the caller (`@memset(pw, 0)` before `allocator.free(pw)`).
  - Tests zero the result in their own `defer`, modeling the caller pattern but not library enforcement.
- **Why this is a gap:** The requirement is only partially met -- the library zeroes its internal buffer but cannot guarantee the returned secret is wiped; that depends on every caller following the documented pattern.
- **Impact/Risk:** Low. Residual password material may persist in freed heap if a caller forgets to zero. Mitigations: intermediate buffer wiped; pattern documented; tests model it.
- **Recommended fix (pick one):**
  - Provide a zeroizing `SecretString` wrapper whose `deinit()` memsets-then-frees and return it from `password()`; OR
  - Add a `password.free(allocator, pw)` convenience that zeroes-then-frees; OR
  - Accept current design as Won't-Do with explicit recorded rationale and close #40 as Documented.
- **Acceptance criteria:**
  - [ ] Returned secret is wiped via a library-provided zeroizing type/free helper with a test asserting the buffer is zeroed after teardown, OR #40 is explicitly closed as Won't-Do/Documented with recorded rationale
  - [ ] `zig build test --summary all` green

---

## Gap Priority Matrix

| Severity | Count | Gap-IDs |
|----------|-------|---------|
| Critical | 0 | -- |
| High | 0 | -- |
| Medium | 0 | -- |
| Low | 6 | GAP-0083, GAP-0084, GAP-0096, GAP-0097, GAP-0098, GAP-0099 |

---

## Closed / Resolved

Resolved and won't-do items have been moved to
[GAP_ANALYSIS_RESOLVED.md](GAP_ANALYSIS_RESOLVED.md). Recent resolutions:

- **codepros:audit Phase 4 (2026-06-11):** GAP-0091 (integration deadlock fixed
  in 2db1dc9), GAP-0082 (DeprecatedWriter resolved by Zig 0.16 upgrade).
- **Phase 4 Gap Closure (2026-03-25):** GAP-0085 through GAP-0090, GAP-0092
  through GAP-0094.
- **Waves 1-2:** GAP-0060 through GAP-0080 and earlier.
