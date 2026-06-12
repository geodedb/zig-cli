// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: Markdown Documentation Generation
//!
//! Markdown output for the help subsystem: `generateMarkdown` and the
//! injection-safe escaping helpers for headings, prose, table cells, and
//! code fences.

const std = @import("std");
const mem = std.mem;

const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

// Group-collection helper lives in common.zig (shared within the help subsystem).
const collectUniqueGroups = @import("common.zig").collectUniqueGroups;

/// Generate Markdown documentation for a command tree
pub fn generateMarkdown(cmd: *const Command, allocator: std.mem.Allocator) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    errdefer buf.deinit();
    buf.ensureUnusedCapacity(4096) catch {};
    const w = &buf.writer;

    try generateMarkdownCommand(w, cmd, 1);

    return buf.toOwnedSlice();
}

/// Write a string to `w` with characters escaped for Markdown table cells.
/// Escapes: `|` -> `\|`, `` ` `` -> `` \` ``, `<` -> `&lt;`, `>` -> `&gt;`,
/// `\n` -> `<br>` (raw newline would terminate the table row), `\r` removed.
fn writeMarkdownEscaped(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '|' => "\\|",
            '`' => "\\`",
            '<' => "&lt;",
            '>' => "&gt;",
            '\n' => "<br>",
            '\r' => "",
            else => null,
        };
        if (esc) |escape_seq| {
            if (idx > start) try w.writeAll(s[start..idx]);
            try w.writeAll(escape_seq);
            start = idx + 1;
        }
    }
    if (start < s.len) {
        try w.writeAll(s[start..]);
    }
}

/// Write a string to `w` escaped for Markdown headings / inline text.
/// HTML-escapes angle brackets, escapes backticks, collapses `\n` to a
/// single space, and discards `\r` (so CRLF produces exactly one space).
/// Headings must be single-line.
fn writeMarkdownHeading(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '<' => "&lt;",
            '>' => "&gt;",
            '`' => "\\`",
            '\n' => " ",
            '\r' => "",
            else => null,
        };
        if (esc) |escape_seq| {
            if (idx > start) try w.writeAll(s[start..idx]);
            try w.writeAll(escape_seq);
            start = idx + 1;
        }
    }
    if (start < s.len) try w.writeAll(s[start..]);
}

/// Write a string to `w` escaped for Markdown prose blocks.
/// HTML-escapes angle brackets and neutralises line-leading `#` so injected
/// text cannot create headings.  `\r` is discarded (does not affect
/// `at_line_start`) so CRLF line endings are handled correctly.
fn writeMarkdownProse(w: anytype, s: []const u8) !void {
    var at_line_start = true;
    for (s) |c| {
        if (at_line_start and c == '#') {
            try w.writeAll("\\#");
            at_line_start = false;
            continue;
        }
        switch (c) {
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '\n' => {
                try w.writeAll("\n");
                at_line_start = true;
                continue;
            },
            '\r' => continue,
            else => try w.writeByte(c),
        }
        at_line_start = false;
    }
}

/// Write content inside a code fence, prefixing any line that starts with
/// ``` (after optional indentation) with a space so it cannot close the fence.
/// Trailing `\r` on each line (from CRLF input) is stripped before writing.
fn writeFenceSafe(w: anytype, s: []const u8) !void {
    var lines = std.mem.splitScalar(u8, s, '\n');
    var first = true;
    while (lines.next()) |raw_line| {
        if (!first) try w.writeAll("\n");
        first = false;
        // Strip trailing CR so CRLF input does not embed \r in fence content.
        const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r')
            raw_line[0 .. raw_line.len - 1]
        else
            raw_line;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "```")) {
            try w.writeAll(" ");
        }
        try w.writeAll(line);
    }
}

