# Gap Analysis: zig-cli vs Cobra

This document provides a detailed analysis of feature gaps between zig-cli and [Cobra](https://github.com/spf13/cobra), the industry-standard Go CLI framework. Each gap is tracked as a GitLab issue for implementation.

## Executive Summary

zig-cli has achieved **full Cobra feature parity** for core CLI functionality. All 11 originally identified gaps have been closed except for package registry publishing (#12), which is planned for a future release.

| Priority | Total | Closed | Open |
|----------|-------|--------|------|
| High | 6 | 6 | 0 |
| Medium | 5 | 5 | 0 |
| Other | 1 | 0 | 1 |

## Remaining Gap

### Package Registry Publishing ([#12](https://gitlab.com/devnw/zig/cli/-/issues/12))

**What Cobra Has:**
Available via `go get github.com/spf13/cobra`.

**Current State:**
Manual installation via git URL required.

**Impact:**
Friction for new users; not discoverable in package searches.

**Plan:**
Register with Zig package registry when the API stabilises (planned for v0.2.0).

---

## Closed Gaps (Implemented)

| # | Feature | Issue | Status |
|---|---------|-------|--------|
| 1 | PowerShell completion generation | [#13](https://gitlab.com/devnw/zig/cli/-/issues/13) | Closed |
| 2 | Persistent hooks (PersistentPreRun/PostRun) | [#14](https://gitlab.com/devnw/zig/cli/-/issues/14) | Closed |
| 3 | Flag groups (mutually exclusive, required together, one required) | [#16](https://gitlab.com/devnw/zig/cli/-/issues/16) | Closed |
| 4 | Positional argument validators | [#17](https://gitlab.com/devnw/zig/cli/-/issues/17) | Closed |
| 5 | Flag value completion | [#22](https://gitlab.com/devnw/zig/cli/-/issues/22) | Closed |
| 6 | Command groups for organized help output | [#15](https://gitlab.com/devnw/zig/cli/-/issues/15) | Closed |
| 7 | Markdown documentation generation | [#18](https://gitlab.com/devnw/zig/cli/-/issues/18) | Closed |
| 8 | Custom help templates | [#19](https://gitlab.com/devnw/zig/cli/-/issues/19) | Closed |
| 9 | Active help (dynamic shell completion hints) | [#20](https://gitlab.com/devnw/zig/cli/-/issues/20) | Closed |
| 10 | Version command with build metadata | [#21](https://gitlab.com/devnw/zig/cli/-/issues/21) | Closed |
| 11 | Environment variables in help output | [#23](https://gitlab.com/devnw/zig/cli/-/issues/23) | Closed |

## Feature Comparison with Cobra

| Feature | zig-cli | Cobra |
|---------|---------|-------|
| Nested subcommands | Yes | Yes |
| Command aliases | Yes | Yes |
| Short/long flags | Yes | Yes |
| Required flags | Yes | Yes |
| Flag validators | Yes | Yes |
| String array flags | Yes | Yes |
| PreRun/PostRun hooks | Yes | Yes |
| PersistentPreRun/PostRun | Yes | Yes |
| Flag groups | Yes | Yes |
| Positional arg validators | Yes | Yes |
| Automatic help | Yes | Yes |
| Help with examples | Yes | Yes |
| Command groups in help | Yes | Yes |
| Custom help templates | Yes | Yes |
| Typo suggestions | Yes | Yes |
| Bash completion | Yes | Yes |
| Zsh completion | Yes | Yes |
| Fish completion | Yes | Yes |
| PowerShell completion | Yes | Yes |
| Flag value completion | Yes | Yes |
| Active help | Yes | Yes |
| Man page generation | Yes | Yes |
| Markdown doc generation | Yes | Yes |
| Config file support | Yes (via zig-config) | Yes (via Viper) |
| Environment variables | Yes | Yes |
| Env vars in help | Yes | Yes |

## Features Unique to zig-cli

zig-cli provides several features not found in Cobra:

| Feature | Description |
|---------|-------------|
| **Secret Handling Policy** | Flags can require values from file/stdin only, rejecting command-line input |
| **Progress Indicators** | Built-in spinners and progress bars with TTY awareness |
| **Interactive Prompts** | Input, password, confirm, select, multi-select prompts |
| **Table Output Formatter** | Structured table output with multiple border styles |
| **Pager Integration** | Automatic less pager for long output |
| **Path Redaction** | Sensitive paths auto-redacted in error messages |
| **Provenance Tracking** | Track exactly where each config value originated |
| **XDG Compliance** | Full XDG Base Directory support for config files |

## Contributing

To work on the remaining gap:

1. Comment on the issue to claim it
2. Read existing related code
3. Write tests first
4. Implement the feature
5. Update documentation
6. Submit merge request

See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed guidelines.
