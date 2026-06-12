// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: Man Page Generation
//!
//! Roff (man page) output for the help subsystem: `generateMan` and the
//! injection-safe `writeRoffEscaped` escaper.

const std = @import("std");
const mem = std.mem;

const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

/// Write a roff-escaped version of a user string.
/// Escapes: `\` -> `\\`, `-` -> `\-`, leading `.` -> `\&.`, leading `'` -> `\&'`.
/// After newlines, `.` and `'` at the start of a new line are also escaped
/// to prevent roff command injection.
///
/// Uses span-based flushing: accumulates runs of clean characters and writes
/// them in a single writeAll call, avoiding per-byte writeByte overhead.
pub fn writeRoffEscaped(w: anytype, s: []const u8) !void {
    var at_line_start = true;
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const needs_escape = switch (c) {
            '\\', '-' => true,
            '.' => at_line_start,
            '\'' => at_line_start,
            '\n' => true,
            else => false,
        };
        if (needs_escape) {
            // Flush accumulated clean characters
            if (idx > start) {
                try w.writeAll(s[start..idx]);
            }
            switch (c) {
                '\\' => try w.writeAll("\\\\"),
                '-' => try w.writeAll("\\-"),
                '.' => try w.writeAll("\\&."),
                '\'' => try w.writeAll("\\&'"),
                '\n' => {
                    try w.writeByte('\n');
                    at_line_start = true;
                    start = idx + 1;
                    continue;
                },
                else => unreachable,
            }
            at_line_start = false;
            start = idx + 1;
        } else {
            at_line_start = false;
        }
    }
    // Flush remaining clean characters
    if (start < s.len) {
        try w.writeAll(s[start..]);
    }
}

/// Generate man page in roff format
pub fn generateMan(cmd: *const Command, allocator: std.mem.Allocator) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    errdefer buf.deinit();
    buf.ensureUnusedCapacity(4096) catch {};
    const w = &buf.writer;

    try w.writeAll(".TH ");
    try writeRoffEscaped(w, cmd.name);
    try w.writeAll(" 1\n");
    try w.writeAll(".SH NAME\n");
    try writeRoffEscaped(w, cmd.name);
    try w.writeAll(" \\- ");
    try writeRoffEscaped(w, cmd.summary);
    try w.writeAll("\n");

    try w.writeAll(".SH SYNOPSIS\n");
    try w.writeAll(".B ");
    try writeRoffEscaped(w, cmd.name);
    try w.writeAll("\n");
    try w.writeAll("[\\fIOPTIONS\\fR] ");
    if (cmd.hasSubcommands()) {
        try w.writeAll("<\\fICOMMAND\\fR> [\\fIARGS\\fR]");
    }
    try w.writeAll("\n");

    if (cmd.long_help.len > 0) {
        try w.writeAll(".SH DESCRIPTION\n");
        try writeRoffEscaped(w, cmd.long_help);
        try w.writeAll("\n");
    }

    if (cmd.examples.len > 0) {
        try w.writeAll(".SH EXAMPLES\n");
        for (cmd.examples) |example| {
            try w.writeAll(".TP\n\\fB");
            try writeRoffEscaped(w, example);
            try w.writeAll("\\fR\n");
        }
    }

    try w.writeAll(".SH OPTIONS\n");
    for (cmd.flags) |*flag| {
        try w.writeAll(".TP\n");
        if (flag.short) |s| {
            // Only printable ASCII may be emitted raw (R2-02 / CWE-150)
            if (std.ascii.isPrint(s)) try w.print("\\fB\\-{c}\\fR, ", .{s});
        }
        try w.writeAll("\\fB\\-\\-");
        try writeRoffEscaped(w, flag.name);
        try w.writeAll("\\fR\n");
        try writeRoffEscaped(w, flag.help);
        try w.writeAll("\n");
    }

    if (cmd.subcommands.len > 0) {
        try w.writeAll(".SH COMMANDS\n");
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                try w.writeAll(".TP\n\\fB");
                try writeRoffEscaped(w, subcmd.name);
                try w.writeAll("\\fR\n");
                try writeRoffEscaped(w, subcmd.summary);
                try w.writeAll("\n");
            }
        }
    }

    // AUTHOR section: use explicit author if set, otherwise fall back to the
    // command name (a common man-page convention for generated pages).
    const author = if (cmd.author.len > 0) cmd.author else cmd.name;
    try w.writeAll(".SH AUTHOR\n");
    try writeRoffEscaped(w, author);
    try w.writeAll("\n");

    return buf.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "writeRoffEscaped escapes special chars" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeRoffEscaped(w, "hello-world");
    try std.testing.expectEqualStrings("hello\\-world", buf.written());

    buf.clearRetainingCapacity();
    try writeRoffEscaped(w, "path\\to");
    try std.testing.expectEqualStrings("path\\\\to", buf.written());

    buf.clearRetainingCapacity();
    try writeRoffEscaped(w, ".TH inject");
    try std.testing.expectEqualStrings("\\&.TH inject", buf.written());

    buf.clearRetainingCapacity();
    try writeRoffEscaped(w, "'comment");
    try std.testing.expectEqualStrings("\\&'comment", buf.written());

    buf.clearRetainingCapacity();
    try writeRoffEscaped(w, "normal text");
    try std.testing.expectEqualStrings("normal text", buf.written());
}

