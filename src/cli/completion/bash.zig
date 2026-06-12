// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Bash Completion Module
//!
//! Generates bash completion scripts for CLI commands with full
//! support for nested subcommands.

const std = @import("std");
const sanitize = @import("sanitize");
const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

/// Escape a string for use inside bash double-quoted contexts.
/// Escapes: $, `, ", \, !
/// Strips: NUL bytes (0x00), newlines (0x0A), carriage returns (0x0D).
/// Fast path: if no special chars are found, returns `s` directly (no allocation).
pub fn escapeBashDoubleQuote(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    // Fast path: scan for special chars
    var needs_escape = false;
    for (s) |c| {
        switch (c) {
            '$', '`', '"', '\\', '!', 0x00, '\n', '\r' => {
                needs_escape = true;
                break;
            },
            else => {},
        }
    }
    if (!needs_escape) return s;

    // Build escaped string with capacity hint
    var list: std.ArrayListUnmanaged(u8) = .empty;
    list.ensureTotalCapacity(allocator, s.len) catch {};
    for (s) |c| {
        switch (c) {
            // Strip NUL bytes and newlines entirely
            0x00, '\n', '\r' => {},
            '$', '`', '"', '\\', '!' => {
                list.append(allocator, '\\') catch return error.OutOfMemory;
                list.append(allocator, c) catch return error.OutOfMemory;
            },
            else => {
                list.append(allocator, c) catch return error.OutOfMemory;
            },
        }
    }
    return list.toOwnedSlice(allocator);
}

/// Escape a string for use in bash case patterns.
/// Escapes: *, ?, [, ]
/// Fast path: if no special chars are found, returns `s` directly (no allocation).
pub fn escapeBashCasePattern(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    // Fast path: scan for special chars
    var needs_escape = false;
    for (s) |c| {
        switch (c) {
            '*', '?', '[', ']' => {
                needs_escape = true;
                break;
            },
            else => {},
        }
    }
    if (!needs_escape) return s;

    // Build escaped string with capacity hint
    var list: std.ArrayListUnmanaged(u8) = .empty;
    list.ensureTotalCapacity(allocator, s.len) catch {};
    for (s) |c| {
        switch (c) {
            '*', '?', '[', ']' => {
                list.append(allocator, '\\') catch return error.OutOfMemory;
                list.append(allocator, c) catch return error.OutOfMemory;
            },
            else => {
                list.append(allocator, c) catch return error.OutOfMemory;
            },
        }
    }
    return list.toOwnedSlice(allocator);
}

/// Escape a string for use inside bash single-quoted contexts.
/// Replaces ' with '\'' (close quote, escaped quote, reopen quote).
/// Strips: NUL bytes (0x00), newlines (0x0A), carriage returns (0x0D).
/// Fast path: if no special chars are found, returns `s` directly (no allocation).
pub fn escapeBashSingleQuote(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var needs_escape = false;
    for (s) |c| {
        switch (c) {
            '\'', 0x00, '\n', '\r' => {
                needs_escape = true;
                break;
            },
            else => {},
        }
    }
    if (!needs_escape) return s;

    var list: std.ArrayListUnmanaged(u8) = .empty;
    list.ensureTotalCapacity(allocator, s.len) catch {};
    for (s) |c| {
        switch (c) {
            // Strip NUL bytes and newlines entirely
            0x00, '\n', '\r' => {},
            '\'' => list.appendSlice(allocator, "'\\''") catch return error.OutOfMemory,
            else => list.append(allocator, c) catch return error.OutOfMemory,
        }
    }
    return list.toOwnedSlice(allocator);
}

/// Sanitize a name for use as a bash function identifier.
/// Replaces any character that is not [a-zA-Z0-9_] with an underscore.
/// Uses an arena-allocated buffer (no static mutable state).
fn sanitizeBashIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, name.len);
    for (name, 0..) |c, idx| {
        if (std.ascii.isAlphanumeric(c) or c == '_') {
            buf[idx] = c;
        } else {
            buf[idx] = '_';
        }
    }
    return buf;
}

/// Generate bash completion script
pub fn generate(cmd: *const Command, allocator: std.mem.Allocator) ![]const u8 {
    return generateWithActiveHelp(cmd, allocator, true);
}