fn generateMarkdownCommand(w: anytype, cmd: *const Command, depth: usize) !void {
    // Header (depth determines heading level)
    for (0..depth) |_| {
        try w.writeAll("#");
    }
    try w.writeAll(" ");
    try writeMarkdownHeading(w, cmd.name);
    try w.writeAll("\n\n");

    // Summary
    try writeMarkdownProse(w, cmd.summary);
    try w.writeAll("\n\n");

    // Synopsis
    try w.print("## Synopsis\n\n", .{});
    try w.writeAll("```\n");
    try writeFenceSafe(w, cmd.name);
    try w.writeAll(" [OPTIONS]");
    if (cmd.hasSubcommands()) {
        try w.writeAll(" <COMMAND> [ARGS]");
    }
    try w.writeAll("\n```\n\n");

    // Description
    if (cmd.long_help.len > 0) {
        try w.print("## Description\n\n", .{});
        try writeMarkdownProse(w, cmd.long_help);
        try w.writeAll("\n\n");
    }

    // Examples
    if (cmd.examples.len > 0) {
        try w.print("## Examples\n\n", .{});
        for (cmd.examples) |example| {
            try w.writeAll("```bash\n");
            try writeFenceSafe(w, example);
            try w.writeAll("\n```\n\n");
        }
    }

    // Options
    if (cmd.flags.len > 0) {
        try w.print("## Options\n\n", .{});
        try w.print("| Flag | Description | Default | Env Var |\n", .{});
        try w.print("|------|-------------|---------|--------|\n", .{});
        for (cmd.flags) |*flag| {
            try w.print("| ", .{});
            if (flag.short) |s| {
                try w.print("`-{c}`, ", .{s});
            }
            try w.writeAll("`--");
            try writeMarkdownEscaped(w, flag.name);
            try w.writeAll("` | ");
            try writeMarkdownEscaped(w, flag.help);
            if (flag.required) {
                try w.print(" **(required)**", .{});
            }
            try w.print(" | ", .{});
            if (flag.default_str) |def| {
                try w.writeAll("`");
                try writeMarkdownEscaped(w, def);
                try w.writeAll("`");
            } else {
                try w.print("-", .{});
            }
            try w.print(" | ", .{});
            if (flag.env) |env_var| {
                try w.writeAll("`$");
                try writeMarkdownEscaped(w, env_var);
                try w.writeAll("`");
            } else {
                try w.print("-", .{});
            }
            try w.print(" |\n", .{});
        }
        try w.print("\n", .{});
    }

    // Subcommands
    if (cmd.subcommands.len > 0) {
        try w.print("## Commands\n\n", .{});

        var groups: [32][]const u8 = undefined;
        const group_count = collectUniqueGroups(cmd.subcommands, &groups);

        // Print commands by group
        for (groups[0..group_count]) |group_name| {
            if (group_name.len > 0) {
                try w.writeAll("### ");
                try writeMarkdownHeading(w, group_name);
                try w.writeAll("\n\n");
            }

            try w.print("| Command | Description |\n", .{});
            try w.print("|---------|-------------|\n", .{});

            for (cmd.subcommands) |subcmd| {
                if (subcmd.hidden) continue;
                if (!mem.eql(u8, subcmd.group, group_name)) continue;
                try w.writeAll("| `");
                try writeMarkdownEscaped(w, subcmd.name);
                try w.writeAll("` | ");
                try writeMarkdownEscaped(w, subcmd.summary);
                try w.writeAll(" |\n");
            }
            try w.print("\n", .{});
        }

        // Recursively generate docs for subcommands
        try w.print("---\n\n", .{});
        for (cmd.subcommands) |subcmd| {
            if (!subcmd.hidden) {
                try generateMarkdownCommand(w, subcmd, depth + 1);
            }
        }
    }
}

// ============================================================================
// Markdown Generation Tests
// ============================================================================

test "help: generateMarkdown basic" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "# myapp") != null);
    try std.testing.expect(mem.indexOf(u8, md, "My application") != null);
    try std.testing.expect(mem.indexOf(u8, md, "## Synopsis") != null);
}

test "help: generateMarkdown with description" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .long_help = "This is a detailed description.",
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "## Description") != null);
    try std.testing.expect(mem.indexOf(u8, md, "This is a detailed description") != null);
}

test "help: generateMarkdown with examples" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .examples = &.{
            "myapp start",
            "myapp stop",
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "## Examples") != null);
    try std.testing.expect(mem.indexOf(u8, md, "```bash") != null);
    try std.testing.expect(mem.indexOf(u8, md, "myapp start") != null);
    try std.testing.expect(mem.indexOf(u8, md, "myapp stop") != null);
}

