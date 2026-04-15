// SPDX-License-Identifier: MIT
// Copyright (c) 2024 DevNW

//! # Demo CLI Application
//!
//! Example application demonstrating zig-cli features:
//! - Nested subcommands (kv get, kv set, serve)
//! - Flag parsing with types
//! - Configuration loading with precedence
//! - Help generation
//! - Shell completions

const std = @import("std");
const cli = @import("cli");
const config = @import("config");

// ============================================================================
// Configuration
// ============================================================================

const AppConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    debug: bool = false,
    log_level: []const u8 = "info",
};

// ============================================================================
// Commands
// ============================================================================

// Root command
const root_cmd = cli.Command{
    .name = "demo",
    .summary = "example CLI application demonstrating zig-cli features",
    .long_help =
    \\demo is an example CLI application that demonstrates the features
    \\of the zig-cli library, including nested subcommands, configuration
    \\loading, and shell completions.
    ,
    .examples = &.{
        "demo kv get KEY",
        "demo kv set KEY --value=VAL",
        "demo serve --port=9000",
        "demo completion --shell zsh > _demo",
    },
    .flags = &.{
        cli.FlagSpec{
            .name = "config",
            .short = 'c',
            .help = "Path to configuration file",
            .ftype = .path,
            .env = "DEMO_CONFIG",
        },
        cli.FlagSpec{
            .name = "verbose",
            .short = 'v',
            .help = "Enable verbose output",
            .ftype = .bool,
        },
    },
    .subcommands = &.{
        &kv_cmd,
        &serve_cmd,
        &completion_cmd,
        &man_cmd,
        &config_cmd,
        &login_cmd,
        &ps_cmd,
    },
};

// KV command group
const kv_cmd = cli.Command{
    .name = "kv",
    .summary = "key-value store operations",
    .examples = &.{
        "demo kv get mykey",
        "demo kv set mykey --value=\"hello world\"",
        "demo kv list",
    },
    .subcommands = &.{
        &kv_get_cmd,
        &kv_set_cmd,
        &kv_list_cmd,
    },
};

const kv_get_cmd = cli.Command{
    .name = "get",
    .summary = "get a value by key",
    .run = kvGetRun,
};

const kv_set_cmd = cli.Command{
    .name = "set",
    .summary = "set a key-value pair",
    .flags = &.{
        cli.FlagSpec{
            .name = "value",
            .help = "Value to set",
            .ftype = .string,
            .required = true,
        },
    },
    .run = kvSetRun,
};

const kv_list_cmd = cli.Command{
    .name = "list",
    .summary = "list all keys",
    .run = kvListRun,
};

// Serve command
const serve_cmd = cli.Command{
    .name = "serve",
    .summary = "start the server",
    .aliases = &.{"s"},
    .flags = &.{
        cli.FlagSpec{
            .name = "port",
            .short = 'p',
            .help = "Port to listen on",
            .ftype = .int,
            .default_str = "8080",
            .env = "DEMO_PORT",
        },
        cli.FlagSpec{
            .name = "host",
            .help = "Host to bind to",
            .ftype = .string,
            .default_str = "localhost",
            .env = "DEMO_HOST",
        },
    },
    .run = serveRun,
};

// Completion command
const completion_cmd = cli.Command{
    .name = "completion",
    .summary = "generate shell completion script",
    .flags = &.{
        cli.FlagSpec{
            .name = "shell",
            .short = 's',
            .help = "Shell type (bash, zsh, fish)",
            .ftype = .string,
            .required = true,
        },
    },
    .run = completionRun,
};

// Man page command
const man_cmd = cli.Command{
    .name = "man",
    .summary = "generate man page",
    .run = manRun,
};

// Config command (for debugging)
const config_cmd = cli.Command{
    .name = "config",
    .summary = "show configuration with provenance",
    .run = configRun,
};

// Login command (demonstrates secret handling)
const login_cmd = cli.Command{
    .name = "login",
    .summary = "authenticate with a token",
    .flags = &.{
        cli.FlagSpec{
            .name = "token",
            .help = "Authentication token (use --token-file instead)",
            .ftype = .string,
            .secret = .from_file_or_stdin, // This will reject --token=...
        },
        cli.FlagSpec{
            .name = "token-file",
            .help = "Path to file containing token",
            .ftype = .path,
        },
    },
    .run = loginRun,
};

// PS command (for testing suggestions)
const ps_cmd = cli.Command{
    .name = "ps",
    .summary = "list processes",
    .run = psRun,
};

// ============================================================================
// Command Implementations
// ============================================================================

fn kvGetRun(ctx: *cli.Context) !void {
    const key = if (ctx.positionals.items.len > 0)
        ctx.positionals.items[0]
    else
        return ctx.err("Error: KEY argument required\n", .{});

    if (ctx.json) {
        try ctx.print("{{\"key\":\"{s}\",\"value\":\"example-value\"}}\n", .{key});
    } else {
        try ctx.print("{s}\n", .{"example-value"});
    }
}

