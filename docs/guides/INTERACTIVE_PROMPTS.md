# Interactive Prompts Guide

This guide explains how to use interactive prompts for user input.

## Overview

The CLI library provides several prompt types for gathering user input:

- **Input**: Basic text input
- **Password**: Hidden text input for secrets
- **Confirm**: Yes/No confirmation
- **Select**: Single selection from options
- **Multi-select**: Multiple selections from options

## Basic Input Prompt

```zig
const prompts = @import("cli").prompts;

pub fn askName(ctx: *cli.Context) !void {
    const name = try prompts.input(ctx.allocator, .{
        .message = "What is your name?",
        .default = "Anonymous",
    });
    defer ctx.allocator.free(name);

    try ctx.stdout.print("Hello, {s}!\n", .{name});
}
```

## Password Input

For sensitive data like passwords or API keys:

```zig
pub fn askPassword(ctx: *cli.Context) !void {
    const password = try prompts.password(ctx.allocator, .{
        .message = "Enter your password:",
        .mask = '*',  // Character shown while typing
    });
    defer ctx.allocator.free(password);

    // Use password securely...
}
```

## Confirmation Prompt

For yes/no questions:

```zig
pub fn confirmDelete(ctx: *cli.Context) !void {
    const confirmed = try prompts.confirm(.{
        .message = "Are you sure you want to delete all files?",
        .default = false,  // Default to "No"
    });

    if (confirmed) {
        // Proceed with deletion
    } else {
        try ctx.stdout.print("Operation cancelled.\n", .{});
    }
}
```

## Select Prompt

For choosing a single option from a list:

```zig
pub fn selectEnvironment(ctx: *cli.Context) !void {
    const options = &[_]prompts.SelectOption{
        .{ .label = "Development", .value = "dev" },
        .{ .label = "Staging", .value = "staging" },
        .{ .label = "Production", .value = "prod" },
    };

    const selected = try prompts.select(options, .{
        .message = "Select deployment environment:",
        .default = 0,  // Default to first option
    });

    try ctx.stdout.print("Selected: {s}\n", .{selected.value});
}
```

## Multi-Select Prompt

For choosing multiple options:

```zig
pub fn selectFeatures(ctx: *cli.Context) !void {
    const options = &[_]prompts.SelectOption{
        .{ .label = "Logging", .value = "logging" },
        .{ .label = "Metrics", .value = "metrics" },
        .{ .label = "Tracing", .value = "tracing" },
        .{ .label = "Profiling", .value = "profiling" },
    };

    const selected = try prompts.multiSelect(ctx.allocator, options, .{
        .message = "Select features to enable:",
        .min_selections = 1,  // At least one required
    });
    defer ctx.allocator.free(selected);

    for (selected) |feature| {
        try ctx.stdout.print("Enabling: {s}\n", .{feature.value});
    }
}
```

## Non-Interactive Mode

When running in scripts or CI environments, disable prompts:

```zig
// Check if running interactively
if (ctx.no_input) {
    // Use defaults or fail gracefully
    return error.NonInteractiveMode;
}

// Safe to prompt
const answer = try prompts.input(ctx.allocator, .{
    .message = "Enter value:",
});
```

The `--no-input` flag automatically disables all prompts.

## TTY Detection

Prompts automatically detect if stdin/stdout is a TTY:

```zig
const term = @import("cli").terminal;

if (!term.isTty(std.io.getStdIn())) {
    // Not running in a terminal
    // Provide non-interactive fallback
}
```

## Customizing Appearance

```zig
const answer = try prompts.input(ctx.allocator, .{
    .message = "Project name:",
    .default = "my-project",
    .prefix = "> ",           // Prompt prefix
    .placeholder = "name",    // Hint text
});
```

## Error Handling

```zig
const result = prompts.input(ctx.allocator, .{
    .message = "Enter value:",
}) catch |err| switch (err) {
    error.Cancelled => {
        // User pressed Ctrl+C
        try ctx.stdout.print("Cancelled.\n", .{});
        return;
    },
    error.EndOfStream => {
        // EOF received (piped input ended)
        return error.NoInput;
    },
    else => return err,
};
```

## Validation

Add custom validation to prompts:

```zig
const email = try prompts.input(ctx.allocator, .{
    .message = "Enter email:",
    .validate = struct {
        fn validate(value: []const u8) ?[]const u8 {
            if (std.mem.indexOf(u8, value, "@") == null) {
                return "Invalid email address";
            }
            return null;  // Valid
        }
    }.validate,
});
```

## Best Practices

1. **Always provide defaults** when reasonable
2. **Use `--no-input` flag** for CI/script compatibility
3. **Handle Ctrl+C gracefully** with error.Cancelled
4. **Validate input** before proceeding
5. **Clear sensitive data** after use
6. **Test with piped input** to ensure non-TTY behavior

## Complete Example

```zig
const std = @import("std");
const cli = @import("cli");
const prompts = cli.prompts;

fn setupProject(ctx: *cli.Context) !void {
    // Check if interactive
    if (ctx.no_input) {
        try ctx.err("This command requires interactive mode\n", .{});
        return error.NonInteractive;
    }

    // Gather project info
    const name = try prompts.input(ctx.allocator, .{
        .message = "Project name:",
        .default = "my-project",
    });
    defer ctx.allocator.free(name);

    const template = try prompts.select(&.{
        .{ .label = "Library", .value = "lib" },
        .{ .label = "Application", .value = "app" },
        .{ .label = "Both", .value = "both" },
    }, .{
        .message = "Project type:",
    });

    const features = try prompts.multiSelect(ctx.allocator, &.{
        .{ .label = "Testing framework", .value = "test" },
        .{ .label = "Documentation", .value = "docs" },
        .{ .label = "CI configuration", .value = "ci" },
    }, .{
        .message = "Additional features:",
    });
    defer ctx.allocator.free(features);

    const confirmed = try prompts.confirm(.{
        .message = try std.fmt.allocPrint(
            ctx.allocator,
            "Create project '{s}'?",
            .{name}
        ),
        .default = true,
    });

    if (!confirmed) {
        try ctx.stdout.print("Aborted.\n", .{});
        return;
    }

    // Create project...
    try ctx.stdout.print("Creating {s}...\n", .{name});
}
```