test "help: generateMarkdown with options table" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .short = 'c',
                .help = "Config file",
                .ftype = .path,
            },
            FlagSpec{
                .name = "verbose",
                .help = "Verbose output",
                .ftype = .bool,
                .required = true,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "## Options") != null);
    try std.testing.expect(mem.indexOf(u8, md, "| Flag | Description | Default |") != null);
    try std.testing.expect(mem.indexOf(u8, md, "`-c`") != null);
    try std.testing.expect(mem.indexOf(u8, md, "`--config`") != null);
    try std.testing.expect(mem.indexOf(u8, md, "**(required)**") != null);
}

test "help: generateMarkdown with subcommands" {
    const subcmd1 = Command{
        .name = "start",
        .summary = "Start the service",
    };
    const subcmd2 = Command{
        .name = "stop",
        .summary = "Stop the service",
    };
    const cmd = Command{
        .name = "service",
        .summary = "Service manager",
        .subcommands = &.{ &subcmd1, &subcmd2 },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "## Commands") != null);
    try std.testing.expect(mem.indexOf(u8, md, "| Command | Description |") != null);
    try std.testing.expect(mem.indexOf(u8, md, "| `start` | Start the service |") != null);
    try std.testing.expect(mem.indexOf(u8, md, "| `stop` | Stop the service |") != null);
    // Subcommand sections
    try std.testing.expect(mem.indexOf(u8, md, "## start") != null);
    try std.testing.expect(mem.indexOf(u8, md, "## stop") != null);
}

test "help: generateMarkdown with command groups" {
    const subcmd1 = Command{
        .name = "start",
        .summary = "Start the service",
        .group = "Lifecycle",
    };
    const subcmd2 = Command{
        .name = "stop",
        .summary = "Stop the service",
        .group = "Lifecycle",
    };
    const subcmd3 = Command{
        .name = "logs",
        .summary = "View logs",
        .group = "Debugging",
    };
    const cmd = Command{
        .name = "service",
        .summary = "Service manager",
        .subcommands = &.{ &subcmd1, &subcmd2, &subcmd3 },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "### Lifecycle") != null);
    try std.testing.expect(mem.indexOf(u8, md, "### Debugging") != null);
}

test "help: generateMarkdown hides hidden commands" {
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

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "| `visible`") != null);
    try std.testing.expect(mem.indexOf(u8, md, "| `hidden`") == null);
}

// ============================================================================
// Command Groups Tests (in help output)
// ============================================================================

test "help: command groups ordering" {
    const subcmd1 = Command{
        .name = "build",
        .summary = "Build project",
        .group = "Development",
    };
    const subcmd2 = Command{
        .name = "test",
        .summary = "Run tests",
        .group = "Development",
    };
    const subcmd3 = Command{
        .name = "deploy",
        .summary = "Deploy to production",
        .group = "Operations",
    };
    const subcmd4 = Command{
        .name = "version",
        .summary = "Show version",
    };
    const cmd = Command{
        .name = "app",
        .summary = "Application toolkit",
        .subcommands = &.{ &subcmd1, &subcmd2, &subcmd3, &subcmd4 },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    // Check groups are present
    try std.testing.expect(mem.indexOf(u8, md, "### Development") != null);
    try std.testing.expect(mem.indexOf(u8, md, "### Operations") != null);
    // Ungrouped commands should not have a group header
    try std.testing.expect(mem.indexOf(u8, md, "| `version`") != null);
}

// ============================================================================
// Environment Variable Documentation Tests
// ============================================================================

test "help: generateMarkdown with env vars" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .path,
                .env = "MYAPP_CONFIG",
            },
            FlagSpec{
                .name = "verbose",
                .help = "Verbose output",
                .ftype = .bool,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    // Should have Env Var column
    try std.testing.expect(mem.indexOf(u8, md, "| Env Var |") != null);
    // Should show env var for config
    try std.testing.expect(mem.indexOf(u8, md, "`$MYAPP_CONFIG`") != null);
}

test "help: env vars shown with dash when not set" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "verbose",
                .help = "Verbose output",
                .ftype = .bool,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    // Count occurrences of " - |" (dash in last column)
    var count: usize = 0;
    var i: usize = 0;
    while (i < md.len - 3) : (i += 1) {
        if (mem.eql(u8, md[i .. i + 4], " - |")) {
            count += 1;
        }
    }
    // Should have at least one flag with no env var
    try std.testing.expect(count >= 1);
}

test "help: writeMarkdownEscaped escapes pipe in table cells" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "a|b|c");
    const result = buf.written();
    try std.testing.expectEqualStrings("a\\|b\\|c", result);
}