/// Generate bash completion script with optional active help support
pub fn generateWithActiveHelp(cmd: *const Command, allocator: std.mem.Allocator, enable_active_help: bool) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const esc_alloc = arena.allocator();

    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 4096);
    const w = &aw.writer;

    // Newline-strip the name so it cannot terminate the comment and inject
    // a live script line (N-04 / CWE-116).
    try w.writeAll("# Bash completion for ");
    try sanitize.writeLineFiltered(w, cmd.name);
    try w.writeAll("\n");
    try w.print("# Generated by zig-cli\n\n", .{});

    // Add active help support function if enabled
    if (enable_active_help) {
        try generateActiveHelpSupport(w, cmd, esc_alloc);
    }

    // Sanitize cmd.name for use in bash function identifiers
    const safe_name = try sanitizeBashIdentifier(esc_alloc, cmd.name);

    // Global flags shared by all completion functions (emitted once; NP-029).
    try w.print("_{s}_global_flags=\"", .{safe_name});
    for (command.global_flags, 0..) |*gflag, gi| {
        if (gi > 0) try w.writeAll(" ");
        const esc_gname = try escapeBashDoubleQuote(esc_alloc, gflag.name);
        try w.print("--{s}", .{esc_gname});
        if (gflag.short) |s| {
            // A short flag is conventionally a single alphanumeric character.
            // Restricting to alphanumeric drops printable shell metacharacters
            // (", `, ', ;, $, (, |) that would otherwise be emitted raw into
            // this double-quoted list (F7-01 / CWE-78/94). Skipping is safe:
            // it just omits the short token from the space-separated list.
            if (std.ascii.isAlphanumeric(s)) try w.print(" -{c}", .{s});
        }
    }
    try w.writeAll("\"\n\n");

    // Generate completion functions for all commands recursively
    try generateCommandFunction(w, cmd, safe_name, "", enable_active_help, esc_alloc);

    // Main completion function
    try w.print("_{s}() {{\n", .{safe_name});
    try w.print("    local cur prev words cword\n", .{});
    try w.print("    _init_completion || return\n\n", .{});
    try w.print("    _{s}_main \"${{words[@]}}\"\n", .{safe_name});
    try w.print("}}\n\n", .{});

    // Quote the registration target: the function id is sanitized, but the
    // command word itself must be single-quote-escaped (N-03 / CWE-78).
    const esc_reg_name = try escapeBashSingleQuote(esc_alloc, cmd.name);
    try w.print("complete -F _{s} '{s}'\n", .{ safe_name, esc_reg_name });

    var list = aw.toArrayList();
    return list.toOwnedSlice(allocator);
}

/// Generate active help support functions
fn generateActiveHelpSupport(w: anytype, cmd: *const Command, esc_alloc: std.mem.Allocator) !void {
    const safe_name = try sanitizeBashIdentifier(esc_alloc, cmd.name);

    // Convert program name to uppercase for env var
    var env_var_buf: [256]u8 = undefined;
    var env_var_len: usize = 0;
    for (cmd.name) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            env_var_buf[env_var_len] = std.ascii.toUpper(c);
        } else {
            env_var_buf[env_var_len] = '_';
        }
        env_var_len += 1;
        if (env_var_len >= env_var_buf.len - 1) break;
    }
    const env_var = env_var_buf[0..env_var_len];

    try w.writeAll("# Active Help Support\n");
    try w.writeAll("# Set ");
    try w.writeAll(env_var);
    try w.writeAll("_ACTIVE_HELP=0 to disable active help\n\n");

    try w.print("_{s}_active_help_enabled() {{\n", .{safe_name});
    try w.writeAll("    # Check if active help is disabled via environment variable\n");
    try w.print("    if [[ \"${{{s}_ACTIVE_HELP}}\" == \"0\" ]]; then\n", .{env_var});
    try w.writeAll("        return 1\n");
    try w.writeAll("    fi\n");
    try w.writeAll("    return 0\n");
    try w.print("}}\n\n", .{});

    // Helper function to display active help messages
    try w.print("_{s}_show_active_help() {{\n", .{safe_name});
    try w.writeAll("    local msg=\"$1\"\n");
    try w.print("    if _{s}_active_help_enabled; then\n", .{safe_name});
    try w.writeAll("        printf '\\n\\033[33m💡 %s\\033[0m\\n' \"$msg\" >&2\n");
    try w.writeAll("    fi\n");
    try w.print("}}\n\n", .{});
}

