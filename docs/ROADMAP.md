# Roadmap

This document tracks planned features and improvements for zig-cli, with reference to [Cobra](https://github.com/spf13/cobra) as the feature baseline for a production-quality CLI framework.

## Current Status

The library provides comprehensive CLI functionality with near-complete Cobra feature parity:
- Command and subcommand parsing with aliases
- Flag parsing (bool, string, int, float, path, string_array)
- **Flag groups** (mutually exclusive, required together, one required)
- **Positional argument validators** (exact, minimum, maximum, range, only_valid)
- **Persistent hooks** (PersistentPreRun/PersistentPostRun)
- Configuration file loading (YAML, TOML, JSON) with XDG compliance
- Shell completion generation (bash, zsh, fish, **PowerShell**)
- **Flag value completions** in shell scripts
- Man page generation
- **Markdown documentation generation**
- Help text generation with examples-first approach and **custom templates**
- **Command groups** for organized help output
- **Table output formatter** for structured data display
- **Version command support** with build metadata
- Terminal utilities (colors, progress indicators, TTY detection, **Windows support**)
- Signal handling (SIGINT, SIGTERM)
- Interactive prompts (input, password, confirm, select, multi-select)
- Error messages with typo suggestions

## Recently Completed

| Issue | Description | Status |
|-------|-------------|--------|
| [#1](https://gitlab.com/devnw/zig/cli/-/issues/1) | String array flag parsing | ✅ Closed |
| [#2](https://gitlab.com/devnw/zig/cli/-/issues/2) | Complete Windows terminal size detection | ✅ Closed |
| [#3](https://gitlab.com/devnw/zig/cli/-/issues/3) | Signal handling (SIGINT, SIGTERM) | ✅ Closed |
| [#4](https://gitlab.com/devnw/zig/cli/-/issues/4) | Shell completion tests | ✅ Closed |
| [#5](https://gitlab.com/devnw/zig/cli/-/issues/5) | Help format tests | ✅ Closed |
| [#7](https://gitlab.com/devnw/zig/cli/-/issues/7) | Interactive prompts | ✅ Closed |
| [#10](https://gitlab.com/devnw/zig/cli/-/issues/10) | Progress bar and spinner utilities | ✅ Closed |
| [#11](https://gitlab.com/devnw/zig/cli/-/issues/11) | Table output formatter | ✅ Closed |
| [#13](https://gitlab.com/devnw/zig/cli/-/issues/13) | PowerShell completion script generation | ✅ Closed |
| [#14](https://gitlab.com/devnw/zig/cli/-/issues/14) | Persistent hooks (PersistentPreRun/PersistentPostRun) | ✅ Closed |
| [#15](https://gitlab.com/devnw/zig/cli/-/issues/15) | Command groups for organized help output | ✅ Closed |
| [#16](https://gitlab.com/devnw/zig/cli/-/issues/16) | Flag groups (mutually exclusive, required together) | ✅ Closed |
| [#17](https://gitlab.com/devnw/zig/cli/-/issues/17) | Positional argument validators | ✅ Closed |
| [#18](https://gitlab.com/devnw/zig/cli/-/issues/18) | Markdown documentation generation | ✅ Closed |
| [#21](https://gitlab.com/devnw/zig/cli/-/issues/21) | Version command with build metadata | ✅ Closed |
| [#22](https://gitlab.com/devnw/zig/cli/-/issues/22) | Flag value completion support | ✅ Closed |
| [#23](https://gitlab.com/devnw/zig/cli/-/issues/23) | Environment variable documentation in help | ✅ Closed |
| [#6](https://gitlab.com/devnw/zig/cli/-/issues/6) | Config loading integration tests | ✅ Closed |
| [#20](https://gitlab.com/devnw/zig/cli/-/issues/20) | Active help for dynamic shell completions | ✅ Closed |
| [#19](https://gitlab.com/devnw/zig/cli/-/issues/19) | Custom help and usage templates | ✅ Closed |
| [#9](https://gitlab.com/devnw/zig/cli/-/issues/9) | Advanced usage guides | ✅ Closed |
| [#8](https://gitlab.com/devnw/zig/cli/-/issues/8) | API documentation | ✅ Closed |

## Planned Features

### High Priority

| Issue | Description | Status |
|-------|-------------|--------|
| [#12](https://gitlab.com/devnw/zig/cli/-/issues/12) | Publish to Zig package registry | Open |

## Feature Comparison with Cobra

| Feature | zig-cli | Cobra |
|---------|---------|-------|
| Nested subcommands | ✅ | ✅ |
| Command aliases | ✅ | ✅ |
| Short/long flags | ✅ | ✅ |
| Required flags | ✅ | ✅ |
| Flag validators | ✅ | ✅ |
| String array flags | ✅ | ✅ |
| PreRun/PostRun hooks | ✅ | ✅ |
| PersistentPreRun/PostRun | ✅ | ✅ |
| Flag groups | ✅ | ✅ |
| Positional arg validators | ✅ | ✅ |
| Automatic help | ✅ | ✅ |
| Help with examples | ✅ | ✅ |
| **Command groups in help** | ✅ | ✅ |
| **Custom help templates** | ✅ | ✅ |
| Typo suggestions | ✅ | ✅ |
| Bash completion | ✅ | ✅ |
| Zsh completion | ✅ | ✅ |
| Fish completion | ✅ | ✅ |
| PowerShell completion | ✅ | ✅ |
| Flag value completion | ✅ | ✅ |
| **Active help** | ✅ | ✅ |
| Man page generation | ✅ | ✅ |
| **Markdown doc generation** | ✅ | ✅ |
| Config file support | ✅ (via zig-config) | ✅ (via Viper) |
| Environment variables | ✅ | ✅ |
| **Env vars in help** | ✅ | ✅ |

### Unique to zig-cli

Features zig-cli provides that Cobra doesn't:

| Feature | Description |
|---------|-------------|
| Secret handling policy | Flags can require values from file/stdin only |
| Progress indicators | Built-in spinners and progress bars |
| Interactive prompts | Input, password, confirm, select, multi-select |
| Table output formatter | Structured table output with multiple styles |
| Pager integration | Automatic less pager for long output |
| Path redaction | Sensitive paths redacted in error messages |
| XDG compliance | Full XDG Base Directory support |
| Provenance tracking | Track where each config value came from |

## Contributing

Contributions are welcome! Please:

1. Check the [issue tracker](https://gitlab.com/devnw/zig/cli/-/issues) for open tasks
2. Comment on an issue to indicate you're working on it
3. Follow the existing code style
4. Add tests for new functionality
5. Update documentation as needed

## Version History

### v0.2.0 (Unreleased)
- Zig package registry publishing (#12)

### v0.1.1
- Audit hardening: security, performance, quality, and documentation fixes
- Cross-compilation CI for Windows and aarch64-linux
- Subcommand environment variable defaults
- Windows echo suppression for password prompts

### v0.1.0
- Command groups for organized help output
- Markdown documentation generation
- Table output formatter with multiple border styles
- Version command support with build metadata
- Windows terminal size detection
- Comprehensive shell completion tests
- Help format tests
- Full Cobra feature parity for core CLI functionality
- PowerShell completion support
- Persistent hooks (PersistentPreRun/PersistentPostRun)
- Flag groups (mutually exclusive, required together, one required)
- Positional argument validators
- Flag value completion in all shells

### v0.0.0 (Initial)
- Initial development release
- Core command parsing
- Configuration file support via zig-config
- Shell completions (bash, zsh, fish)
- Terminal utilities
- Signal handling
- Interactive prompts
- Progress indicators
