# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.13] - 2026-09-25

### Changed

- Bump config pin to v0.1.16 (json v0.1.18: `\u` escapes take exactly 4 hex digits) so cli -> config -> json converges with policy on a single json version (SONNY-2768).

## [0.1.12] - 2026-09-24

### Changed

- Bump config pin to v0.1.15 (json v0.1.17) so cli -> config -> json converges with policy on a single json version (SONNY-2608 diamond fix).

### Fixed

- `Context.stdout`/`stderr` now append when redirected to a regular file; previously each write started at offset 0 and overwrote the previous one (SONNY-2608).

## [0.1.11] - 2026-09-12

### Changed

- Converge thread_pool v0.2.7, fips v0.1.1, protobuf v0.1.5, config v0.1.13 (GAP-0838 diamond sync).

## [0.1.10] - 2026-09-12

### Changed

- Converge thread_pool v0.2.7, fips v0.1.1, protobuf v0.1.5 (GAP-0838 diamond sync).

## [0.1.8] - 2026-06-12

Audit hardening release: 11 iterations of `/security:appsec-review` +
`/codepros:audit` run to convergence (dual-independent confirmation). Test
suite grew from 803 to 1129 unit tests; `zig build check` is clean for native
and `x86_64-windows`. Note: versions 0.1.5–0.1.7 were consumed by an unrelated
dependency-sync tagging line and skipped here.

### Changed (parser semantics, iteration 4)
- **Breaking:** a value-taking short flag in any non-final cluster position is now an error (`MissingValue`) instead of being silently dropped (e.g. `-ov file.txt` where `-o` takes a value)
- **Breaking:** bool flag values are strictly `true`/`false`; any other value (including `1`/`0`) is `InvalidValue` instead of silently false — applies to `--flag=value`, env-bound values, and `default_str`
- **Breaking:** subcommand resolution stops at the first positional (Cobra semantics): `prog svc myname start` now resolves to `svc` with positionals `["myname","start"]` instead of silently executing `start`
- Required flags and flag-group constraints are validated across the full resolved command chain, not just the leaf; positional rules remain leaf-only
- CLI values fully replace env-seeded repeatable (`string_array`) flag values; env-bound flag defaults run after argv for every command in the chain, so flags > env > default holds chain-wide
- Custom flag validators are enforced for environment values (recorded + skipped on rejection) and `default_str` (hard `InvalidValue`)
- Bool short flags enforce secret policy and custom validators, matching long-flag behavior; global flags accept `--name=true|false`; `MissingValue` errors name the offending flag
- Mid-chain commands now receive env defaults and `default_str` defaults; `InvalidValue` diagnostics name the env variable only when the error actually came from the environment
- `--help`/`--version` early exits return before env-bound flag defaults are applied: the returned context carries CLI-set flags only
- man pages show `(required)`, `(default: …)`, `(env: $…)`, `(deprecated)` on flags; markdown shows `**(deprecated)**`; JSON flag objects gain a `deprecated` field
- man and markdown generators strip terminal control bytes (NS-056 defense-in-depth)

