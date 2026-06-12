// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Zsh Completion Module
//!
//! Generates zsh completion scripts for CLI commands with full
//! support for nested subcommands.

const std = @import("std");
const sanitize = @import("sanitize");
const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

/// True when `c` is in the comptime-known `set` (unrolled membership test).
inline fn inSet(comptime set: []const u8, c: u8) bool {
    inline for (set) |e| {
        if (c == e) return true;
    }
    return false;
}

/// Shared core for the zsh single-quoted-context escapers.
/// Handles the two-pass logic: a scan-only fast path (returns `s` directly,
/// no allocation), the '\'' pattern to break out of single quotes and
/// re-enter, and stripping of NUL bytes (0x00), newlines (0x0A), and
/// carriage returns (0x0D). Characters in the comptime `backslash_extra`
/// set are additionally backslash-escaped for context-specific
/// metacharacters (optspec brackets, _describe colons).
fn escapeZshQuoted(comptime backslash_extra: []const u8, allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var needs_escape = false;
    for (s) |c| {
        if (c == '\'' or c == 0x00 or c == '\n' or c == '\r' or inSet(backslash_extra, c)) {
            needs_escape = true;
            break;
        }
    }
    if (!needs_escape) return s;

    var list: std.ArrayListUnmanaged(u8) = .empty;
    list.ensureTotalCapacity(allocator, s.len + 4) catch {};
    for (s) |c| {
        switch (c) {
            0x00, '\n', '\r' => {},
            '\'' => {
                // zsh '\'' pattern: end quote, escaped quote, reopen quote
                list.appendSlice(allocator, "'\\''") catch return error.OutOfMemory;
            },
            else => {
                if (inSet(backslash_extra, c)) {
                    list.append(allocator, '\\') catch return error.OutOfMemory;
                }
                list.append(allocator, c) catch return error.OutOfMemory;
            },
        }
    }
    return list.toOwnedSlice(allocator);
}

/// Escape a string for use inside zsh single-quoted contexts.
/// Uses the '\'' pattern to break out of single quotes and re-enter.
/// Strips: NUL bytes (0x00), newlines (0x0A), carriage returns (0x0D).
/// Fast path: if no single quotes or control chars, returns `s` directly (no allocation).
pub fn escapeZshSingleQuote(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return escapeZshQuoted("", allocator, s);
}