test "writeRoffEscaped escapes dot after newline to prevent injection" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeRoffEscaped(w, "line1\n.system echo pwned");
    try std.testing.expectEqualStrings("line1\n\\&.system echo pwned", buf.written());

    buf.clearRetainingCapacity();
    try writeRoffEscaped(w, "line1\n'comment injection");
    try std.testing.expectEqualStrings("line1\n\\&'comment injection", buf.written());
}

test "generateMan" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
        .long_help = "This is a test command.",
        .examples = &.{"test --help"},
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".TH test 1") != null);
    try std.testing.expect(mem.indexOf(u8, man, "Test command") != null);
}

test "help: generateMan with name section" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".TH myapp 1") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH NAME") != null);
    try std.testing.expect(mem.indexOf(u8, man, "myapp \\- My application") != null);
}

test "help: generateMan with synopsis" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH SYNOPSIS") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".B myapp") != null);
    try std.testing.expect(mem.indexOf(u8, man, "[\\fIOPTIONS\\fR]") != null);
}

test "help: generateMan with subcommands" {
    const subcmd1 = Command{
        .name = "start",
        .summary = "Start the service",
    };
    const subcmd2 = Command{
        .name = "stop",
        .summary = "Stop the service",
    };
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .subcommands = &.{ &subcmd1, &subcmd2 },
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH COMMANDS") != null);
    try std.testing.expect(mem.indexOf(u8, man, "\\fBstart\\fR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "\\fBstop\\fR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "Start the service") != null);
    try std.testing.expect(mem.indexOf(u8, man, "Stop the service") != null);
}

test "help: generateMan with hidden subcommands" {
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

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, "visible") != null);
    try std.testing.expect(mem.indexOf(u8, man, "hidden") == null);
}

test "help: generateMan with flags" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "output",
                .short = 'o',
                .help = "Output file path",
                .ftype = .path,
            },
            FlagSpec{
                .name = "verbose",
                .help = "Enable verbose output",
                .ftype = .bool,
            },
        },
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH OPTIONS") != null);
    try std.testing.expect(mem.indexOf(u8, man, "\\fB\\-o\\fR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "\\fB\\-\\-output\\fR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "\\fB\\-\\-verbose\\fR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "Output file path") != null);
}

test "help: generateMan with examples" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .examples = &.{
            "myapp start --config app.toml",
            "myapp stop --force",
            "myapp status",
        },
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH EXAMPLES") != null);
    // Dashes are roff-escaped to \-
    try std.testing.expect(mem.indexOf(u8, man, "myapp start \\-\\-config app.toml") != null);
    try std.testing.expect(mem.indexOf(u8, man, "myapp stop \\-\\-force") != null);
    try std.testing.expect(mem.indexOf(u8, man, "myapp status") != null);
}

test "help: generateMan with description" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .long_help = "This is a detailed description of the application.\nIt spans multiple lines.",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH DESCRIPTION") != null);
    try std.testing.expect(mem.indexOf(u8, man, "This is a detailed description") != null);
}

test "help: generateMan includes author section when set" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .author = "DevNW",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH AUTHOR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "DevNW") != null);
}

test "help: generateMan falls back to command name when author not set" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, ".SH AUTHOR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "myapp") != null);
}

test "help: generateMan with subcommands shows COMMAND in synopsis" {
    const subcmd = Command{
        .name = "run",
        .summary = "Run command",
    };
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .subcommands = &.{&subcmd},
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, "<\\fICOMMAND\\fR>") != null);
    try std.testing.expect(mem.indexOf(u8, man, "[\\fIARGS\\fR]") != null);
}

test "help: generateMan complete real-world example" {
    const subcmd1 = Command{
        .name = "serve",
        .summary = "Start the HTTP server",
    };
    const subcmd2 = Command{
        .name = "build",
        .summary = "Build the project",
    };
    const cmd = Command{
        .name = "webapp",
        .summary = "Web application toolkit",
        .long_help = "A comprehensive toolkit for building and deploying web applications.",
        .examples = &.{
            "webapp serve --port 8080",
            "webapp build --release",
        },
        .subcommands = &.{ &subcmd1, &subcmd2 },
        .flags = &.{
            FlagSpec{
                .name = "config",
                .short = 'c',
                .help = "Configuration file",
                .ftype = .path,
            },
        },
        .author = "Webapp Team",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    // Check all major sections
    try std.testing.expect(mem.indexOf(u8, man, ".TH webapp 1") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH NAME") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH SYNOPSIS") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH DESCRIPTION") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH EXAMPLES") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH OPTIONS") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH COMMANDS") != null);
    try std.testing.expect(mem.indexOf(u8, man, ".SH AUTHOR") != null);
    try std.testing.expect(mem.indexOf(u8, man, "Webapp Team") != null);
}