fn kvSetRun(ctx: *cli.Context) !void {
    const key = if (ctx.positionals.items.len > 0)
        ctx.positionals.items[0]
    else
        return ctx.err("Error: KEY argument required\n", .{});

    const value = ctx.getString("value") orelse "undefined";

    if (ctx.dry_run) {
        try ctx.print("Would set {s} = {s}\n", .{ key, value });
    } else {
        if (ctx.json) {
            try ctx.print("{{\"key\":\"{s}\",\"value\":\"{s}\",\"status\":\"ok\"}}\n", .{ key, value });
        } else {
            try ctx.print("Set {s} = {s}\n", .{ key, value });
        }
    }
}

fn kvListRun(ctx: *cli.Context) !void {
    const keys = &[_][]const u8{ "key1", "key2", "key3" };

    if (ctx.json) {
        try ctx.print("[", .{});
        for (keys, 0..) |key, i| {
            if (i > 0) try ctx.print(",", .{});
            try ctx.print("\"{s}\"", .{key});
        }
        try ctx.print("]\n", .{});
    } else if (ctx.plain) {
        for (keys) |key| {
            try ctx.print("{s}\n", .{key});
        }
    } else {
        try ctx.print("Keys:\n", .{});
        for (keys) |key| {
            try ctx.print("  - {s}\n", .{key});
        }
    }
}

fn serveRun(ctx: *cli.Context) !void {
    const port = ctx.getInt("port") orelse 8080;
    const host = ctx.getString("host") orelse "localhost";

    if (ctx.dry_run) {
        try ctx.print("Would start server on {s}:{d}\n", .{ host, port });
        return;
    }

    if (ctx.json) {
        try ctx.print("{{\"status\":\"starting\",\"host\":\"{s}\",\"port\":{d}}}\n", .{ host, port });
    } else {
        try ctx.print("Starting server on {s}:{d}\n", .{ host, port });
        try ctx.print("Press Ctrl+C to stop\n", .{});
    }
}

fn completionRun(ctx: *cli.Context) !void {
    const shell = ctx.getString("shell") orelse "bash";

    if (std.mem.eql(u8, shell, "bash")) {
        const script = try @import("cli").completion.bash.generate(&root_cmd, ctx.allocator);
        try ctx.stdout.writeAll(script);
    } else if (std.mem.eql(u8, shell, "zsh")) {
        const script = try @import("cli").completion.zsh.generate(&root_cmd, ctx.allocator);
        try ctx.stdout.writeAll(script);
    } else if (std.mem.eql(u8, shell, "fish")) {
        const script = try @import("cli").completion.fish.generate(&root_cmd, ctx.allocator);
        try ctx.stdout.writeAll(script);
    } else {
        try ctx.err("Error: Unknown shell '{s}'. Supported: bash, zsh, fish\n", .{shell});
    }
}

fn manRun(ctx: *cli.Context) !void {
    const man = try @import("cli").help.generateMan(&root_cmd, ctx.allocator);
    try ctx.stdout.writeAll(man);
}

fn configRun(ctx: *cli.Context) !void {
    // Show configuration with provenance
    var loader = config.Loader(AppConfig).init(ctx.allocator);
    defer loader.deinit();

    _ = loader.load(.{
        .app_name = "demo",
        .filename = "config.toml",
        .env_prefix = "DEMO_",
    }) catch {};

    if (ctx.json) {
        try loader.getTracker().printJson(ctx.stdout);
    } else {
        try ctx.print("Configuration (source precedence: flag > env > project > user > system > default)\n\n", .{});
        const tracker = loader.getTracker();
        for (try tracker.getAll()) |val| {
            try ctx.print("{s} = {s} (from: {s})\n", .{ val.key, val.value, val.source.format() });
        }
    }
}

fn loginRun(ctx: *cli.Context) !void {
    // Check for token-file
    if (ctx.getString("token-file")) |path| {
        const token = @import("config").secret.readFromFile(path, ctx.allocator) catch |err| {
            try ctx.err("Error reading token file: {}\n", .{err});
            return;
        };

        // Don't echo the token!
        if (ctx.json) {
            try ctx.print("{{\"status\":\"authenticated\",\"token_length\":{d}}}\n", .{token.len});
        } else {
            try ctx.print("Successfully authenticated (token length: {d})\n", .{token.len});
        }
    } else {
        try ctx.err("Error: Provide --token-file or pipe token via stdin\n", .{});
    }
}

fn psRun(ctx: *cli.Context) !void {
    if (ctx.json) {
        try ctx.print("[{{\"pid\":1,\"name\":\"init\"}}]\n", .{});
    } else {
        try ctx.print("PID   NAME\n", .{});
        try ctx.print("1     init\n", .{});
    }
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const exit_code = try cli.run(&root_cmd, args, allocator);
    std.process.exit(exit_code);
}
