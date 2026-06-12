# Audit Iteration 1 Refactor Plan (file sizes + dedup)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close GAP-0096 (#34: `help.zig` 2346L / `parser.zig` 2233L / `command.zig` 1311L exceed the 800-line guidance) and NQ-NEW-014 (#140: sanitizer triplication + generator helper duplication), with a pre-commit gate so the file-size class cannot recur.

**Architecture:** (a) A new first-class `sanitize` module (own module root, wired by name into cli/term/util/zig_cli and every test module) replaces the three predicate-synced mirrors. (b) Pure mechanical file splits within each existing module — public APIs preserved via re-exports from the original file paths; tests move with the code they exercise (private access), or into `*_test.zig` siblings when they only use public API. (c) A line-count pre-commit hook enforces ≤800 lines per `.zig` file.

**Tech Stack:** Zig 0.16.0. Gates per task: `zig fmt src/ build.zig`, `zig build test --summary all`, `zig build test-integration --summary all`, `zig build check` (+ `-Dtarget=x86_64-windows`), `pre-commit run --all-files` before each commit.

**Branch:** `refactor/audit-iter1` from `main`.

**Hard acceptance criteria (every task must keep):**

- Zero public-API changes: `examples/demo.zig`, `tests/integration.zig`, `benchmarks/*` compile UNCHANGED.
- Test count never decreases (currently 929 unit + 34 integration).
- After Task 7: no `.zig` file in `src/` or `tests/` exceeds 800 lines.

---

## Tasks

### Task 1: First-class `sanitize` module (kills the three mirrors)

**Files:**

- Create: `src/sanitize.zig` (module root — must NOT be `@import`ed by file path from any other src file)
- Modify: `build.zig` (create module, wire imports), `src/util/text.zig` (delegate to module, keep re-exports), `src/cli/help.zig` (delete `textutil` mirror, import named module), `src/term/{sanitize.zig→deleted, color.zig, progress.zig, table.zig}` (import named module), `src/term.zig` (drop sanitize.zig test aggregation)

- [ ] **Step 1:** Create `src/sanitize.zig` containing the canonical implementations currently in `src/util/text.zig`: `isTerminalControl` (make it `pub` here), `writeControlFiltered`, `stripControlChars`, `utf8FloorIndex`, with their doc comments (CWE-150 / CR rationale / NS-062) and ALL their tests (including the exhaustive 0x00–0xFF policy test and the utf8 corpus incl. the 4-byte emoji case). Module doc: "Terminal output sanitization. First-class module so cli/term/util can share one implementation (a plain src/ file may belong to only one module)."
- [ ] **Step 2:** `build.zig`: create the module and wire it everywhere:

```zig
const sanitize_mod = b.addModule("sanitize", .{
    .root_source_file = b.path("src/sanitize.zig"),
    .target = target,
    .optimize = optimize,
});
```

Then `addImport("sanitize", sanitize_mod)` on: `cli_mod`, `term_mod`, `util_mod`, `zig_cli_mod`, and EVERY `b.createModule` used by test steps that compile cli/term/util/root sources (cli_tests, term_tests, util_tests, root_tests, integration tests, bench/scale-bench modules if they compile these sources — let the compiler enumerate: build, fix, repeat). Add a test step for the sanitize module itself mirroring how other module tests are wired, and register it in the main `test` step.

- [ ] **Step 3:** `src/util/text.zig`: replace the four canonical implementations with thin delegating re-exports so the documented public path `util.text.stripControlChars` (referenced by SECURITY.md) keeps working:

```zig
const sanitize = @import("sanitize");

/// Re-export: see the `sanitize` module (single source of truth).
pub const writeControlFiltered = sanitize.writeControlFiltered;
pub const stripControlChars = sanitize.stripControlChars;
pub const utf8FloorIndex = sanitize.utf8FloorIndex;
```

Delete `isTerminalControl` and the moved tests from text.zig (they live in sanitize.zig now); KEEP text.zig's `truncate` (it calls `utf8FloorIndex` — now via the re-export) and all other text functions/tests.