/// Generate completion function for a command
fn generateCommandFunction(w: anytype, cmd: *const Command, root_name: []const u8, path: []const u8, enable_active_help: bool, esc_alloc: std.mem.Allocator) !void {
    // Build function name
    var func_name_buf: [256]u8 = undefined;
    const func_name = if (path.len > 0)
        std.fmt.bufPrint(&func_name_buf, "{s}_{s}", .{ root_name, path }) catch root_name
    else
        std.fmt.bufPrint(&func_name_buf, "{s}_main", .{root_name}) catch root_name;

    try w.print("_{s}() {{\n", .{func_name});
    try w.print("    local cur=\"${{COMP_WORDS[COMP_CWORD]}}\"\n", .{});
    try w.print("    local prev=\"${{COMP_WORDS[COMP_CWORD-1]}}\"\n\n", .{});

    // Global flags: reference the variable emitted once at top level (NP-029).
    try w.print("    local global_flags=\"${{_{s}_global_flags}}\"\n", .{root_name});

    // Command-specific flags
    try w.writeAll("    local flags=\"$global_flags");
    for (cmd.flags) |*flag| {
        const esc_name = try escapeBashDoubleQuote(esc_alloc, flag.name);
        try w.print(" --{s}", .{esc_name});
        if (flag.short) |s| {
            // Alphanumeric-only short flag (F7-01 / CWE-78/94): drops printable
            // shell metacharacters that would corrupt this double-quoted list.
            if (std.ascii.isAlphanumeric(s)) try w.print(" -{c}", .{s});
        }
    }
    try w.writeAll("\"\n");

    // Subcommands
    if (cmd.subcommands.len > 0) {
        try w.writeAll("    local commands=\"");
        var first = true;
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                if (!first) try w.writeAll(" ");
                first = false;
                // Escape for the double-quoted candidate list so a hostile
                // name cannot terminate the string and inject script (CWE-78).
                const esc_sub = try escapeBashDoubleQuote(esc_alloc, subcmd.name);
                try w.print("{s}", .{esc_sub});
            }
        }
        try w.writeAll("\"\n\n");

        // Find which subcommand we're completing for
        try w.writeAll("    # Find the subcommand\n");
        try w.writeAll("    local i cmd_idx=-1\n");
        try w.writeAll("    for ((i=1; i < ${#COMP_WORDS[@]}-1; i++)); do\n");
        try w.writeAll("        case \"${COMP_WORDS[i]}\" in\n");
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                // Single-quote the case label so the real typed name matches
                // literally and shell metacharacters cannot break out of the
                // case statement (CWE-78).
                const esc_case = try escapeBashSingleQuote(esc_alloc, subcmd.name);
                try w.print("            '{s}')\n", .{esc_case});
                try w.writeAll("                cmd_idx=$i\n");
                try w.writeAll("                break\n");
                try w.writeAll("                ;;\n");
            }
        }
        try w.writeAll("        esac\n");
        try w.writeAll("    done\n\n");

        // If we found a subcommand, delegate to it
        try w.writeAll("    if [[ $cmd_idx -gt 0 ]]; then\n");
        try w.writeAll("        case \"${COMP_WORDS[cmd_idx]}\" in\n");
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                // Function identifiers must use the sanitized name so the
                // call here matches the sanitized definition and no shell
                // metacharacter from the raw name reaches an identifier
                // position (CWE-78/94).
                const safe_sub = try sanitizeBashIdentifier(esc_alloc, subcmd.name);
                var subpath_buf: [256]u8 = undefined;
                const subpath = if (path.len > 0)
                    std.fmt.bufPrint(&subpath_buf, "{s}_{s}", .{ path, safe_sub }) catch path
                else
                    std.fmt.bufPrint(&subpath_buf, "{s}", .{safe_sub}) catch "";

                // Single-quote the case label so the real typed name matches
                // literally (CWE-78).
                const esc_case2 = try escapeBashSingleQuote(esc_alloc, subcmd.name);
                try w.print("            '{s}')\n", .{esc_case2});
                try w.print("                _{s}_{s}\n", .{ root_name, subpath });
                try w.writeAll("                return\n");
                try w.writeAll("                ;;\n");
            }
        }
        try w.writeAll("        esac\n");
        try w.writeAll("    fi\n\n");
    }

    // Handle flag value completion
    try w.writeAll("    # Handle flags that need values\n");
    try w.writeAll("    case $prev in\n");
    for (cmd.flags) |*flag| {
        if (flag.ftype != .bool) {
            // Single-quote the case label so a flag name with shell
            // metacharacters matches literally and cannot break out (CWE-78).
            const esc_flag_case = try escapeBashSingleQuote(esc_alloc, flag.name);
            try w.print("        '--{s}'", .{esc_flag_case});
            if (flag.short) |s| {
                // Alphanumeric-only short flag (F7-01 / CWE-78/94). If skipped,
                // the case label is just `'--name')`, which is valid.
                if (std.ascii.isAlphanumeric(s)) try w.print("|'-{c}'", .{s});
            }
            try w.writeAll(")\n");
            if (flag.ftype == .path) {
                try w.writeAll("            _filedir\n");
            } else if (flag.completions.len > 0) {
                // Use static completion values
                try w.writeAll("            local values=\"");
                for (flag.completions, 0..) |value, i| {
                    if (i > 0) try w.writeAll(" ");
                    const esc_val = try escapeBashDoubleQuote(esc_alloc, value);
                    try w.print("{s}", .{esc_val});
                }
                try w.writeAll("\"\n");
                try w.writeAll("            COMPREPLY=( $(compgen -W \"$values\" -- \"$cur\") )\n");
            } else {
                try w.writeAll("            # Value completion\n");
            }
            try w.writeAll("            return\n");
            try w.writeAll("            ;;\n");
        }
    }
    try w.writeAll("    esac\n\n");

    // Complete flags or commands
    try w.writeAll("    if [[ $cur == -* ]]; then\n");
    try w.writeAll("        COMPREPLY=( $(compgen -W \"$flags\" -- \"$cur\") )\n");
    if (cmd.subcommands.len > 0) {
        try w.writeAll("    else\n");
        try w.writeAll("        COMPREPLY=( $(compgen -W \"$commands\" -- \"$cur\") )\n");
    }
    try w.writeAll("    fi\n");

    // Display active help when no completions are available
    if (enable_active_help and cmd.active_help.len > 0) {
        try w.writeAll("\n    # Display active help when no completions\n");
        try w.writeAll("    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then\n");
        for (cmd.active_help) |help_msg| {
            const esc_help = try escapeBashDoubleQuote(esc_alloc, help_msg);
            try w.print("        _{s}_show_active_help \"{s}\"\n", .{ root_name, esc_help });
        }
        try w.writeAll("    fi\n");
    }

    try w.print("}}\n\n", .{});

    // Recursively generate functions for subcommands
    for (cmd.subcommands) |subcmd| {
        if (!subcmd.hidden) {
            // Sanitize each path component: it composes the function name
            // emitted by the recursive call (must stay [a-zA-Z0-9_]).
            const safe_sub = try sanitizeBashIdentifier(esc_alloc, subcmd.name);
            var subpath_buf: [256]u8 = undefined;
            const subpath = if (path.len > 0)
                std.fmt.bufPrint(&subpath_buf, "{s}_{s}", .{ path, safe_sub }) catch path
            else
                std.fmt.bufPrint(&subpath_buf, "{s}", .{safe_sub}) catch "";

            try generateCommandFunction(w, subcmd, root_name, subpath, enable_active_help, esc_alloc);
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "generate bash completion" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "_test()") != null);
    // Registration target is single-quoted (N-03)
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _test 'test'") != null);
}

