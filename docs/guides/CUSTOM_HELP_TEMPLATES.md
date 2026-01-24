# Custom Help Templates Guide

This guide explains how to customize help output using templates.

## Overview

The help system uses `HelpTemplate` to control:

- Section order (usage, examples, commands, flags, etc.)
- Section headers
- Formatting options (indentation, column widths)
- Whether to show global flags
- Custom footer text

## Default Template

The default template follows an "examples-first" approach:

```zig
const help = @import("cli").help;

// Default template (used automatically)
const template = help.HelpTemplate.default;
// Produces:
// myapp - My application description
//
// Usage: myapp [flags] <command> [args]
//
// Examples:
//   myapp start --port 8080
//   myapp stop --force
//
// Commands:
//   start    Start the server
//   stop     Stop the server
//
// Flags:
//   -h, --help     Print help information
//   -V, --version  Print version information
//   --config       Config file path [$MYAPP_CONFIG]
//
// For full help: myapp --help
```

## Built-in Presets

### Minimal

Shows only essential information:

```zig
const template = help.HelpTemplate.minimal;
// Produces:
// Usage: myapp [flags] <command> [args]
//
// Flags:
//   --config       Config file path
//   --verbose      Enable verbose output
```

### Verbose

All sections with uppercase headers:

```zig
const template = help.HelpTemplate.verbose;
// Produces:
// myapp - My application description
//
// USAGE: myapp [flags] <command> [args]
//
// My application provides comprehensive functionality
// for managing your infrastructure.
//
// EXAMPLES:
//   myapp start --port 8080
//   myapp stop --force
//
// COMMANDS:
//   start    Start the server
//   stop     Stop the server
//
// OPTIONS:
//   -h, --help     Print help information
//   ...
```

### Man Page Style

Sections ordered like Unix man pages:

```zig
const template = help.HelpTemplate.manpage;
// Produces:
// myapp - My application description
//
// SYNOPSIS: myapp [flags] <command> [args]
//
// DESCRIPTION:
// My application provides comprehensive functionality
// for managing your infrastructure.
//
// COMMANDS:
//   start    Start the server
//
// OPTIONS:
//   -h, --help     Print help information
//
// EXAMPLES:
//   myapp start --port 8080
```

## Custom Templates

### Basic Customization

```zig
const custom_template = help.HelpTemplate{
    // Change section order
    .sections = &.{
        .usage,
        .description,
        .commands,
        .flags,
        .examples,
    },

    // Custom headers
    .usage_header = "How to Use",
    .examples_header = "Examples",
    .commands_header = "Available Commands",
    .flags_header = "Options",
};
```

### Custom Footer

```zig
const template = help.HelpTemplate{
    .footer_text = "Report bugs to: https://github.com/myorg/myapp/issues",
};
```

### Disable Global Flags

```zig
const template = help.HelpTemplate{
    .show_global_flags = false,  // Don't show --help, --version, etc.
};
```

### Formatting Options

```zig
const template = help.HelpTemplate{
    .indent = 4,             // 4-space indentation (default: 2)
    .name_column_width = 25, // Width for flag/command names (default: 20)
};
```

## Using Templates

### In printHelp

```zig
const help = @import("cli").help;

fn showHelp(cmd: *const cli.Command, ctx: *cli.Context) void {
    help.printHelpWithTemplate(cmd, ctx, &custom_template);
}
```

### Per-Command Templates

Different commands can use different templates:

```zig
const root_cmd = cli.Command{
    .name = "myapp",
    .summary = "My application",
    .pre_run = struct {
        fn pre(ctx: *cli.Context) !void {
            // Override help for this command
            if (ctx.getBool("help")) {
                help.printHelpWithTemplate(&root_cmd, ctx, &custom_template);
                return error.HelpRequested;
            }
        }
    }.pre,
};
```

## Custom Section Renderer

For full control, use a custom renderer callback:

```zig
const template = help.HelpTemplate{
    .custom_renderer = renderSection,
};

fn renderSection(
    cmd: *const cli.Command,
    ctx: *cli.Context,
    section: help.HelpSection,
    template: *const help.HelpTemplate,
) bool {
    const w = ctx.stdout;

    switch (section) {
        .header => {
            // Custom header with ASCII art
            w.print(
                \\  __  __         _
                \\ |  \/  |_   _  / \   _ __  _ __
                \\ | |\/| | | | |/ _ \ | '_ \| '_ \
                \\ | |  | | |_| / ___ \| |_) | |_) |
                \\ |_|  |_|\__, /_/   \_\ .__/| .__/
                \\         |___/       |_|   |_|
                \\
            , .{}) catch return false;
            w.print("\n{s}\n", .{cmd.summary}) catch return false;
            return true; // We handled this section
        },

        .footer => {
            // Custom footer with links
            w.print(
                \\
                \\Documentation: https://myapp.dev/docs
                \\Report issues: https://github.com/myorg/myapp/issues
                \\
            , .{}) catch return false;
            return true;
        },

        else => return false, // Use default rendering
    }
}
```