/// Escape a string for use inside zsh double-quoted contexts.
/// Escapes: $, `, ", \
/// Strips: NUL bytes (0x00), newlines (0x0A), carriage returns (0x0D).
/// Fast path: if no special chars, returns `s` directly (no allocation).
pub fn escapeZshDoubleQuote(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var needs_escape = false;
    for (s) |c| {
        switch (c) {
            '$', '`', '"', '\\', 0x00, '\n', '\r' => {
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
            0x00, '\n', '\r' => {},
            '$', '`', '"', '\\' => {
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

/// Escape a flag name for use inside zsh option-spec NAME positions.
/// Option specs have the form `'--flagname[description]'`.  A `]` in the
/// NAME portion would close the description bracket early; a `'` would
/// break out of the surrounding single-quote context.  `[` is also escaped
/// to prevent it from opening a spurious bracket.
/// Strips: NUL bytes (0x00), newlines (0x0A), carriage returns (0x0D).
/// Fast path: if no special chars, returns `s` directly (no allocation).
pub fn escapeZshOptspecName(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return escapeZshQuoted("[]", allocator, s);
}

/// Escape a name for use in the WORD portion of a zsh `_describe` array
/// entry (`'word:description'`).  An unescaped `:` in the word terminates
/// it early, so the completed word would be a prefix of the real name while
/// the dispatch case label uses the full name — the subcommand becomes
/// unreachable.  `_describe` supports `\:` for a literal colon in the word.
/// Strips: NUL bytes (0x00), newlines (0x0A), carriage returns (0x0D).
/// Fast path: if no special chars, returns `s` directly (no allocation).
pub fn escapeZshDescribeName(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    return escapeZshQuoted(":", allocator, s);
}

/// Sanitize a name for use as a zsh function identifier.
/// Replaces any character that is not [a-zA-Z0-9_] with an underscore.
/// Only function IDENTIFIERS are sanitized; completion registration
/// (#compdef) and case labels keep the real command name (CWE-78).
fn sanitizeZshIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
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

/// Generate zsh completion script
pub fn generate(cmd: *const Command, allocator: std.mem.Allocator) ![]const u8 {
    return generateWithActiveHelp(cmd, allocator, true);
}

/// Generate zsh completion script with optional active help support
pub fn generateWithActiveHelp(cmd: *const Command, allocator: std.mem.Allocator, enable_active_help: bool) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    // esc_alloc MUST be arena-backed: escaper results are never individually freed.
    const esc_alloc = arena.allocator();

    var buf: std.Io.Writer.Allocating = .init(allocator);
    errdefer buf.deinit();
    buf.ensureUnusedCapacity(4096) catch {};
    const w = &buf.writer;

    // Strip control bytes AND newlines from the name (CWE-150 / N-04): a
    // newline would terminate the #compdef directive or comment and inject
    // a live script line. Whitespace in a binary name is otherwise out of
    // scope — completion cannot target such a binary anyway.
    try w.writeAll("#compdef ");
    try sanitize.writeLineFiltered(w, cmd.name);
    try w.writeAll("\n\n");
    try w.writeAll("# Zsh completion for ");
    try sanitize.writeLineFiltered(w, cmd.name);
    try w.writeAll("\n");
    try w.print("# Generated by zig-cli\n\n", .{});

    // Sanitize cmd.name for use in zsh function identifiers; #compdef and
    // other places where zsh expects the command word keep the real name.
    const safe_name = try sanitizeZshIdentifier(esc_alloc, cmd.name);

    // Add active help support if enabled
    if (enable_active_help) {
        try generateActiveHelpSupport(w, cmd, safe_name);
    }

    // Generate helper function for flags (sourced from canonical command.global_flags)
    try w.writeAll("# Global flags available to all commands\n");
    try w.writeAll("_global_flags=(\n");
    for (command.global_flags) |*gflag| {
        const esc_ghelp = try escapeZshSingleQuote(esc_alloc, gflag.help);
        const esc_gname = try escapeZshOptspecName(esc_alloc, gflag.name);
        // A short flag is conventionally a single alphanumeric character.
        // Treating a non-alphanumeric short as "no short flag" routes it to the
        // long-only optspec branch below (`'--name[...]'`) instead of emitting a
        // half-formed `'(-" --name)'{-",--name}'[...]'` combined spec
        // (F7-01 / CWE-78/94).
        const gshort: ?u8 = if (gflag.short) |s| (if (std.ascii.isAlphanumeric(s)) s else null) else null;
        if (gshort) |s| {
            if (gflag.ftype == .bool) {
                try w.print("    '(-{c} --{s})'{{-{c},--{s}}}'[{s}]'\n", .{
                    s, esc_gname, s, esc_gname, esc_ghelp,
                });
            } else {
                try w.print("    '(-{c} --{s})'{{-{c},--{s}}}'[{s}]:value:'\n", .{
                    s, esc_gname, s, esc_gname, esc_ghelp,
                });
            }
        } else {
            if (gflag.ftype == .bool) {
                try w.print("    '--{s}[{s}]'\n", .{ esc_gname, esc_ghelp });
            } else {
                try w.print("    '--{s}[{s}]:value:'\n", .{ esc_gname, esc_ghelp });
            }
        }
    }
    try w.writeAll(")\n\n");

    // Generate completion functions for all commands recursively
    try generateCommandFunction(w, cmd, safe_name, safe_name, enable_active_help, esc_alloc);

    // Entry point
    try w.print("_{s}\n", .{safe_name});

    return buf.toOwnedSlice();
}

/// Generate active help support functions for zsh.
/// `safe_name` is the sanitized root command name used for function identifiers.
fn generateActiveHelpSupport(w: anytype, cmd: *const Command, safe_name: []const u8) !void {
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

    try w.print("_{s}_active_help() {{\n", .{safe_name});
    try w.writeAll("    local msg=\"$1\"\n");
    try w.print("    [[ \"${{{s}_ACTIVE_HELP}}\" == \"0\" ]] && return\n", .{env_var});
    try w.writeAll("    print -P \"\\n%F{yellow}💡 $msg%f\" >&2\n");
    try w.print("}}\n\n", .{});
}

/// Generate a completion function for a command and its subcommands.
/// `prefix` and `root_name` are pre-sanitized zsh function identifiers
/// (see sanitizeZshIdentifier); never raw command names.
fn generateCommandFunction(w: anytype, cmd: *const Command, prefix: []const u8, root_name: []const u8, enable_active_help: bool, esc_alloc: std.mem.Allocator) !void {
    try w.print("_{s}() {{\n", .{prefix});
    try w.print("    local curcontext=\"$curcontext\" state line\n", .{});
    try w.print("    typeset -A opt_args\n\n", .{});

    // Build flags array
    try w.print("    local -a flags\n", .{});
    try w.print("    flags=(\n", .{});
    try w.writeAll("        $_global_flags\n");

    // Command-specific flags
    for (cmd.flags) |*flag| {
        try writeZshFlag(w, flag, esc_alloc);
    }
    try w.print("    )\n\n", .{});

    if (cmd.subcommands.len > 0) {
        // Command with subcommands
        try w.print("    _arguments -C \\\n", .{});
        try w.print("        $flags \\\n", .{});
        try w.print("        '1: :->command' \\\n", .{});
        try w.print("        '*:: :->args'\n\n", .{});

        try w.print("    case $state in\n", .{});
        try w.print("        command)\n", .{});
        try w.print("            local -a commands\n", .{});
        try w.print("            commands=(\n", .{});
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                // Escape single quotes in name and summary; a literal `:` in
                // the name must additionally become `\:` so _describe does
                // not split the word early (the case label below keeps the
                // raw `:`, matching what the user actually types).
                const esc_name = try escapeZshDescribeName(esc_alloc, subcmd.name);
                const esc_summary = try escapeZshSingleQuote(esc_alloc, subcmd.summary);
                try w.print("                '{s}:{s}'\n", .{ esc_name, esc_summary });
            }
        }
        try w.print("            )\n", .{});
        try w.print("            _describe -t commands 'command' commands\n", .{});
        try w.print("            ;;\n", .{});

        try w.print("        args)\n", .{});
        try w.print("            case $line[1] in\n", .{});
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                // Function identifier: sanitized name component only.
                const safe_sub = try sanitizeZshIdentifier(esc_alloc, subcmd.name);
                var subprefix_buf: [256]u8 = undefined;
                const subprefix = std.fmt.bufPrint(&subprefix_buf, "{s}_{s}", .{ prefix, safe_sub }) catch prefix;
                // Case label: real name, single-quoted ('literal') matches
                // the literal in zsh) so metacharacters cannot inject (CWE-78).
                const esc_label = try escapeZshSingleQuote(esc_alloc, subcmd.name);
                try w.print("                '{s}')\n", .{esc_label});
                try w.print("                    _{s}\n", .{subprefix});
                try w.print("                    ;;\n", .{});
            }
        }
        try w.print("            esac\n", .{});
        try w.print("            ;;\n", .{});
        try w.print("    esac\n", .{});
    } else {
        // Leaf command (no subcommands)
        try w.print("    _arguments -s $flags '*:file:_files'\n", .{});

        // Display active help for leaf commands when no completions
        if (enable_active_help and cmd.active_help.len > 0) {
            try w.writeAll("\n    # Display active help\n");
            try w.writeAll("    if (( ${#words[@]} > 2 )); then\n");
            for (cmd.active_help) |help_msg| {
                const esc_help = try escapeZshDoubleQuote(esc_alloc, help_msg);
                try w.print("        _{s}_active_help \"{s}\"\n", .{ root_name, esc_help });
            }
            try w.writeAll("    fi\n");
        }
    }

    try w.print("}}\n\n", .{});

    // Recursively generate functions for subcommands
    for (cmd.subcommands) |subcmd| {
        if (!subcmd.hidden) {
            const safe_sub = try sanitizeZshIdentifier(esc_alloc, subcmd.name);
            var subprefix_buf: [256]u8 = undefined;
            const subprefix = std.fmt.bufPrint(&subprefix_buf, "{s}_{s}", .{ prefix, safe_sub }) catch prefix;
            try generateCommandFunction(w, subcmd, subprefix, root_name, enable_active_help, esc_alloc);
        }
    }
}

