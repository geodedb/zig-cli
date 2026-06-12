# Active Help Guide

This guide explains how to use active help for enhanced shell completions.

## Overview

Active help provides dynamic hints and messages during shell tab completion:

- Context-aware hints when completing commands
- Validation feedback during flag value completion
- Dynamic suggestions based on current state
- User-controllable via environment variable

## Basic Active Help

Add static hints to commands:

```zig
const cli = @import("cli");

const deploy_cmd = cli.Command{
    .name = "deploy",
    .summary = "Deploy application",
    .active_help = &.{
        "Tip: Use --dry-run to preview changes",
        "Note: Requires DEPLOY_TOKEN environment variable",
    },
};
```

When the user types `myapp deploy<TAB>`, they'll see:

```text
$ myapp deploy
Tip: Use --dry-run to preview changes
Note: Requires DEPLOY_TOKEN environment variable
```

## Dynamic Active Help

Use a function for context-aware hints:

```zig
const deploy_cmd = cli.Command{
    .name = "deploy",
    .summary = "Deploy application",
    .active_help_fn = getDeployHints,
};

fn getDeployHints(
    cmd: *const cli.Command,
    args: []const []const u8,
) []const []const u8 {
    // Check current state
    const has_env = std.posix.getenv("DEPLOY_TOKEN") != null;

    if (!has_env) {
        return &.{"Warning: DEPLOY_TOKEN not set - authentication will fail"};
    }

    // Check arguments already provided
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--env=prod")) {
            return &.{
                "Deploying to PRODUCTION - use --dry-run first",
                "Tip: Add --notify to alert the team",
            };
        }
    }

    return &.{}; // No hints
}
```

## Enabling/Disabling Active Help

Users can disable active help with environment variables:

```bash
# Disable active help for myapp
export MYAPP_ACTIVE_HELP=0

# Re-enable
unset MYAPP_ACTIVE_HELP
# or
export MYAPP_ACTIVE_HELP=1
```

The environment variable name is derived from the program name in uppercase.

## Shell Support

### Bash

Active help is shown as comments in completion output:

```bash
$ myapp deploy <TAB>
# Tip: Use --dry-run to preview changes
--dry-run    --env       --force
```

### Zsh

Active help integrates with zsh's description system:

```zsh
$ myapp deploy <TAB>
-- Tip: Use --dry-run to preview changes --
--dry-run  -- Preview deployment without changes
--env      -- Target environment
--force    -- Skip confirmation prompts
```

### Fish

Active help appears as a description:

```fish
$ myapp deploy <TAB>
--dry-run  (Preview deployment without changes)
--env      (Target environment)
# Tip: Use --dry-run to preview changes
```

### PowerShell

Active help shows in the completion tooltip.

## Use Cases

### Workflow Guidance

```zig
fn getGitHints(cmd: *const cli.Command, args: []const []const u8) []const []const u8 {
    // Check if in git repo
    const in_repo = std.fs.cwd().openDir(".git", .{}) catch null != null;

    if (!in_repo) {
        return &.{"Hint: Run 'git init' to create a repository"};
    }

    // Check for uncommitted changes
    // ...

    return &.{};
}
```

### Validation Feedback

```zig
fn getEnvHints(cmd: *const cli.Command, args: []const []const u8) []const []const u8 {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--env=")) {
            const env = arg[6..];
            if (!isValidEnv(env)) {
                return &.{
                    "Invalid environment. Valid: dev, staging, prod",
                };
            }
        }
    }
    return &.{};
}
```

### Permission Warnings

```zig
fn getAdminHints(cmd: *const cli.Command, args: []const []const u8) []const []const u8 {
    // Check if running as admin
    const uid = std.os.linux.getuid();

    if (uid != 0) {
        for (cmd.flags) |flag| {
            if (flag.requires_admin) {
                return &.{"Note: Some options require root privileges"};
            }
        }
    }

    return &.{};
}
```

