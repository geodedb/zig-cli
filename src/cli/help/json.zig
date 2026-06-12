// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: JSON Output
//!
//! JSON-format help rendering for the help subsystem: `printJsonHelp` and
//! the `writeJsonEscapedString` escaper shared with version printing.

const std = @import("std");
const mem = std.mem;

const command = @import("../command.zig");
const Command = command.Command;
const Context = command.Context;
const FlagSpec = command.FlagSpec;

/// Write a JSON-escaped string value (without surrounding quotes).
/// Escapes: ", \, control characters (\n, \r, \t, and chars < 0x20 as \uXXXX).
/// Write a JSON-escaped string to `w`. Uses span-based flushing: runs of
/// non-special characters are written in a single `writeAll` call, reducing
/// the number of writer calls from O(n) to O(specials).
pub fn writeJsonEscapedString(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const escape: ?[]const u8 = switch (c) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            else => if (c < 0x20) @as(?[]const u8, "") else null,
        };
        if (escape) |esc| {
            // Flush the span of clean characters before this special char
            if (idx > start) {
                try w.writeAll(s[start..idx]);
            }
            if (esc.len > 0) {
                try w.writeAll(esc);
            } else {
                // Control character -- emit \uXXXX
                try w.print("\\u{x:0>4}", .{@as(u16, c)});
            }
            start = idx + 1;
        }
    }
    // Flush remaining clean characters
    if (start < s.len) {
        try w.writeAll(s[start..]);
    }
}

/// Print JSON-format help.
/// Renders into a memory buffer first, then writes to stdout in a single
/// call to reduce syscall overhead.
// Internal to the help subsystem; pub for cross-file use within the module.
pub fn printJsonHelp(cmd: *const Command, ctx: *Context) !void {
    var buf: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer buf.deinit();
    buf.ensureUnusedCapacity(1024) catch {};
    const w = &buf.writer;

    try w.print("{{", .{});
    try w.writeAll("\"name\":\"");
    try writeJsonEscapedString(w, cmd.name);
    try w.writeAll("\",");
    try w.writeAll("\"summary\":\"");
    try writeJsonEscapedString(w, cmd.summary);
    try w.writeAll("\",");
    try w.writeAll("\"usage\":\"");
    try writeJsonEscapedString(w, cmd.name);
    try w.writeAll(" [flags]");
    if (cmd.hasSubcommands()) {
        try w.writeAll(" <command> [args]");
    }
    try w.writeAll("\",");

    // Flags
    try w.print("\"flags\":[", .{});
    var first_flag = true;

    // Global flags
    for (command.global_flags) |*flag| {
        if (!first_flag) try w.print(",", .{});
        first_flag = false;
        try printJsonFlag(w, flag);
    }

    // Command flags
    for (cmd.flags) |*flag| {
        if (!first_flag) try w.print(",", .{});
        first_flag = false;
        try printJsonFlag(w, flag);
    }
    try w.print("],", .{});

    // Subcommands
    try w.print("\"subcommands\":[", .{});
    var first = true;
    for (cmd.subcommands) |subcmd| {
        if (subcmd.hidden) continue;
        if (!first) try w.print(",", .{});
        first = false;
        try w.writeAll("{\"name\":\"");
        try writeJsonEscapedString(w, subcmd.name);
        try w.writeAll("\",\"summary\":\"");
        try writeJsonEscapedString(w, subcmd.summary);
        try w.writeAll("\"}");
    }
    try w.print("]", .{});

    try w.print("}}\n", .{});

    try ctx.stdout.writeAll(buf.written());
}

fn printJsonFlag(w: anytype, flag: *const FlagSpec) !void {
    try w.print("{{", .{});
    try w.writeAll("\"name\":\"");
    try writeJsonEscapedString(w, flag.name);
    try w.writeAll("\",");
    try w.writeAll("\"help\":\"");
    try writeJsonEscapedString(w, flag.help);
    try w.writeAll("\",");
    if (flag.short) |s| {
        try w.writeAll("\"short\":\"");
        try writeJsonEscapedString(w, &[_]u8{s});
        try w.writeAll("\",");
    } else {
        try w.writeAll("\"short\":null,");
    }
    try w.print("\"type\":\"{s}\",", .{flag.ftype.format()});
    try w.print("\"required\":{},", .{flag.required});
    if (flag.env) |env_var| {
        try w.writeAll("\"env\":\"");
        try writeJsonEscapedString(w, env_var);
        try w.writeAll("\"");
    } else {
        try w.print("\"env\":null", .{});
    }
    try w.print("}}", .{});
}

// ============================================================================
// JSON Escaping Tests
// ============================================================================

test "help: writeJsonEscapedString plain text" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeJsonEscapedString(w, "hello world");
    try std.testing.expectEqualStrings("hello world", buf.written());
}

test "help: writeJsonEscapedString with double quote" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeJsonEscapedString(w, "say \"hi\"");
    try std.testing.expectEqualStrings("say \\\"hi\\\"", buf.written());
}

test "help: writeJsonEscapedString with backslash" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeJsonEscapedString(w, "path\\to\\file");
    try std.testing.expectEqualStrings("path\\\\to\\\\file", buf.written());
}

test "help: writeJsonEscapedString with newline" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeJsonEscapedString(w, "line1\nline2");
    try std.testing.expectEqualStrings("line1\\nline2", buf.written());
}

test "help: writeJsonEscapedString with tab and carriage return" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeJsonEscapedString(w, "a\tb\rc");
    try std.testing.expectEqualStrings("a\\tb\\rc", buf.written());
}

test "help: writeJsonEscapedString with control char" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    // ASCII 0x01 (SOH)
    try writeJsonEscapedString(w, "\x01");
    try std.testing.expectEqualStrings("\\u0001", buf.written());
}

test "help: writeJsonEscapedString empty string" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeJsonEscapedString(w, "");
    try std.testing.expectEqual(@as(usize, 0), buf.written().len);
}

test "help: json short flag with quote char is escaped" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const flag = FlagSpec{
        .name = "delim",
        .help = "Delimiter character",
        .short = '"',
        .ftype = .string,
    };
    try printJsonFlag(w, &flag);
    const out = buf.written();
    // "short" value must be JSON-escaped: "short":"\"" not "short":"""
    try std.testing.expect(mem.indexOf(u8, out, "\"short\":\"\\\"\"") != null);
    // The raw double-quote must not appear as an unescaped JSON value
    try std.testing.expect(mem.indexOf(u8, out, "\"short\":\"\"") == null);
}

test "help: json short flag with backslash is escaped" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const flag = FlagSpec{
        .name = "sep",
        .help = "Separator",
        .short = '\\',
        .ftype = .string,
    };
    try printJsonFlag(w, &flag);
    const out = buf.written();
    // "short" value must be JSON-escaped: "short":"\\" not "short":"\"
    try std.testing.expect(mem.indexOf(u8, out, "\"short\":\"\\\\\"") != null);
}

test "help: json short flag benign char renders verbatim" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const flag = FlagSpec{
        .name = "verbose",
        .help = "Verbose output",
        .short = 'v',
        .ftype = .bool,
    };
    try printJsonFlag(w, &flag);
    const out = buf.written();
    // Benign char must render unchanged: "short":"v"
    try std.testing.expect(mem.indexOf(u8, out, "\"short\":\"v\"") != null);
}
