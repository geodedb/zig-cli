# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Audit hardening batch (2026-06 codepros audit iteration 1).

### Changed
- Invalid flag `default_str` values now return `ParseError.InvalidValue` instead of being silently skipped
- Windows `password()` returns `NotInteractive` when echo suppression is unavailable (GetConsoleMode/SetConsoleMode failure) instead of reading the password with echo enabled
- Pager falls back to direct output on spawn/exec/write failure instead of erroring
- Terminal control bytes are stripped from help, error, table, and progress output (CWE-150)
- Markdown generator escapes headings, prose, and fences contextually; table cells render embedded newlines as `<br>`
- Library version is single-sourced from `build.zig.zon` via build options; `root.version` can no longer drift from the package manifest (#106)

### Fixed
- Completion-script injection hardening: PowerShell `-CommandName` escaping, zsh identifier sanitization and quoted case labels, fish 16-level depth cap instead of out-of-bounds write (#132)
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

[Unreleased]: https://gitlab.com/devnw/zig/cli/-/compare/v0.1.4...HEAD
[0.1.4]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.4
[0.1.3]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.3
[0.1.2]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.2
[0.1.1]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.0