/// Write a zsh flag specification.
/// `esc_alloc` MUST be arena-backed: escape results and `value_list` storage
/// are never individually freed.
fn writeZshFlag(w: anytype, flag: *const FlagSpec, esc_alloc: std.mem.Allocator) !void {
    const required_suffix: []const u8 = if (flag.required) " (required)" else "";
    const esc_help = try escapeZshSingleQuote(esc_alloc, flag.help);
    // Gap B: flag name in the NAME portion of `'--flagname[desc]'` optspecs.
    // A `]` in the name closes the description bracket; `'` breaks single-quote
    // context.  Use escapeZshOptspecName to neutralise both.
    const esc_fname = try escapeZshOptspecName(esc_alloc, flag.name);

    // Build value completion spec
    // Gap C: completion values were copied raw via @memcpy.  Use
    // escapeZshSingleQuote so that a `'` in a value cannot break out of the
    // surrounding single-quoted optspec context.
    var value_spec: []const u8 = "";
    var value_list: std.ArrayListUnmanaged(u8) = .empty;
    if (flag.ftype == .path) {
        value_spec = "_files";
    } else if (flag.completions.len > 0) {
        value_list.ensureTotalCapacity(esc_alloc, 64) catch {};
        value_list.append(esc_alloc, '(') catch return error.OutOfMemory;
        for (flag.completions, 0..) |val, i| {
            if (i > 0) {
                value_list.append(esc_alloc, ' ') catch return error.OutOfMemory;
            }
            const esc_val = try escapeZshSingleQuote(esc_alloc, val);
            value_list.appendSlice(esc_alloc, esc_val) catch return error.OutOfMemory;
        }
        value_list.append(esc_alloc, ')') catch return error.OutOfMemory;
        value_spec = value_list.items;
    }

    // Known limitation: a `[` in a long flag name combined with a short flag
    // emits the name inside `{-s,--name}` brace expansion, which strips the
    // backslash escape and degrades the optspec. Accepted as pathological.
    // A short flag is conventionally a single alphanumeric character; a
    // non-alphanumeric short is treated as "no short flag" and routed to the
    // long-only optspec branch below, so a printable metacharacter never
    // reaches the combined `'(-c --name)'{-c,--name}'[...]'` spec
    // (F7-01 / CWE-78/94).
    const short: ?u8 = if (flag.short) |s| (if (std.ascii.isAlphanumeric(s)) s else null) else null;
    if (short) |s| {
        if (flag.ftype == .bool) {
            try w.print("        '(-{c} --{s})'{{-{c},--{s}}}'[{s}{s}]'\n", .{
                s, esc_fname, s, esc_fname, esc_help, required_suffix,
            });
        } else {
            try w.print("        '(-{c} --{s})'{{-{c},--{s}}}'[{s}{s}]:value:{s}'\n", .{
                s, esc_fname, s, esc_fname, esc_help, required_suffix, value_spec,
            });
        }
    } else {
        if (flag.ftype == .bool) {
            try w.print("        '--{s}[{s}{s}]'\n", .{ esc_fname, esc_help, required_suffix });
        } else {
            try w.print("        '--{s}[{s}{s}]:value:{s}'\n", .{ esc_fname, esc_help, required_suffix, value_spec });
        }
    }
}

