# cli

A comprehensive command-line interface and configuration library for Zig, providing Cobra/Viper-class features for building production-quality CLI applications.

## Status

| Aspect | Info |
|--------|------|
| API Stability | Beta |
| Zig Version | 0.15.2+ |
| Platforms | Linux, macOS, Windows |

## Features

### CLI Features

- **Nested command trees** with subcommands and aliases
- **Type-safe flag parsing** (bool, int, float, string, path, string_array)
- **Automatic help generation** with examples-first approach
- **Shell completion generation** (bash, zsh, fish, PowerShell)
- **Man page generation** in roff format
- **Typo-suggestion helpers** (Levenshtein distance) for building "did you mean" error messages
- **Signal handling** (SIGINT, SIGTERM) with cleanup callbacks
- **Pre/post-run hooks** for command lifecycle management
- **Default flag values** applied when unspecified

### Config Features

- **Multiple format support** (TOML, JSON, YAML) via config
- **XDG Base Directory compliance** (~/.config, /etc)
- **Strict precedence**: flags > env > project > user > system > defaults
- **Secret handling**: file/stdin only, never flags/env
- **Provenance tracking** for debugging configuration sources
- **Validation hooks**

### Terminal Features

- **TTY detection** and terminal size
- **ANSI color** with NO_COLOR/TERM=dumb compliance
- **Pager integration** (less) for long output
- **Progress indicators** (spinners, bars) - TTY-aware
- **Interactive prompts** (input, password, confirm, select, multi-select)

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .cli = .{
        .url = "https://gitlab.com/devnw/zig/cli/-/archive/main/cli-main.tar.gz",
        .hash = "...", // Run `zig fetch` to get the hash
    },
},
```

Then in your `build.zig`:

```zig
const cli_dep = b.dependency("cli", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("cli", cli_dep.module("cli"));
exe.root_module.addImport("config", cli_dep.module("config"));
```

## Quick Start

```zig
const std = @import("std");
const cli = @import("cli");

const root_cmd = cli.Command{
    .name = "myapp",
    .summary = "My application",
    .examples = &.{
        "myapp serve --port=8080",
        "myapp config show",
    },
    .flags = &.{
        cli.FlagSpec{
            .name = "verbose",
            .short = 'v',
            .help = "Enable verbose output",
            .ftype = .bool,
        },
    },
    .run = myRun,
};

fn myRun(ctx: *cli.Context) !void {
    if (ctx.getBool("verbose")) {
        try ctx.print("Verbose mode enabled\n", .{});
    }
    try ctx.print("Hello, World!\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const exit_code = try cli.run(&root_cmd, args, gpa.allocator());
    std.process.exit(exit_code);
}
```

## Configuration Loading

```zig
const config = @import("config");

const AppConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    debug: bool = false,
};

// Loads from (in order): flags > env > project (./) > user (~/.config) > system (/etc)
const cfg = try config.load(AppConfig, .{
    .app_name = "myapp",
    .filename = "config.toml",
    .env_prefix = "MYAPP_",
});
```

## Configuration Precedence

```text
+--------+  highest priority
| Flags  |  --port=7000
+--------+
    |
+--------+
|  Env   |  MYAPP_PORT=8000
+--------+
    |
+--------+
|Project |  ./config.toml, ./.env
+--------+
    |
+--------+
| User   |  ~/.config/myapp/config.toml
+--------+
    |
+--------+
| System |  /etc/myapp/config.toml
+--------+
    |
+--------+  lowest priority
|Default |  struct field defaults
+--------+
```

## Testing

```bash
# Unit tests
zig build test

# Integration tests
zig build test-integration
```

## Security Notes

### Secrets Must Never Be in Flags or Environment Variables

```zig
// WRONG: This will be rejected
myapp --token=secret123

// CORRECT: Use file
myapp --token-file=/path/to/token

// CORRECT: Pipe via stdin
cat token.txt | myapp login
```

Configure secret flags:

```zig
cli.FlagSpec{
    .name = "token",
    .help = "Auth token (use --token-file instead)",
    .ftype = .string,
    .secret = .from_file_or_stdin,  // Rejects --token=...
},
cli.FlagSpec{
    .name = "token-file",
    .help = "Path to file containing token",
    .ftype = .path,
},
```

### Error Message Redaction

Paths to sensitive files are automatically redacted in error messages:

- `/etc/shadow`, `/etc/passwd`
- `.ssh/`, `.gnupg/`, `.aws/`
- Files named `credentials`, `secrets`, `.env`

## Color and TTY Behavior

| Condition | Color Output |
|-----------|--------------|
| Not a TTY | Disabled |
| `--no-color` flag | Disabled |
| `NO_COLOR` env set | Disabled |
| `TERM=dumb` | Disabled |
| Otherwise | Enabled |

Progress indicators and animations are automatically disabled when not a TTY.

## Generating Completions

```bash
# Bash
myapp completion --shell bash > /etc/bash_completion.d/myapp

# Zsh
myapp completion --shell zsh > ~/.zsh/completions/_myapp

# Fish
myapp completion --shell fish > ~/.config/fish/completions/myapp.fish

# PowerShell
myapp completion --shell powershell > myapp.ps1
```

## Generating Man Pages

```bash
myapp man > /usr/local/share/man/man1/myapp.1
```

## Output Modes

| Flag | Description |
|------|-------------|
| `--json` | Machine-readable JSON output |
| `--plain` | Plain text, one record per line |
| `-q, --quiet` | Suppress non-essential output |
| `--no-color` | Disable ANSI color codes |
| `-n, --dry-run` | Show what would happen |

## Building

```bash
# Build
zig build

# Run tests
zig build test

# Run demo
zig build run -- --help

# Build with optimizations
zig build -Doptimize=ReleaseSafe
```

## Cross-Platform Support

| Platform | Architecture | Status |
|----------|-------------|--------|
| Linux | x86_64 | Native |
| Linux | ARM64 | Native |
| Linux | ARM | Cross-compile |
| Linux | RISC-V | Cross-compile |
| macOS | ARM64 (M1/M2) | Native |
| macOS | x86_64 | Cross-compile |
| Windows | x86_64 | Native |
| Windows | ARM64 | Cross-compile |

## Documentation

- [Getting Started](docs/GETTING_STARTED.md) - Quick start guide
- [Architecture](docs/ARCHITECTURE.md) - Design overview and module structure
- [API Reference](docs/API.md) - Public API documentation
- [Roadmap](docs/ROADMAP.md) - Planned features and Cobra comparison

### Guides

- [Subcommands](docs/guides/SUBCOMMANDS.md) - Nested command structures
- [Config Precedence](docs/guides/CONFIG_PRECEDENCE.md) - Configuration loading order
- [Shell Completions](docs/guides/SHELL_COMPLETIONS.md) - Completion script generation
- [Cross-Platform](docs/guides/CROSS_PLATFORM.md) - Platform-specific notes
- [Testing](docs/guides/TESTING.md) - Testing guide

## Project Status

This library is under active development. See the [Roadmap](docs/ROADMAP.md) for a complete Cobra feature comparison.

### Planned

| Issue | Description |
|-------|-------------|
| [#12](https://gitlab.com/devnw/zig/cli/-/issues/12) | Publish to Zig package registry |

### Recently Completed

- PowerShell completion generation ([#13](https://gitlab.com/devnw/zig/cli/-/issues/13))
- Persistent hooks (PersistentPreRun/PostRun) ([#14](https://gitlab.com/devnw/zig/cli/-/issues/14))
- Flag groups (mutually exclusive/required together) ([#16](https://gitlab.com/devnw/zig/cli/-/issues/16))
- Positional argument validators ([#17](https://gitlab.com/devnw/zig/cli/-/issues/17))
- Flag value completion support ([#22](https://gitlab.com/devnw/zig/cli/-/issues/22))
- String array flag parsing ([#1](https://gitlab.com/devnw/zig/cli/-/issues/1))
- Signal handling ([#3](https://gitlab.com/devnw/zig/cli/-/issues/3))
- Interactive prompts ([#7](https://gitlab.com/devnw/zig/cli/-/issues/7))
- Progress indicators ([#10](https://gitlab.com/devnw/zig/cli/-/issues/10))

## Design Rationale

1. **Human-first defaults** - Help, examples, and concise messaging + composability (stdout/JSON/--plain)
2. **Strict precedence & XDG compliance** - Predictable configuration behavior
3. **Safety by default** - Explicit aliases only, confirmations for destructive ops, no secrets in flags/env
4. **Clear separation of concerns** - cli/, config/, term/, util/
5. **Deterministic builds** - Pinned Zig version, no vendored dependencies, no network at build time
6. **TTY-aware UX** - Progress/pager/color only when appropriate
7. **Machine-readable output** - `--json` for tooling integration

## Requirements

- Zig 0.15.2 or compatible

## License

Apache-2.0 License - see [LICENSE](LICENSE)