test "bash: completion header comment" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "# Bash completion for myapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "# Generated by zig-cli") != null);
}

test "bash: completion function name" {
    const cmd = Command{
        .name = "webapp",
        .summary = "Web application",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "_webapp()") != null);
    // Registration target is single-quoted (N-03)
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _webapp 'webapp'") != null);
}

test "bash: completion with subcommands generates functions" {
    const subcmd1 = Command{
        .name = "start",
        .summary = "Start service",
    };
    const subcmd2 = Command{
        .name = "stop",
        .summary = "Stop service",
    };
    const cmd = Command{
        .name = "service",
        .summary = "Service manager",
        .subcommands = &.{ &subcmd1, &subcmd2 },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "_service_start()") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "_service_stop()") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "local commands=\"start stop\"") != null);
}

test "bash: completion with flags" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            command.FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .path,
            },
            command.FlagSpec{
                .name = "verbose",
                .help = "Verbose output",
                .ftype = .bool,
            },
        },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "--config") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--verbose") != null);
}

test "bash: global flags emitted once, referenced per function" {
    const subcmd = Command{
        .name = "sub",
        .summary = "A subcommand",
    };
    const cmd = Command{
        .name = "app",
        .summary = "Application",
        .subcommands = &.{&subcmd},
    };

    const out = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(out);

    // The top-level variable must appear exactly once
    const first = std.mem.indexOf(u8, out, "_app_global_flags=").?;
    try std.testing.expect(std.mem.indexOfPos(u8, out, first + 1, "_app_global_flags=") == null);

    // Every completion function must reference it via the local alias
    // (one function for the root, one for the subcommand)
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(u8, out, "local global_flags=\"${_app_global_flags}\""),
    );

    // The alias must still be composed into flags=
    try std.testing.expect(std.mem.indexOf(u8, out, "local flags=\"$global_flags") != null);

    // The definition must precede the first completion function
    try std.testing.expect(first < std.mem.indexOf(u8, out, "_app_main() {").?);
}

