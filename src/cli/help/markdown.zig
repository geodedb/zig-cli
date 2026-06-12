// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: Markdown Documentation Generation
//!
//! Markdown output for the help subsystem: `generateMarkdown` and the
//! injection-safe escaping helpers for headings, prose, table cells, and
//! code fences.

const std = @import("std");
const mem = std.mem;

const sanitize = @import("sanitize");
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
/// Terminal control bytes (sanitize.isTerminalControl) are stripped as
/// defense-in-depth against ANSI/OSC injection (NS-056 policy).
// pub for markdown_test.zig (file-size split); internal to the help subsystem.
pub fn writeMarkdownEscaped(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '|' => "\\|",
            '`' => "\\`",
            '<' => "&lt;",
            '>' => "&gt;",
            '\n' => "<br>",
            '\r' => "",
            else => if (sanitize.isTerminalControl(c)) "" else null,
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
/// Terminal control bytes (sanitize.isTerminalControl) are stripped.
/// Headings must be single-line.
pub fn writeMarkdownHeading(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '<' => "&lt;",
            '>' => "&gt;",
            '`' => "\\`",
            '\n' => " ",
            '\r' => "",
            else => if (sanitize.isTerminalControl(c)) "" else null,
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
/// Terminal control bytes (sanitize.isTerminalControl) are stripped without
/// consuming the line-start state, so a stripped byte cannot mask a
/// line-leading `#`.
pub fn writeMarkdownProse(w: anytype, s: []const u8) !void {
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
            else => {
                if (sanitize.isTerminalControl(c)) continue;
                try w.writeByte(c);
            },
        }
        at_line_start = false;
    }
}

/// Returns true if `line` would render as a fence delimiter once terminal
/// control bytes have been stripped: i.e. after skipping leading
/// whitespace and stripped control bytes, three backticks follow
/// (control bytes interleaved between the backticks are also skipped,
/// because they disappear from the output).
fn lineOpensFence(line: []const u8) bool {
    var i: usize = 0;
    while (i < line.len and
        (line[i] == ' ' or line[i] == '\t' or sanitize.isTerminalControl(line[i]))) : (i += 1)
    {}
    var ticks: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '`') {
            ticks += 1;
            if (ticks >= 3) return true;
        } else if (!sanitize.isTerminalControl(line[i])) {
            break;
        }
    }
    return false;
}

/// Write content inside a code fence, prefixing any fence-delimiter line
/// with FOUR spaces so it cannot close the fence: CommonMark allows closing
/// fences indented up to 3 spaces, so a single space is not enough — at
/// >= 4 spaces of indentation the line is literal text inside the fence.
/// Terminal control bytes (sanitize.isTerminalControl, which includes \r)
/// are stripped from every line as defense-in-depth (NS-056 policy), and
/// the fence check accounts for stripped bytes so e.g. "\x1b```" cannot
/// turn into a bare ``` after filtering.
pub fn writeFenceSafe(w: anytype, s: []const u8) !void {
    var lines = std.mem.splitScalar(u8, s, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try w.writeAll("\n");
        first = false;
        if (lineOpensFence(line)) {
            try w.writeAll("    ");
        }
        try sanitize.writeControlFiltered(w, line);
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
                // Only printable ASCII may be emitted raw (R2-02 / CWE-150)
                if (std.ascii.isPrint(s)) try w.print("`-{c}`, ", .{s});
            }
            try w.writeAll("`--");
            try writeMarkdownEscaped(w, flag.name);
            try w.writeAll("` | ");
            try writeMarkdownEscaped(w, flag.help);
            if (flag.required) {
                try w.print(" **(required)**", .{});
            }
            if (flag.is_deprecated) {
                try w.print(" **(deprecated)**", .{});
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