### Fixed (iteration 4)
- PowerShell completion doubles single quotes inside regex case labels — apostrophes in subcommand names cannot break out of the single-quoted pattern (CWE-94)
- Markdown fence guard indents embedded ``` lines by 4 spaces (one space was bypassable: CommonMark closing fences may be indented up to 3 spaces)
- JSON help output is always valid RFC 8259 UTF-8 — invalid bytes are replaced with U+FFFD
- `.only_valid` argument errors, completion-script headers, and the bash `complete -F` registration target are control-filtered/escaped (iteration-2/3 findings N-01, N-03, N-04)

### Fixed (iteration 8)
- `parallel.initPool` clamps an explicit `worker_count` to the thread-pool maximum (64) instead of `@panic`-ing the whole process — a `--jobs N` above the cap, or `getCpuCount()` on >64-thread hardware, no longer aborts at startup; `pool_workers` records the clamped value so chunking math stays consistent (iter-8 finding 8-1)
- `parallel.forEach` runs the unsubmitted tail chunks inline when `submitBatch` partially enqueues under `.return_error` backpressure — previously the partial-success result was discarded, leaving the dropped chunks' result slots uninitialized and read as garbage (iter-8 finding 8-2)
- The pager ignores SIGPIPE (SIG_IGN, saved/restored) for the duration of the spawn/write/wait interaction so a pager that closes its read end early (user quits `less` with `q`) yields `EPIPE` → the existing direct-output fallback, instead of the default SIGPIPE disposition killing the process before the fallback can run; POSIX-only, no-op on Windows (iter-8 finding 8-3, refs #137)

### Fixed (iteration 9)
- `ProgressBar.render` clamps `current` to `total` before computing the bar fill, so a concurrent `increment()` advancing past `total` (its `fetchAdd` runs outside the render mutex) can no longer make `width - filled` underflow — previously a panic in safe builds and a near-infinite stderr write in ReleaseFast (CWE-191/CWE-362 reachable DoS via the thread-safe API; distinct from the closed init-time NS-058)
- Documented the mixed borrowed/owned return contract on `text.wordWrap`, `padRight`, `padLeft`, and `center` (they return a borrowed slice in the no-op case, like `truncate`): a caller using `defer free(result)` would otherwise free a non-heap pointer when the input already fits

### Fixed (iteration 10)
- Completion-script per-field escapers (bash/fish/zsh/powershell) now strip the full terminal-control-byte set — ESC (0x1B), BEL (0x07), every other C0 control, and DEL (0x7F) — instead of only NUL/newline/CR. Field metadata (`flag.help`, `gflag.help`, `subcmd.summary`, and completion **values**) could previously carry an embedded `\x1b]0;…\x07` OSC sequence straight into a generated completion script, executing against the terminal when a user inspects/`cat`s/pages the script before `eval` (CWE-150). Shell metacharacter escaping is unchanged — only control bytes are stripped; tab is preserved. The "No ESC byte may survive" invariant test now drives ESC/BEL/C0/DEL through field metadata (not just `cmd.name`), with equivalent field-metadata control-byte invariant tests added for bash, fish, and powershell

### Changed
- Invalid flag `default_str` values now return `ParseError.InvalidValue` instead of being silently skipped
- Windows `password()` returns `NotInteractive` when echo suppression is unavailable (GetConsoleMode/SetConsoleMode failure) instead of reading the password with echo enabled
- Pager falls back to direct output on spawn/exec/write failure instead of erroring
- Terminal control bytes are stripped from help, error, table, and progress output (CWE-150)
- Markdown generator escapes headings, prose, and fences contextually; table cells render embedded newlines as `<br>`
- Library version is single-sourced from `build.zig.zon` via build options; `root.version` can no longer drift from the package manifest (#106)
- Env-bound flag defaults (`FlagSpec.env`) are POSIX-only: on Windows the lookup now returns null instead of dereferencing a dangling stack slice — a documented limitation (#46)
- Large source files split to meet the 800-line guidance (help/parser/command/zsh/prompt/bench), now enforced by a pre-commit hook; `parse()` decomposed into a phase pipeline (#34, #46); the terminal sanitizer is a single first-class `sanitize` module (#140)

### Fixed
- Completion-script injection hardening: PowerShell `-CommandName` escaping, zsh identifier sanitization and quoted case labels, fish 16-level depth cap instead of out-of-bounds write (#132)
- Short-flag bytes are restricted to alphanumeric everywhere — the parser no longer matches a non-alphanumeric `short` (returns `UnknownFlag`), and help, bash/fish/zsh/powershell completions, and man/markdown all omit it — so a printable shell metacharacter (`"`, backtick, `;`, `$`, ...) can never be emitted raw into a shell or markup context. The `FlagSpec.short` contract is documented; parser, help, and generators now agree (CWE-78/CWE-94)
- JSON help escapes the short-flag character (#140)
- Truncation and table cell clipping never split multibyte UTF-8 sequences (#133)
- Table `min_width` is honored even when all cells are shorter; `max_width` is an absolute ceiling (#127)
- `ProgressBar.init` no longer underflows on terminals narrower than 20 columns (#129)
- `parallel.forEach` drains partially submitted batches before the sequential fallback, eliminating a data race; chunk count now scales with worker count (#125)
- Pager spawn migrated to the Zig 0.16 `std.process.spawn` API (the old path was a latent compile error hidden by lazy analysis) (#137)
- Parser resets diagnostic state between `parse()` calls and counts env parse errors beyond the 8-entry buffer (#39, #140)

### Added
- `prompt.freeSecret` helper that zeroes secret buffers before freeing
- `Context.getBoolOpt` — returns `?bool` so callers can distinguish an absent bool flag from an explicit `false` (#138)

### Documentation
- Backfilled changelog entries for releases 0.1.2, 0.1.3, and 0.1.4 (#135)

## [0.1.4] - 2026-05-02

Release alignment: re-pin sibling dependencies to their tagged releases
(config 0.1.4, thread-pool 0.2.4). No library code changes.

### Changed
- Dependency pins updated to tagged sibling releases

## [0.1.3] - 2026-05-02

Release alignment: re-pin sibling dependencies to their tagged releases.
No library code changes.

### Changed
- Dependency pins updated to tagged sibling releases

## [0.1.2] - 2026-05-02

Zig 0.16.0 migration and parallelism rework.

### Changed
- Migrated the codebase to Zig 0.16.0 (`std.io` → `std.Io`, `fs.File` → `Io.File`, removed-stdlib Windows wrappers replaced with direct externs; CI `ZIG_VERSION` bumped to 0.16.0)
- Replaced the `spice` parallelism dependency with `thread-pool`; parallel module is now conditional on the `thread-pool` build option
- `config` dependency consumed by URL so remote consumers can fetch it
- Transitive dependencies made optional to avoid diamond-dependency conflicts in parent builds
- Sibling dependency pins converged repeatedly to aligned HEADs
- Replaced `std.posix.getenv` with cross-platform alternatives for Windows support

### Added
- `parallel` module exported from the public root API
- Scale benchmark suite with baseline tracking and JSON output
- Diamond-dependency detector with pre-commit hook
- Parallel execution support for CLI operations (GAP-0089)

### Fixed
- ProgressBar made thread-safe (GAP-0086)
- Signal handler reworked to flag-and-poll pattern (GAP-0087)
- 72 audit gaps closed across security hardening, performance optimization, cross-platform fixes, quality, and documentation
- Gitleaks configuration: removed overly-broad private-key-file rule, allowlisted test path literals

### CI
- Linux jobs routed to company-tagged runners
- `.pre-commit-config.yaml` standardized from geode upstream

## [0.1.1] - 2026-03-25

Audit hardening release: security, performance, quality, and documentation fixes
identified by comprehensive gap analysis.

### Fixed
- Subcommand flags with `.env` set are now populated from environment variables (GAP-0090)
- Windows password prompt now properly suppresses echo via SetConsoleMode (NQ-052/NS-047)
- Windows terminal size detection uses safe i32 arithmetic instead of panicking intCast (NS-054)
- Windows `WINAPI` calling convention updated for Zig 0.15.2 compatibility
- Windows `GetModuleHandleW`/`GetStdHandle` null handle safety (cross-compile fix)

### Changed
- Help text and JSON help output are rendered into a memory buffer before writing, reducing syscall overhead (NP-019/NP-028)
- Roff escaping uses span-based flushing for fewer write calls (NP-021)
- Prompt input buffer is dynamically sized based on max_length config (NQ-056)
- Bash `sanitizeBashIdentifier` uses arena allocator instead of static mutable buffer (NQ-055/NS-052)
- Fish escape function strips NUL/newline/CR characters matching bash/zsh behavior (NS-048)
- Fish `buildCondition` escapes command names for single-quoted contexts (NS-051)
- PowerShell escape function strips NUL/newline/CR characters (NS-049)
- Markdown escaping now handles backticks, `<`, and `>` (NS-053)
- Pre-allocated capacity hints for escape functions and generators across all shells (NP-025)
- Context.init pre-allocates flags HashMap, positionals, and command_path (NP-020/NP-027)
- Man page and Markdown generators pre-allocate output buffers (NP-023/NP-024)
- wordWrap pre-allocates output buffer (NP-026)

### Removed
- Dead code: handleFlag, findFlagInChain, findFlagByShortInChain from parser.zig (GAP-0092)

### Security
- Cross-compilation CI job validates Windows and aarch64 code paths compile (GAP-0094)
- Parser getEnvVar handles Windows via FixedBufferAllocator pattern (GAP-0093)

### Documentation
- ARCHITECTURE.md Command struct updated to match actual field names (GAP-0085)
- SECURITY.md fuzz testing claim corrected (GAP-0086)
- ROADMAP.md v0.2.0 features moved to completed section (GAP-0087)
- Makefile Zig version updated to match build.zig.zon (GAP-0089)

### Added
- Signal module tests for Config validation, Windows atomic flags, and cleanup callbacks (NQ-058)
- Parser tests for subcommand env defaults and CLI priority over env (GAP-0090)
- Cross-compilation CI job for x86_64-windows and aarch64-linux (GAP-0094)

## [0.1.0] - 2026-01-24

Initial open source release under Apache-2.0 license.

### Added
- Merge request template
- Issue templates for bug reports, features, and questions

### Changed
- Removed 'zig' prefix from library name
- Updated README to use correct library name
- Updated config dependency to use GitLab archive URL

### Security
- Added GitLab native Secret Detection
- Enabled Advanced SAST and Dependency Scanning
- Updated CI catalog components to v1.7.1

### Features

#### CLI Features
- Nested command trees with subcommands and aliases
- Type-safe flag parsing (bool, int, float, string, path, string_array)
- Automatic help generation with examples-first approach
- Shell completion generation (bash, zsh, fish)
- Man page generation in roff format
- Error messages with typo suggestions using Levenshtein distance
- Signal handling (SIGINT, SIGTERM) with cleanup callbacks
- Pre/post-run hooks for command lifecycle management
- Default flag values applied when unspecified
- Custom help and usage templates (#19)
- Active help for dynamic shell completions (#20)
- Environment variable documentation in help output (#23)
- 12 Cobra parity features for comprehensive CLI building

#### Config Features
- Multiple format support (TOML, JSON, YAML) via config module
- XDG Base Directory compliance (~/.config, /etc)
- Strict precedence: flags > env > project > user > system > defaults
- Secret handling: file/stdin only, never flags/env
- Provenance tracking for debugging configuration sources
- Validation hooks
- Config loading integration tests (#6)

#### Terminal Features
- TTY detection and terminal size
- ANSI color with NO_COLOR/TERM=dumb compliance
- Pager integration (less) for long output
- Progress indicators (spinners, bars) - TTY-aware
- Interactive prompts (input, password, confirm, select, multi-select)

#### Documentation
- Getting Started guide
- Architecture overview and module structure
- API reference documentation (#8)
- Advanced usage guides (#9)
- Subcommands guide
- Config precedence guide
- Shell completions guide
- Cross-platform notes
- Testing guide

#### Cross-Platform Support
- Linux (x86_64, ARM64, ARM, RISC-V)
- macOS (ARM64/M1/M2, x86_64)
- Windows (x86_64, ARM64)

#### CI/CD
- GitLab CI/CD pipeline with DevNW CI Catalog components
- SAST and Secret Detection
- SBOM generation
- Coverage-guided fuzz testing via `zig build test --fuzz`

### Security
- Secrets must never be in flags or environment variables
- Automatic path redaction for sensitive files in error messages
- Strict secret handling with file/stdin-only input

[Unreleased]: https://gitlab.com/devnw/zig/cli/-/compare/v0.1.8...HEAD
[0.1.8]: https://gitlab.com/devnw/zig/cli/-/compare/v0.1.4...v0.1.8
[0.1.4]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.4
[0.1.3]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.3
[0.1.2]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.2
[0.1.1]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.0