test "help: writeMarkdownEscaped no special chars" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "hello world");
    try std.testing.expectEqualStrings("hello world", buf.written());
}

test "help: writeMarkdownEscaped escapes backticks" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "use `code` here");
    try std.testing.expectEqualStrings("use \\`code\\` here", buf.written());
}

test "help: writeMarkdownEscaped escapes angle brackets" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "<script>alert('xss')</script>");
    try std.testing.expectEqualStrings("&lt;script&gt;alert('xss')&lt;/script&gt;", buf.written());
}

test "help: writeMarkdownEscaped mixed special chars" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "a|b`c<d>e");
    try std.testing.expectEqualStrings("a\\|b\\`c&lt;d&gt;e", buf.written());
}

test "help: writeMarkdownEscaped newline becomes br" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "line1\nline2");
    try std.testing.expectEqualStrings("line1<br>line2", buf.written());
}

test "help: writeMarkdownEscaped cr is removed" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "a\r\nb");
    try std.testing.expectEqualStrings("a<br>b", buf.written());
}

test "help: writeMarkdownHeading escapes angle brackets" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownHeading(w, "x<script>alert(1)</script>");
    const result = buf.written();
    try std.testing.expect(mem.indexOf(u8, result, "<script>") == null);
    try std.testing.expect(mem.indexOf(u8, result, "&lt;script&gt;") != null);
}

test "help: writeMarkdownHeading collapses newlines to spaces" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownHeading(w, "foo\nbar\r\nbaz");
    try std.testing.expectEqualStrings("foo bar baz", buf.written());
}

test "help: writeMarkdownProse escapes angle brackets" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownProse(w, "<img src=x onerror=1>");
    try std.testing.expectEqualStrings("&lt;img src=x onerror=1&gt;", buf.written());
}

test "help: writeMarkdownProse neutralises line-leading hash" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownProse(w, "# fake heading\nnormal line");
    const result = buf.written();
    // Line-leading # must be escaped so it doesn't become a heading
    try std.testing.expect(mem.indexOf(u8, result, "\n# fake") == null);
    try std.testing.expect(mem.indexOf(u8, result, "\\# fake heading") != null);
}

test "help: writeMarkdownProse discards lone CR" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownProse(w, "foo\rbar");
    try std.testing.expectEqualStrings("foobar", buf.written());
}

test "help: writeFenceSafe blocks fence breakout" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeFenceSafe(w, "a\n```\nevil");
    const result = buf.written();
    // The ``` line must be prefixed with a space so it cannot close the outer fence
    try std.testing.expect(mem.indexOf(u8, result, "\n```\n") == null);
    try std.testing.expect(mem.indexOf(u8, result, "\n ```\n") != null);
}

test "help: generateMarkdown headings and prose are escaped" {
    const cmd = Command{
        .name = "x<script>",
        .summary = "<img src=x onerror=1>",
        .long_help = "# fake heading\n<b>bold</b>",
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    // The heading line must not contain a raw angle bracket — it would render as HTML
    // when Markdown is converted to HTML. The synopsis code-fence is safe (code
    // fences are not parsed as HTML), so we only check the heading line itself.
    const heading_end = mem.indexOf(u8, md, "\n\n") orelse md.len;
    const heading_line = md[0..heading_end];
    try std.testing.expect(mem.indexOf(u8, heading_line, "<script>") == null);
    try std.testing.expect(mem.indexOf(u8, heading_line, "&lt;script&gt;") != null);

    // Summary prose must have angle brackets escaped
    try std.testing.expect(mem.indexOf(u8, md, "<img") == null);
    try std.testing.expect(mem.indexOf(u8, md, "&lt;img") != null);

    // Heading injection via long_help: "\n# fake" must not appear
    try std.testing.expect(mem.indexOf(u8, md, "\n# fake") == null);
}

test "help: generateMarkdown fence breakout blocked" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .examples = &.{"a\n```\nevil"},
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    // The ``` line inside the example must not appear unescaped — it would close
    // the outer ```bash fence if emitted raw.
    try std.testing.expect(mem.indexOf(u8, md, "\n```\nevil") == null);
}

test "help: generateMarkdown cell newline becomes br" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "flag",
                .help = "line1\nline2",
                .ftype = .bool,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "line1<br>line2") != null);
}
