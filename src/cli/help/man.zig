// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: Man Page Generation
//!
//! Roff (man page) output for the help subsystem: `generateMan` and the
//! injection-safe `writeRoffEscaped` escaper.

const std = @import("std");
const mem = std.mem;

const sanitize = @import("sanitize");
const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

/// Write a roff-escaped version of a user string.
/// Escapes: `\` -> `\\`, `-` -> `\-`, leading `.` -> `\&.`, leading `'` -> `\&'`.
/// After newlines, `.` and `'` at the start of a new line are also escaped
/// to prevent roff command injection.
/// Terminal control bytes (sanitize.isTerminalControl; \n is kept — man
/// content is multi-line) are stripped as defense-in-depth against
/// ANSI/OSC injection (NS-056 policy). Stripping does not consume the
/// line-start state, so a stripped byte cannot mask a line-leading `.`.
///
/// Uses span-based flushing: accumulates runs of clean characters and writes
/// them in a single writeAll call, avoiding per-byte writeByte overhead.
pub fn writeRoffEscaped(w: anytype, s: []const u8) !void {
    var at_line_start = true;
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        if (sanitize.isTerminalControl(c)) {
            // Strip: flush the clean span, skip the byte, and leave
            // at_line_start untouched.
            if (idx > start) {
                try w.writeAll(s[start..idx]);
            }
            start = idx + 1;
            continue;
        }
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
            // A short flag is conventionally a single alphanumeric character.
            // Restricting to alphanumeric keeps the last raw `{c}` metadata
            // emission consistent with the shell generators (F7-01); if skipped,
            // the entry shows only the long form (`\-\-name`), which is correct.
            if (std.ascii.isAlphanumeric(s)) try w.print("\\fB\\-{c}\\fR, ", .{s});
        }
        try w.writeAll("\\fB\\-\\-");
        try writeRoffEscaped(w, flag.name);
        try w.writeAll("\\fR\n");
        try writeRoffEscaped(w, flag.help);
        if (flag.required) {
            try w.writeAll(" (required)");
        }
        if (flag.default_str) |def| {
            try w.writeAll(" (default: ");
            try writeRoffEscaped(w, def);
            try w.writeAll(")");
        }
        if (flag.env) |env_var| {
            try w.writeAll(" (env: $");
            try writeRoffEscaped(w, env_var);
            try w.writeAll(")");
        }
        if (flag.is_deprecated) {
            try w.writeAll(" (deprecated)");
        }
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

test "help: generateMan printable-but-non-alphanumeric short flag is dropped (F7-01)" {
    // A backtick short flag is printable; the old isPrint guard rendered it as
    // `\fB\-`\fR, `. isAlphanumeric drops it; only the long form is shown.
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "name",
                .short = '`',
                .help = "hostile short",
                .ftype = .bool,
            },
        },
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    // No short-flag roff fragment and no stray backtick.
    try std.testing.expect(mem.indexOfScalar(u8, man, '`') == null);
    try std.testing.expect(mem.indexOf(u8, man, "\\fB\\-`\\fR") == null);
    // The long form is still rendered.
    try std.testing.expect(mem.indexOf(u8, man, "\\fB\\-\\-name\\fR") != null);
}

test "help: generateMan alphanumeric short flag still renders (F7-01 positive)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "output",
                .short = 'o',
                .help = "Output",
                .ftype = .path,
            },
        },
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, "\\fB\\-o\\fR, ") != null);
}

test "help: generateMan options show required/default/env/deprecated (iter-3 finding 13)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .path,
                .required = true,
                .default_str = "a\\b",
                .env = "MYAPP_CONFIG",
                .is_deprecated = true,
            },
            FlagSpec{
                .name = "verbose",
                .help = "Verbose output",
                .ftype = .bool,
            },
        },
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOf(u8, man, "(required)") != null);
    // Backslash in the default must be roff-escaped (\ -> \\).
    try std.testing.expect(mem.indexOf(u8, man, "(default: a\\\\b)") != null);
    try std.testing.expect(mem.indexOf(u8, man, "(env: $MYAPP_CONFIG)") != null);
    try std.testing.expect(mem.indexOf(u8, man, "(deprecated)") != null);

    // The plain flag must not pick up any attribute markers.
    const verbose_at = mem.indexOf(u8, man, "Verbose output").?;
    const after_verbose = man[verbose_at..];
    const line_end = mem.indexOfScalar(u8, after_verbose, '\n') orelse after_verbose.len;
    try std.testing.expect(mem.indexOf(u8, after_verbose[0..line_end], "(") == null);
}

test "help: generateMan strips terminal control bytes (iter-3 finding 15)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "evil\x1b[31m summary\x07",
        .long_help = "desc\x1b]0;owned\x07 text",
    };

    const man = try generateMan(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(man);

    try std.testing.expect(mem.indexOfScalar(u8, man, 0x1b) == null);
    try std.testing.expect(mem.indexOfScalar(u8, man, 0x07) == null);
    try std.testing.expect(mem.indexOf(u8, man, "evil[31m summary") != null);
}

test "writeRoffEscaped strips ESC without consuming line-start state" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    // The stripped ESC must not mask the line-leading dot: the roff
    // request guard has to fire on the `.` that follows it.
    try writeRoffEscaped(w, "line1\n\x1b.system echo pwned");
    try std.testing.expectEqualStrings("line1\n\\&.system echo pwned", buf.written());
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