- [ ] **Step 4:** `src/cli/help.zig`: delete the embedded `textutil` mirror struct and its two sync tests; add `const sanitize = @import("sanitize");` and mechanically replace `textutil.writeControlFiltered` → `sanitize.writeControlFiltered` (grep for all uses).
- [ ] **Step 5:** Delete `src/term/sanitize.zig`. In `color.zig`, `progress.zig`, `table.zig`: change `@import("sanitize.zig")` → `@import("sanitize")`. Remove the `_ = @import("term/sanitize.zig");` line from `src/term.zig`'s test block.
- [ ] **Step 6:** Run the full gate (fmt, test, test-integration, check, check -Dtarget=x86_64-windows). Fix any missed module wiring the compiler reports. Confirm test count ≥ 929 minus the deleted duplicate sync/mirror tests plus sanitize-module tests (report exact numbers).
- [ ] **Step 7:** Commit: `refactor(sanitize): single first-class sanitize module replaces three mirrors` body `Refs: #140`.

### Task 2: Split command.zig (1311L → two files ≤800)

**Files:**

- Create: `src/cli/context.zig`
- Modify: `src/cli/command.zig`, `src/cli.zig` (test aggregation if it lists files explicitly)

- [ ] **Step 1:** Read `src/cli/command.zig` fully and `src/cli.zig`. Move to `src/cli/context.zig`: `StdioWriter`, `io_global`, `FlagValue`, `Context` (with all methods incl. `getBoolOpt`, `deinit` and their doc comments), and every test that exercises them (the Context accessor tests, deinit tests, StdioWriter tests).
- [ ] **Step 2:** `command.zig` keeps `FlagType`, `SecretPolicy`, `FlagSpec`, `Command`, `global_flags`, validation, and their tests; add `const context = @import("context.zig");` plus re-exports preserving every existing public path:

```zig
pub const Context = context.Context;
pub const FlagValue = context.FlagValue;
pub const StdioWriter = context.StdioWriter;
```

(Check what parser.zig/help.zig/completion files/root.zig/cli.zig reference via `command.X` — ALL must keep compiling unchanged.)

- [ ] **Step 3:** If `src/cli.zig` aggregates tests by file list, add `_ = @import("cli/context.zig");`. Verify both files ≤800 lines (`wc -l`). Full gate. Commit: `refactor(cli): split Context/FlagValue/StdioWriter into context.zig` body `Refs: #34`.

### Task 3: Split help.zig (2346L → ≤800 each)

**Files:**

- Create: `src/cli/help/markdown.zig`, `src/cli/help/man.zig`, `src/cli/help/json.zig`, `src/cli/help/text.zig` (if needed for balance)
- Modify: `src/cli/help.zig`, `src/cli.zig` (test aggregation)