## Environment-Based Templates

Choose template based on context:

```zig
fn getTemplate(ctx: *cli.Context) *const help.HelpTemplate {
    // Minimal for non-TTY (pipes)
    if (!cli.terminal.isTty(ctx.stdout)) {
        return &help.HelpTemplate.minimal;
    }

    // Verbose if requested
    if (ctx.getBool("verbose-help")) {
        return &help.HelpTemplate.verbose;
    }

    // Default
    return &help.HelpTemplate.default;
}

fn showHelp(cmd: *const cli.Command, ctx: *cli.Context) void {
    help.printHelpWithTemplate(cmd, ctx, getTemplate(ctx));
}
```

## Combining with Command Groups

Templates work with command groups:

```zig
const template = help.HelpTemplate{
    .commands_header = "Commands",  // Only used for ungrouped commands
};

// Groups get their own headers automatically:
// Development:
//   build    Build the project
//   test     Run tests
//
// Deployment:
//   deploy   Deploy to production
//   rollback Rollback deployment
```

## JSON Help

The template system also supports JSON output:

```zig
fn showHelp(cmd: *const cli.Command, ctx: *cli.Context) void {
    if (ctx.json) {
        // JSON output ignores template, uses standard format
        help.printHelp(cmd, ctx);
    } else {
        help.printHelpWithTemplate(cmd, ctx, &custom_template);
    }
}
```

## Best Practices

1. **Use presets when possible** - They're well-tested
2. **Keep examples first** - Users learn by example
3. **Include environment variables** - Show `[$ENV_VAR]` in flag help
4. **Use consistent headers** - Don't mix styles
5. **Test terminal width** - Ensure help wraps properly
6. **Support --json** - For programmatic access

## Complete Example

```zig
const std = @import("std");
const cli = @import("cli");
const help = cli.help;

// Custom template for a deployment tool
const deploy_template = help.HelpTemplate{
    .sections = &.{
        .header,
        .usage,
        .description,
        .examples,
        .commands,
        .flags,
        .footer,
    },

    .usage_header = "Synopsis",
    .examples_header = "Quick Start",
    .commands_header = "Available Commands",
    .flags_header = "Global Options",
    .description_header = "Description",

    .show_global_flags = true,
    .indent = 2,
    .name_column_width = 22,

    .footer_text =
        \\
        \\Environment:
        \\  DEPLOY_ENV     Target environment (dev, staging, prod)
        \\  DEPLOY_TOKEN   API authentication token
        \\
        \\Configuration:
        \\  ~/.config/deploy/config.yaml
        \\
        \\More info: https://deploy.example.com/docs
    ,

    .custom_renderer = struct {
        fn render(
            cmd: *const cli.Command,
            ctx: *cli.Context,
            section: help.HelpSection,
            _: *const help.HelpTemplate,
        ) bool {
            if (section == .header) {
                const use_color = ctx.useColor();
                const w = ctx.stdout;

                if (use_color) {
                    w.print("\x1b[1;36m{s}\x1b[0m", .{cmd.name}) catch return false;
                } else {
                    w.print("{s}", .{cmd.name}) catch return false;
                }
                w.print(" v{s} - {s}\n", .{
                    cmd.version,
                    cmd.summary,
                }) catch return false;
                return true;
            }
            return false;
        }
    }.render,
};

const root_cmd = cli.Command{
    .name = "deploy",
    .summary = "Deploy applications to cloud infrastructure",
    .version = "1.2.3",
    .long_help =
        \\Deploy is a command-line tool for deploying applications
        \\to various cloud providers with support for rolling updates,
        \\health checks, and automatic rollback.
    ,
    .examples = &.{
        "deploy push --env staging",
        "deploy rollback --revision HEAD~1",
        "deploy status --watch",
    },
    // ...
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var parser = cli.Parser.init(&root_cmd, gpa.allocator());
    const ctx = try parser.parse(std.os.argv);

    if (ctx.getBool("help")) {
        help.printHelpWithTemplate(&root_cmd, ctx, &deploy_template);
        return;
    }

    // Run command...
}
```