### Rate Limit Warnings

```zig
fn getApiHints(cmd: *const cli.Command, args: []const []const u8) []const []const u8 {
    // Check rate limit status from cache
    const remaining = getRateLimitRemaining();

    if (remaining < 10) {
        return &.{
            "Warning: API rate limit nearly exhausted",
            try std.fmt.allocPrint(allocator, "{d} requests remaining", .{remaining}),
        };
    }

    return &.{};
}
```

## Generating Completion Scripts

Active help is automatically included when generating completions:

```zig
const completion = @import("cli").completion;

pub fn generateCompletionCmd(ctx: *cli.Context) !void {
    const shell = ctx.getString("shell").?;

    // Generate with active help support
    const script = try completion.generate(
        shell,
        &root_cmd,
        ctx.allocator,
        .{ .active_help = true },  // Enable active help
    );
    defer ctx.allocator.free(script);

    try ctx.stdout.writeAll(script);
}
```

## Best Practices

1. **Keep hints concise** - One line, actionable information
2. **Don't overuse** - Only show when helpful
3. **Make hints contextual** - Based on current arguments
4. **Respect user preference** - Honor the disable environment variable
5. **Avoid blocking operations** - Hints should be fast to compute
6. **Use sparingly in production** - Experienced users may find hints distracting

## Complete Example

```zig
const std = @import("std");
const cli = @import("cli");

const root_cmd = cli.Command{
    .name = "myapp",
    .summary = "My Application",
    .subcommands = &.{
        &deploy_cmd,
        &config_cmd,
    },
};

const deploy_cmd = cli.Command{
    .name = "deploy",
    .summary = "Deploy application",
    .active_help_fn = getDeployHints,
    .flags = &.{
        cli.FlagSpec{
            .name = "env",
            .short = 'e',
            .help = "Target environment",
            .ftype = .string,
            .completions = &.{ "dev", "staging", "prod" },
        },
        cli.FlagSpec{
            .name = "dry-run",
            .short = 'n',
            .help = "Preview without deploying",
            .ftype = .bool,
        },
        cli.FlagSpec{
            .name = "force",
            .short = 'f',
            .help = "Skip confirmation",
            .ftype = .bool,
        },
    },
};

fn getDeployHints(
    cmd: *const cli.Command,
    args: []const []const u8,
) []const []const u8 {
    var hints: [4][]const u8 = undefined;
    var count: usize = 0;

    // Check authentication
    if (std.posix.getenv("DEPLOY_TOKEN") == null) {
        hints[count] = "Warning: DEPLOY_TOKEN not set";
        count += 1;
    }

    // Check for production deployment
    var is_prod = false;
    var has_dry_run = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--env=prod") or std.mem.eql(u8, arg, "-e=prod")) {
            is_prod = true;
        }
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            has_dry_run = true;
        }
    }

    if (is_prod and !has_dry_run) {
        hints[count] = "Tip: Use --dry-run before deploying to production";
        count += 1;
    }

    if (is_prod) {
        hints[count] = "Note: Production deployments require approval";
        count += 1;
    }

    return hints[0..count];
}

const config_cmd = cli.Command{
    .name = "config",
    .summary = "Manage configuration",
    .active_help = &.{
        "Config files: ~/.config/myapp/config.yaml",
        "Override with --config flag or MYAPP_CONFIG env var",
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Handle completion subcommand
    if (args.len > 2 and std.mem.eql(u8, args[1], "completion")) {
        const shell = args[2];
        const script = try cli.completion.generate(
            shell,
            &root_cmd,
            allocator,
            .{ .active_help = true },
        );
        defer allocator.free(script);
        std.io.getStdOut().writeAll(script) catch {};
        return;
    }

    // Normal execution
    const exit_code = try cli.run(&root_cmd, args, allocator);
    std.process.exit(exit_code);
}
```