// ============================================================================
// Shell Escape Function Tests
//
// Public-API tests for `generate`/`generateWithActiveHelp` live in
// zsh_test.zig. The tests below exercise the escaper family, including
// the private escapeZshQuoted core via its public wrappers.
// ============================================================================

test "zsh: escapeZshSingleQuote no special chars" {
    const result = try escapeZshSingleQuote(std.testing.allocator, "hello world");
    try std.testing.expectEqualStrings("hello world", result);
}

test "zsh: escapeZshSingleQuote with single quote" {
    const result = try escapeZshSingleQuote(std.testing.allocator, "it's");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("it'\\''s", result);
}

test "zsh: escapeZshSingleQuote empty string" {
    const result = try escapeZshSingleQuote(std.testing.allocator, "");
    try std.testing.expectEqualStrings("", result);
}

test "zsh: escapeZshDoubleQuote no special chars" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "hello");
    try std.testing.expectEqualStrings("hello", result);
}

test "zsh: escapeZshDoubleQuote with dollar sign" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "val$ue");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("val\\$ue", result);
}

test "zsh: escapeZshDoubleQuote with backslash" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "path\\to");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("path\\\\to", result);
}

test "zsh: escapeZshDoubleQuote with double quote" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "say\"hi\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("say\\\"hi\\\"", result);
}