test "bash: completion includes global flags" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "--help") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--version") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--json") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--plain") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--dry-run") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--no-input") != null);
}

test "bash: completion init_completion" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "_init_completion || return") != null);
}

test "bash: completion nested subcommands" {
    const leaf_cmd = Command{
        .name = "get",
        .summary = "Get a value",
    };
    const sub_cmd = Command{
        .name = "kv",
        .summary = "Key-value operations",
        .subcommands = &.{&leaf_cmd},
    };
    const cmd = Command{
        .name = "app",
        .summary = "Application",
        .subcommands = &.{&sub_cmd},
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "_app_kv()") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "_app_kv_get()") != null);
}

test "bash: completion compgen usage" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOf(u8, script, "COMPREPLY=") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "compgen -W") != null);
}

test "bash: flag value completions" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            command.FlagSpec{
                .name = "format",
                .help = "Output format",
                .ftype = .string,
                .completions = &.{ "json", "yaml", "toml" },
            },
        },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Bash uses local values for completions
    try std.testing.expect(std.mem.indexOf(u8, script, "local values=\"json yaml toml\"") != null);
}

test "bash: path flag uses filedir" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            command.FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .path,
            },
        },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Path flags should use _filedir for file completion
    try std.testing.expect(std.mem.indexOf(u8, script, "_filedir") != null);
}

test "bash: hides hidden subcommands" {
    const subcmd1 = Command{
        .name = "visible",
        .summary = "Visible command",
    };
    const subcmd2 = Command{
        .name = "hidden",
        .summary = "Hidden command",
        .hidden = true,
    };
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .subcommands = &.{ &subcmd1, &subcmd2 },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // visible should be in commands list
    try std.testing.expect(std.mem.indexOf(u8, script, "local commands=\"visible\"") != null);
}

test "bash: active help support functions" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Should have active help functions
    try std.testing.expect(std.mem.indexOf(u8, script, "_myapp_active_help_enabled()") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "_myapp_show_active_help()") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "MYAPP_ACTIVE_HELP") != null);
}

test "bash: active help messages included" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .active_help = &.{
            "Specify a subcommand to run",
            "Use --help for more information",
        },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Should include active help messages
    try std.testing.expect(std.mem.indexOf(u8, script, "Specify a subcommand to run") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "Use --help for more information") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "_myapp_show_active_help") != null);
}

test "bash: active help can be disabled" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .active_help = &.{"Help message"},
    };

    const script = try generateWithActiveHelp(&cmd, std.testing.allocator, false);
    defer std.testing.allocator.free(script);

    // Should NOT have active help functions when disabled
    try std.testing.expect(std.mem.indexOf(u8, script, "_myapp_active_help_enabled()") == null);
    try std.testing.expect(std.mem.indexOf(u8, script, "_myapp_show_active_help") == null);
}

test "bash: active help env var naming" {
    const cmd = Command{
        .name = "my-app",
        .summary = "My application with dashes",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Dashes should be converted to underscores
    try std.testing.expect(std.mem.indexOf(u8, script, "MY_APP_ACTIVE_HELP") != null);
}

// ============================================================================
// Shell Escape Function Tests
//
// Tests for the public escaper family (escapeBashDoubleQuote,
// escapeBashCasePattern, escapeBashSingleQuote) and public-API generate
// tests for N-03/N-04 hardening live in bash_test.zig. The tests below
// exercise the private sanitizeBashIdentifier helper.
// ============================================================================

test "bash: sanitizeBashIdentifier replaces hyphens and dots" {
    const result = try sanitizeBashIdentifier(std.testing.allocator, "my-app.cli");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("my_app_cli", result);
}

test "bash: sanitizeBashIdentifier preserves alphanumerics and underscores" {
    const result = try sanitizeBashIdentifier(std.testing.allocator, "myapp_v2");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("myapp_v2", result);
}

test "bash: cmd.name with hyphens produces valid function names" {
    const cmd = Command{
        .name = "my-app",
        .summary = "App with hyphens",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Function name should use underscores, not hyphens
    try std.testing.expect(std.mem.indexOf(u8, script, "_my_app()") != null);
    // But complete registration should use the original name, quoted (N-03)
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _my_app 'my-app'") != null);
    // The shared global-flags variable must also use the sanitized name
    try std.testing.expect(std.mem.indexOf(u8, script, "_my_app_global_flags=") != null);
}
