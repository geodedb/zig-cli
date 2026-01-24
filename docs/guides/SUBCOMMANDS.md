# Subcommand Architecture Guide

This guide explains how to structure complex CLIs with nested subcommands.

## Basic Structure

```zig
const cli = @import("cli");

// Leaf commands (no subcommands)
const get_cmd = cli.Command{
    .name = "get",
    .summary = "Get a value by key",
    .flags = &.{
        cli.FlagSpec{
            .name = "key",
            .short = 'k',
            .help = "Key to retrieve",
            .ftype = .string,
            .required = true,
        },
    },
    .run = runGet,
};

const set_cmd = cli.Command{
    .name = "set",
    .summary = "Set a value by key",
    .run = runSet,
};

// Group command (has subcommands)
const kv_cmd = cli.Command{
    .name = "kv",
    .summary = "Key-value operations",
    .subcommands = &.{ &get_cmd, &set_cmd },
};

// Root command
const root_cmd = cli.Command{
    .name = "myapp",
    .summary = "My application",
    .subcommands = &.{ &kv_cmd },
    .flags = &.{
        // Global flags available to all subcommands
        cli.FlagSpec{
            .name = "verbose",
            .short = 'v',
            .help = "Enable verbose output",
            .ftype = .bool,
        },
    },
};
```

## Usage Patterns

```bash
myapp kv get --key foo
myapp kv set --key foo --value bar
myapp -v kv get --key foo  # Global flag before subcommand
```

## Flag Inheritance

Flags defined on parent commands are available to all subcommands:

```zig
fn runGet(ctx: *cli.Context) !void {
    // Access parent's verbose flag
    const verbose = ctx.getBool("verbose");

    // Access own key flag
    const key = ctx.getString("key").?;

    if (verbose) {
        try ctx.print("Getting key: {s}\n", .{key});
    }
}
```

## Lifecycle Hooks

Use `pre_run` and `post_run` for common setup/teardown:

```zig
const kv_cmd = cli.Command{
    .name = "kv",
    .summary = "Key-value operations",
    .subcommands = &.{ &get_cmd, &set_cmd },
    .pre_run = initDatabase,   // Called before any subcommand runs
    .post_run = closeDatabase, // Called after subcommand completes
};

fn initDatabase(ctx: *cli.Context) !void {
    // Open database connection
}

fn closeDatabase(ctx: *cli.Context) !void {
    // Close database connection
}
```

## Hidden Commands

Use `hidden = true` for internal/advanced commands:

```zig
const debug_cmd = cli.Command{
    .name = "debug",
    .summary = "Debug utilities",
    .hidden = true,  // Won't appear in help
};
```

## Command Aliases

```zig
const list_cmd = cli.Command{
    .name = "list",
    .summary = "List items",
    .aliases = &.{ "ls", "l" },  // myapp ls, myapp l
};
```

## Best Practices

1. **Group related commands** under a parent command
2. **Keep nesting shallow** (2-3 levels max)
3. **Use consistent flag names** across related commands
4. **Define global flags on root** for cross-cutting concerns
5. **Provide examples** for complex command combinations