test "zsh: escapeZshDoubleQuote with backtick" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "run`cmd`");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("run\\`cmd\\`", result);
}

test "zsh: escapeZshDoubleQuote empty string" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "");
    try std.testing.expectEqualStrings("", result);
}

test "zsh: escapeZshSingleQuote strips NUL bytes" {
    const result = try escapeZshSingleQuote(std.testing.allocator, "hel\x00lo");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "zsh: escapeZshSingleQuote strips newlines" {
    const result = try escapeZshSingleQuote(std.testing.allocator, "line1\nline2\rline3");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("line1line2line3", result);
}

test "zsh: escapeZshDoubleQuote strips NUL and newlines" {
    const result = try escapeZshDoubleQuote(std.testing.allocator, "a\x00b\nc\rd");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("abcd", result);
}

// ============================================================================
// Gap B: flag name escaping in zsh optspec NAME position (NS-061, #38)
// ============================================================================

test "zsh: escapeZshOptspecName no special chars" {
    const result = try escapeZshOptspecName(std.testing.allocator, "verbose");
    try std.testing.expectEqualStrings("verbose", result);
}

test "zsh: escapeZshOptspecName with closing bracket" {
    const result = try escapeZshOptspecName(std.testing.allocator, "f]x");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("f\\]x", result);
}

test "zsh: escapeZshOptspecName with opening bracket" {
    const result = try escapeZshOptspecName(std.testing.allocator, "f[x");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("f\\[x", result);
}

test "zsh: escapeZshOptspecName with single quote" {
    const result = try escapeZshOptspecName(std.testing.allocator, "f'x");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("f'\\''x", result);
}

test "zsh: escapeZshDescribeName no special chars" {
    const result = try escapeZshDescribeName(std.testing.allocator, "start");
    try std.testing.expectEqualStrings("start", result);
}

test "zsh: escapeZshDescribeName with colon" {
    const result = try escapeZshDescribeName(std.testing.allocator, "foo:bar");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("foo\\:bar", result);
}

test "zsh: escapeZshDescribeName with single quote" {
    const result = try escapeZshDescribeName(std.testing.allocator, "f'x");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("f'\\''x", result);
}