- [ ] **Step 1:** Read help.zig structure. Move by responsibility, tests following their code:
  - `help/markdown.zig`: `generateMarkdown`, `generateMarkdownCommand`, `writeMarkdownEscaped`, `writeMarkdownHeading`, `writeMarkdownProse`, `writeFenceSafe`, `collectUniqueGroups` IF markdown-only (check users first — if shared with text renderer, see Task 5), + all markdown tests.
  - `help/man.zig`: `generateMan`, `writeRoffEscaped` + roff tests.
  - `help/json.zig`: `printJsonHelp`, `printJsonFlag`, `writeJsonEscapedString`, version-JSON helpers (check `printVersionImpl`'s JSON branch — keep cohesion: if version printing is small, leave in help.zig) + JSON tests.
  - `help.zig` keeps: `HelpTemplate` + presets, the public `printHelp*`/`printVersion*` entry points, the plain-text renderer (`printTextHelpWithTemplate`, `renderTextSection`, `printSection*`, `printFlagWithTemplate`, `printEnvVarEntry`) and text-renderer tests. If that still exceeds 800, additionally move the plain-text section printers + their tests to `help/text.zig` keeping dispatch in help.zig.
- [ ] **Step 2:** Re-export moved public symbols from help.zig (e.g. `pub const generateMan = @import("help/man.zig").generateMan;` etc.) so cli.zig/root.zig/completion/tests/integration compile unchanged. The split files import what they need: `@import("../command.zig")`, `@import("sanitize")`.
- [ ] **Step 3:** Wire test aggregation (`src/cli.zig` test block: `_ = @import("cli/help/markdown.zig");` etc.). `wc -l` every result ≤800. Full gate; test count must not drop. Commit: `refactor(cli): split help generators into help/{markdown,man,json}.zig` body `Refs: #34`.

### Task 4: Split parser.zig (2233L → ≤800 each)

**Files:**

- Create: `src/cli/parser_test.zig` (public-API tests), possibly `src/cli/parser/env.zig`
- Modify: `src/cli/parser.zig`, `src/cli.zig`

- [ ] **Step 1:** Audit the 74 tests in parser.zig: classify each as (a) public-API-only (uses `Parser.init`, `parse`, pub fields like `invalid_default_flag`, `missing_required_flag`) or (b) private-access (calls file-private fns). Move ALL class-(a) tests to `src/cli/parser_test.zig` (`const parser_mod = @import("parser.zig");` — same module, public decls visible). Class-(b) tests stay with their code.
- [ ] **Step 2:** If parser.zig impl (~886L) still exceeds 800 after test extraction, extract the env-default machinery (`applyEnvDefaults`, `applyEnvDefaultsForCommand`, `getEnvVar`, `EnvParseErrorEntry` and class-(b) tests of those) into `src/cli/parser/env.zig` as free functions taking `*Parser` (forward-declare via `@import("../parser.zig").Parser`; circular file imports within a module are legal in Zig — verify it compiles; if the cycle fights you, instead extract `formatParseError` + error-rendering, which only reads pub fields).
- [ ] **Step 3:** If parser_test.zig itself exceeds 800 lines, split it by theme (`parser_test.zig` + `parser_env_test.zig`). Wire all new files into cli.zig's test aggregation. `wc -l` all ≤800. Full gate; test count identical. Commit: `refactor(cli): extract parser public-API tests and env machinery to satisfy file-size guidance` body `Refs: #34`.

### Task 5: Generator helper dedup (NQ-NEW-014, #140)

**Files:**

- Create: `src/cli/help/common.zig` (only if ≥2 real duplications found)
- Modify: the help/* files from Task 3

- [ ] **Step 1:** With the split done, diff the four renderers (text/markdown/man/json) for genuinely duplicated logic: group collection (`collectUniqueGroups`), flag display-name/short-flag formatting, env-name derivation, hidden-subcommand filtering loops. Extract ONLY real duplicates (≥2 call sites, identical semantics) into `help/common.zig`. Do NOT build a template engine; do NOT unify escapers (they are context-specific by design — that was finding NS-060's whole point).
- [ ] **Step 2:** Full gate. Update issue #140 expectations: this closes NQ-NEW-014's actionable scope. Commit: `refactor(cli): extract shared help-generator helpers into help/common.zig` body `Refs: #140 #34`. If Step 1 finds nothing real to extract beyond `collectUniqueGroups`, do that one extraction, note it, and keep the commit.

### Task 6: File-size pre-commit gate

**Files:**

- Create: `scripts/check_file_size.sh`
- Modify: `.pre-commit-config.yaml`

- [ ] **Step 1:** Create `scripts/check_file_size.sh` (mark executable):

```bash
#!/usr/bin/env bash
# Enforce the 800-line guidance for Zig source files (GAP-0096 / #34).
set -euo pipefail
LIMIT=800
status=0
for f in "$@"; do
  case "$f" in
    *.zig) ;;
    *) continue ;;
  esac
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$LIMIT" ]; then
    echo "ERROR: $f has $lines lines (limit $LIMIT). Split it (see docs/superpowers/plans/2026-06-12-audit-iter1-refactor.md)."
    status=1
  fi
done
exit $status
```

- [ ] **Step 2:** Add to `.pre-commit-config.yaml` (match the existing local-hook style used by `detect diamond deps`):

```yaml
  - id: check-zig-file-size
    name: check zig file size (<=800 lines)
    entry: scripts/check_file_size.sh
    language: script
    files: '\.zig$'
```

- [ ] **Step 3:** `pre-commit run check-zig-file-size --all-files` — must pass (it will fail if Tasks 2–4 left anything >800; fix there, not by raising the limit). Run `shellcheck scripts/check_file_size.sh`. Commit: `ci: enforce 800-line guidance for zig files in pre-commit` body `Refs: #34`.

### Task 7: Full verification gate

- [ ] All of: `zig fmt --check src/ tests/ build.zig` · `zig build check` · `zig build check -Dtarget=x86_64-windows` · `zig build test --summary all` · `zig build test-integration --summary all` · `zig build bench` (sanity vs previous run: parser ~415-636ns, help ~636ns-1.4us, bash completion ~429ns small / ~4us medium — no regression >10%) · `pre-commit run --all-files`.
- [ ] `wc -l src/**/*.zig src/*.zig tests/*.zig | sort -rn | head` — nothing above 800.
- [ ] Verify examples/demo + integration compiled UNCHANGED (`git diff --stat main -- examples/ tests/` shows nothing or only intended test-aggregation edits).
- [ ] Do NOT merge — the orchestrator merges after final review.
