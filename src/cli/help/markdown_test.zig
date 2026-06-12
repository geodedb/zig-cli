// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Tests for the Markdown help generator: `generateMarkdown` and the
//! injection-safe escaping helpers (`writeMarkdownEscaped`,
//! `writeMarkdownHeading`, `writeMarkdownProse`, `writeFenceSafe`).
//! Extracted from markdown.zig to satisfy the 800-line file-size gate
//! (GAP-0096); follows the bash_test.zig / zsh_test.zig precedent.

const std = @import("std");
const mem = std.mem;

const markdown = @import("markdown.zig");
const generateMarkdown = markdown.generateMarkdown;
const writeMarkdownEscaped = markdown.writeMarkdownEscaped;
const writeMarkdownHeading = markdown.writeMarkdownHeading;
const writeMarkdownProse = markdown.writeMarkdownProse;
const writeFenceSafe = markdown.writeFenceSafe;

const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

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

test "help: generateMarkdown non-printable short flag byte is not emitted (R2-02)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "evil",
                .short = 0x1b, // ESC — a non-printable byte
                .help = "should not emit ESC",
                .ftype = .bool,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOfScalar(u8, md, 0x1b) == null);
    try std.testing.expect(mem.indexOf(u8, md, "`--evil`") != null);
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

/// Test helper: returns true if any line in `s` could close a CommonMark
/// fence — i.e. starts with ``` after at most 3 leading spaces.
fn anyLineClosesFence(s: []const u8) bool {
    var lines = std.mem.splitScalar(u8, s, '\n');
    while (lines.next()) |line| {
        var leading: usize = 0;
        while (leading < line.len and line[leading] == ' ') leading += 1;
        if (leading <= 3 and mem.startsWith(u8, line[leading..], "```")) return true;
    }
    return false;
}

test "help: writeFenceSafe blocks fence breakout" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeFenceSafe(w, "a\n```\nevil");
    const result = buf.written();
    // No line inside the emitted fence may have ``` with <= 3 leading
    // spaces — CommonMark allows closing fences indented up to 3 spaces.
    try std.testing.expect(!anyLineClosesFence(result));
    try std.testing.expect(mem.indexOf(u8, result, "\n    ```\n") != null);
}

test "help: writeFenceSafe blocks 1-3 space indented fence (iter-3 finding 12)" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    // CommonMark closing fences may be indented up to 3 spaces, so a single
    // prepended space is NOT enough — " ```" still closes the outer fence.
    try writeFenceSafe(w, "a\n ```\nb\n  ```\nc\n   ```\nevil");
    const result = buf.written();
    try std.testing.expect(!anyLineClosesFence(result));
}

test "help: writeFenceSafe strips control bytes and still guards fences (iter-3 finding 15)" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    // The ESC byte is stripped on output, so the fence check must treat
    // "\x1b```" as a fence-opening line — otherwise stripping would
    // produce a bare ``` that closes the outer fence.
    try writeFenceSafe(w, "a\n\x1b```\nevil");
    const result = buf.written();
    try std.testing.expect(mem.indexOfScalar(u8, result, 0x1b) == null);
    try std.testing.expect(!anyLineClosesFence(result));
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

test "help: generateMarkdown deprecated flag shows (deprecated) (iter-3 finding 13)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "legacy",
                .help = "Old flag",
                .ftype = .bool,
                .is_deprecated = true,
            },
            FlagSpec{
                .name = "fresh",
                .help = "New flag",
                .ftype = .bool,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOf(u8, md, "Old flag **(deprecated)**") != null);
    try std.testing.expect(mem.indexOf(u8, md, "New flag **(deprecated)**") == null);
}

test "help: generateMarkdown strips terminal control bytes (iter-3 finding 15)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "evil\x1b[31m summary\x07",
        .long_help = "desc\x1b]0;owned\x07 text",
        .flags = &.{
            FlagSpec{
                .name = "flag",
                .help = "help\x1b[2J text",
                .ftype = .bool,
            },
        },
    };

    const md = try generateMarkdown(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(md);

    try std.testing.expect(mem.indexOfScalar(u8, md, 0x1b) == null);
    try std.testing.expect(mem.indexOfScalar(u8, md, 0x07) == null);
    try std.testing.expect(mem.indexOf(u8, md, "evil[31m summary") != null);
}

test "help: writeMarkdownEscaped strips ESC" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownEscaped(w, "a\x1b[31mb");
    try std.testing.expectEqualStrings("a[31mb", buf.written());
}

test "help: writeMarkdownHeading strips ESC" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    try writeMarkdownHeading(w, "a\x1b[31mb");
    try std.testing.expectEqualStrings("a[31mb", buf.written());
}

test "help: writeMarkdownProse strips ESC and keeps line-start hash guard" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    // The stripped ESC must not consume the line-start state: the # after
    // it is still at the start of the line and must be neutralised.
    try writeMarkdownProse(w, "x\n\x1b# fake");
    try std.testing.expectEqualStrings("x\n\\# fake", buf.written());
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
