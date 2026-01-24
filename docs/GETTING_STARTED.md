# Getting Started with zig-cli

A comprehensive CLI and configuration library for Zig.

## Installation

Add zig-cli to your `build.zig.zon`:

```zig
.dependencies = .{
    .cli = .{
        .url = "https://gitlab.com/devnw/zig/cli/-/archive/main/cli-main.tar.gz",
        // .hash = "...", // Add after first fetch
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
```

## Quick Start

### Basic Command

```zig
const std = @import("std");
const cli = @import("cli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const root = cli.Command{
        .name = "myapp",
        .summary = "My awesome CLI application",
        .flags = &.{
            cli.FlagSpec{
                .name = "verbose",
                .short = 'v',
                .help = "Enable verbose output",
                .ftype = .bool,
            },
            cli.FlagSpec{
                .name = "config",
                .short = 'c',
                .help = "Config file path",
                .ftype = .string,
            },
        },
        .callback = runMain,
    };

    var parser = cli.Parser.init(allocator, &root, "1.0.0", "My App");
    const result = try parser.parse(std.os.argv);
    defer result.context.deinit();

    if (result.command.callback) |cb| {
        try cb(&result.context);
    }
}

fn runMain(ctx: *cli.Context) !void {
    const verbose = ctx.getBool("verbose");
    const config_path = ctx.getString("config");

    if (verbose) {
        std.debug.print("Verbose mode enabled\n", .{});
    }
    if (config_path) |path| {
        std.debug.print("Using config: {s}\n", .{path});
    }
}
```

### Subcommands

```zig
const serve = cli.Command{
    .name = "serve",
    .summary = "Start the server",
    .flags = &.{
        cli.FlagSpec{
            .name = "port",
            .short = 'p',
            .help = "Port to listen on",
            .ftype = .int,
            .default = "8080",
        },
    },
    .callback = runServe,
};

const root = cli.Command{
    .name = "myapp",
    .summary = "My application",
    .subcommands = &.{&serve},
};
```

### Configuration Files

```zig
const config = @import("cli").config;

// Load config with automatic format detection
var value = try config.parseFile(allocator, "config.yaml");
defer value.deinit();

// Access values
const host = value.getString("server.host") orelse "localhost";
const port = value.getInt("server.port") orelse 8080;
```

## Features

- **Command Parsing**: Nested subcommands, flags, and positional arguments
- **Config Management**: YAML, TOML, JSON with XDG directory support
- **Shell Completions**: Generate completions for Bash, Zsh, Fish, PowerShell
- **Terminal Utilities**: Colors, progress indicators, terminal size detection
- **Help Generation**: Automatic help text, man pages, markdown

## Next Steps

- See [Architecture](ARCHITECTURE.md) for design overview
- See [Roadmap](ROADMAP.md) for planned features
- Check the [examples/](../examples/) directory for more examples
