# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Coverage support

### Security
- Secrets must never be in flags or environment variables
- Automatic path redaction for sensitive files in error messages
- Strict secret handling with file/stdin-only input

[Unreleased]: https://gitlab.com/devnw/zig/cli/-/compare/v0.1.0...HEAD
[0.1.0]: https://gitlab.com/devnw/zig/cli/-/releases/v0.1.0
