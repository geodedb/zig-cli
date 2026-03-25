// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help Module
//!
//! Help text generation with examples-first approach and
//! support for concise vs. full help output.
//!
//! ## Custom Templates
//!
//! The help system supports custom templates for formatting help output.
//! Use `HelpTemplate` to customize section order, headers, and rendering.
//!
//! ```zig
//! const template = HelpTemplate{
//!     .sections = &.{ .usage, .examples, .description, .commands, .flags },
//!     .usage_header = "USAGE",
//!     .examples_header = "EXAMPLES",
//!     .show_global_flags = true,
//! };
//! printHelpWithTemplate(cmd, ctx, &template);
//! ```
//!
//! ## Environment Variables Section
//!
//! Enable `show_env_section` and add `.env_vars` to the sections list to
//! display a dedicated "Environment Variables" section in help output.
//! This section collects all flags with `.env` set and optionally lists
//! standard framework env vars (NO_COLOR, TERM).
//!
//! ```zig
//! const template = HelpTemplate{
//!     .sections = &.{ .usage, .flags, .env_vars },
//!     .show_env_section = true,
//! };
//! ```

const std = @import("std");
const mem = std.mem;

const command = @import("command.zig");
const Command = command.Command;
const Context = command.Context;
const FlagSpec = command.FlagSpec;

// ============================================================================
// ANSI escape code constants
// ============================================================================

/// Bold text
const ansi_bold = "\x1b[1m";
/// Reset all attributes
const ansi_reset = "\x1b[0m";
/// Red text (errors, required indicators)
const ansi_red = "\x1b[31m";
/// Yellow text (flags, deprecation warnings)
const ansi_yellow = "\x1b[33m";
/// Cyan text (command names, env vars)
const ansi_cyan = "\x1b[36m";

/// Help section types for template ordering
pub const HelpSection = enum {
    /// Command name and summary
    header,
    /// Usage line showing command syntax
    usage,
    /// Usage examples (examples-first approach)
    examples,
    /// Long description/help text
    description,
    /// List of subcommands
    commands,
    /// List of flags/options
    flags,
    /// Dedicated environment variables reference section
    env_vars,
    /// Footer with additional hints
    footer,
};

/// Custom help template for formatting help output
pub const HelpTemplate = struct {
    /// Order of sections to display (default: header, usage, examples, description, commands, flags, footer)
    sections: []const HelpSection = &.{ .header, .usage, .examples, .description, .commands, .flags, .footer },

    /// Header for usage section
    usage_header: []const u8 = "Usage",
    /// Header for examples section
    examples_header: []const u8 = "Examples",
    /// Header for description section (empty = no header, just content)
    description_header: []const u8 = "",
    /// Header for commands section (supports groups override)
    commands_header: []const u8 = "Commands",
    /// Header for flags section
    flags_header: []const u8 = "Flags",

    /// Header for environment variables section
    env_header: []const u8 = "Environment Variables",

    /// Whether to show global flags (--help, --version, etc.)
    show_global_flags: bool = true,
    /// Whether to show the environment variables section
    show_env_section: bool = false,
    /// Whether to include standard env vars (NO_COLOR, TERM, etc.) in env section
    show_standard_env_vars: bool = true,
    /// Whether to show the footer hint
    show_footer: bool = true,
    /// Custom footer text (null = default)
    footer_text: ?[]const u8 = null,

    /// Indentation for content (number of spaces)
    indent: u8 = 2,
    /// Column width for flag/command names before description
    name_column_width: u8 = 20,

    /// Custom section renderer callback (optional)
    /// If set, this function is called for each section, allowing full customization
    custom_renderer: ?*const fn (*const Command, *Context, HelpSection, *const HelpTemplate) bool = null,

    /// Default template with examples-first approach
    pub const default = HelpTemplate{};

    /// Minimal template (usage and flags only)
    pub const minimal = HelpTemplate{
        .sections = &.{ .usage, .flags },
        .show_global_flags = false,
        .show_footer = false,
    };

    /// Verbose template with all sections and descriptions
    pub const verbose = HelpTemplate{
        .sections = &.{ .header, .usage, .description, .examples, .commands, .flags, .footer },
        .usage_header = "USAGE",
        .examples_header = "EXAMPLES",
        .commands_header = "COMMANDS",
        .flags_header = "OPTIONS",
    };

    /// Man-page style template
    pub const manpage = HelpTemplate{
        .sections = &.{ .header, .usage, .description, .commands, .flags, .examples },
        .usage_header = "SYNOPSIS",
        .examples_header = "EXAMPLES",
        .description_header = "DESCRIPTION",
        .commands_header = "COMMANDS",
        .flags_header = "OPTIONS",
    };
};

/// Print help for a command.
/// Write errors (e.g., broken pipe) are silently ignored for CLI robustness.
pub fn printHelp(cmd: *const Command, ctx: *Context) void {
    printHelpWithTemplate(cmd, ctx, &HelpTemplate.default);
}

/// Print help using a custom template.
/// Write errors (e.g., broken pipe) are silently ignored for CLI robustness.
pub fn printHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) void {
    if (ctx.json) {
        printJsonHelp(cmd, ctx) catch {};
    } else {
        printTextHelpWithTemplate(cmd, ctx, template) catch {};
    }
}

/// Print help, returning errors to callers that want to handle them.
pub fn printHelpReturningError(cmd: *const Command, ctx: *Context) !void {
    return printHelpWithTemplateReturningError(cmd, ctx, &HelpTemplate.default);
}

/// Print help with template, returning errors.
pub fn printHelpWithTemplateReturningError(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) !void {
    if (ctx.json) {
        try printJsonHelp(cmd, ctx);
    } else {
        try printTextHelpWithTemplate(cmd, ctx, template);
    }
}

/// Print text-format help using a template.
/// Renders all sections into a memory buffer first, then writes to stdout
/// in a single call to reduce syscall overhead.
fn printTextHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    buf.ensureTotalCapacity(ctx.allocator, 2048) catch {};
    const w = buf.writer(ctx.allocator);
    const use_color = ctx.useColor();

    for (template.sections) |section| {
        // Check for custom renderer first
        if (template.custom_renderer) |renderer| {
            if (renderer(cmd, ctx, section, template)) {
                continue; // Custom renderer handled this section
            }
        }

        switch (section) {
            .header => try printSectionHeader(w, use_color, cmd),
            .usage => try printSectionUsage(w, cmd, template),
            .examples => try printSectionExamples(w, cmd, template),
            .description => try printSectionDescription(w, cmd, template),
            .commands => try printSectionCommands(w, use_color, cmd, template),
            .flags => try printSectionFlags(w, use_color, cmd, template),
            .env_vars => try printSectionEnvVars(w, use_color, cmd, template),
            .footer => try printSectionFooter(w, cmd, template),
        }
    }

    try ctx.stdout.writeAll(buf.items);
}

/// Print header section (name and summary)
fn printSectionHeader(w: anytype, use_color: bool, cmd: *const Command) !void {
    if (use_color) {
        try w.print(ansi_bold ++ "{s}" ++ ansi_reset, .{cmd.name});
    } else {
        try w.print("{s}", .{cmd.name});
    }
    try w.print(" - {s}\n", .{cmd.summary});
}

/// Print usage section
fn printSectionUsage(w: anytype, cmd: *const Command, template: *const HelpTemplate) !void {
    try w.print("\n{s}: {s} [flags]", .{ template.usage_header, cmd.name });
    if (cmd.hasSubcommands()) {
        try w.print(" <command> [args]", .{});
    }
    try w.print("\n", .{});
}

/// Print examples section
fn printSectionExamples(w: anytype, cmd: *const Command, template: *const HelpTemplate) !void {
    if (cmd.examples.len == 0) return;

    try w.print("\n{s}:\n", .{template.examples_header});
    for (cmd.examples) |example| {
        // Write indent
        try w.writeByteNTimes(' ', template.indent);
        try w.print("{s}\n", .{example});
    }
}

/// Print description section
fn printSectionDescription(w: anytype, cmd: *const Command, template: *const HelpTemplate) !void {
    if (cmd.long_help.len == 0) return;

    if (template.description_header.len > 0) {
        try w.print("\n{s}:\n", .{template.description_header});
    } else {
        try w.print("\n", .{});
    }
    try w.print("{s}\n", .{cmd.long_help});
}

/// Collect unique group names from a command's visible subcommands.
/// Returns the number of unique groups found.
///
/// **Limit:** At most 32 unique groups are tracked. Commands with more
/// than 32 groups will have excess groups silently omitted from output.
fn collectUniqueGroups(subcommands: []const *const Command, groups: *[32][]const u8) usize {
    var count: usize = 0;
    for (subcommands) |subcmd| {
        if (subcmd.hidden) continue;
        var found = false;
        for (groups[0..count]) |g| {
            if (mem.eql(u8, g, subcmd.group)) {
                found = true;
                break;
            }
        }
        if (!found and count < groups.len) {
            groups[count] = subcmd.group;
            count += 1;
        }
    }
    return count;
}

/// Print commands section (with group support)
fn printSectionCommands(w: anytype, use_color: bool, cmd: *const Command, template: *const HelpTemplate) !void {
    if (cmd.subcommands.len == 0) return;

    var groups: [32][]const u8 = undefined;
    const group_count = collectUniqueGroups(cmd.subcommands, &groups);

    // Print commands by group
    for (groups[0..group_count]) |group_name| {
        if (group_name.len > 0) {
            if (use_color) {
                try w.print("\n" ++ ansi_bold ++ "{s}:" ++ ansi_reset ++ "\n", .{group_name});
            } else {
                try w.print("\n{s}:\n", .{group_name});
            }
        } else {
            try w.print("\n{s}:\n", .{template.commands_header});
        }

        for (cmd.subcommands) |subcmd| {
            if (subcmd.hidden) continue;
            if (!std.mem.eql(u8, subcmd.group, group_name)) continue;

            // Write indent
            try w.writeByteNTimes(' ', template.indent);

            if (use_color) {
                try w.print(ansi_cyan ++ "{s}" ++ ansi_reset, .{subcmd.name});
            } else {
                try w.print("{s}", .{subcmd.name});
            }

            // Padding to align descriptions
            const sub_name_len: usize = subcmd.name.len;
            const col_width: usize = @as(usize, template.name_column_width) - template.indent;
            const sub_min_len: usize = @min(sub_name_len, col_width);
            const sub_padding: usize = col_width - sub_min_len;
            try w.writeByteNTimes(' ', sub_padding);
            try w.print("{s}\n", .{subcmd.summary});
        }
    }
}

/// Print flags section
fn printSectionFlags(w: anytype, use_color: bool, cmd: *const Command, template: *const HelpTemplate) !void {
    if (cmd.flags.len == 0 and !template.show_global_flags) return;

    try w.print("\n{s}:\n", .{template.flags_header});

    // Global flags first (if enabled) -- sourced from the canonical definition
    if (template.show_global_flags) {
        for (command.global_flags) |*gflag| {
            try printFlagWithTemplate(w, use_color, template, gflag);
        }
    }

    // Command-specific flags
    for (cmd.flags) |*flag| {
        try printFlagWithTemplate(w, use_color, template, flag);
    }
}

/// Standard environment variables recognized by the CLI framework.
/// Listed when `show_standard_env_vars` is true and `show_env_section` is true.
const standard_env_vars: []const struct { name: []const u8, description: []const u8 } = &.{
    .{ .name = "NO_COLOR", .description = "Disable colored output (any value)" },
    .{ .name = "TERM", .description = "Terminal type (set to \"dumb\" to disable formatting)" },
};

/// Print a dedicated environment variables section.
///
/// Collects all flags (global + command-specific) that have an `.env` field set
/// and lists them. Optionally appends standard framework env vars (NO_COLOR, TERM).
fn printSectionEnvVars(w: anytype, use_color: bool, cmd: *const Command, template: *const HelpTemplate) !void {
    if (!template.show_env_section) return;

    // Count env-backed flags to decide whether to print the section
    var env_count: usize = 0;
    for (command.global_flags) |*gflag| {
        if (gflag.env != null) env_count += 1;
    }
    for (cmd.flags) |*flag| {
        if (flag.env != null) env_count += 1;
    }

    // If there are no env-backed flags and no standard vars to show, skip
    if (env_count == 0 and !template.show_standard_env_vars) return;

    try w.print("\n{s}:\n", .{template.env_header});

    // Flag-sourced env vars
    for (command.global_flags) |*gflag| {
        if (gflag.env) |env_var| {
            try printEnvVarEntry(w, use_color, template, env_var, gflag.help);
        }
    }
    for (cmd.flags) |*flag| {
        if (flag.env) |env_var| {
            try printEnvVarEntry(w, use_color, template, env_var, flag.help);
        }
    }

    // Standard framework env vars
    if (template.show_standard_env_vars) {
        for (standard_env_vars) |entry| {
            try printEnvVarEntry(w, use_color, template, entry.name, entry.description);
        }
    }
}

/// Print a single environment variable entry in the env section.
fn printEnvVarEntry(w: anytype, use_color: bool, template: *const HelpTemplate, name: []const u8, description: []const u8) !void {
    try w.writeByteNTimes(' ', template.indent);

    if (use_color) {
        try w.print(ansi_cyan ++ "{s}" ++ ansi_reset, .{name});
    } else {
        try w.print("{s}", .{name});
    }

    // Padding to align descriptions
    const name_len: usize = name.len;
    const col_width: usize = @as(usize, template.name_column_width) - template.indent;
    const min_len: usize = @min(name_len, col_width);
    const pad: usize = col_width - min_len;
    try w.writeByteNTimes(' ', pad);

    try w.print("{s}\n", .{description});
}

/// Print a single flag with template settings
fn printFlagWithTemplate(w: anytype, use_color: bool, template: *const HelpTemplate, flag: *const FlagSpec) !void {
    // Write indent
    try w.writeByteNTimes(' ', template.indent);

    // Short flag
    if (flag.short) |s| {
        if (use_color) {
            try w.print(ansi_yellow ++ "-{c}" ++ ansi_reset ++ ", ", .{s});
        } else {
            try w.print("-{c}, ", .{s});
        }
    } else {
        try w.print("    ", .{});
    }

    // Long flag
    if (use_color) {
        try w.print(ansi_yellow ++ "--{s}" ++ ansi_reset, .{flag.name});
    } else {
        try w.print("--{s}", .{flag.name});
    }

    // Padding
    const name_len: usize = flag.name.len;
    const col_width: usize = @as(usize, template.name_column_width) - template.indent - 6; // -6 for "  -X, "
    const min_len: usize = @min(name_len, col_width);
    const padding_amount: usize = if (col_width > min_len) col_width - min_len else 0;
    try w.writeByteNTimes(' ', padding_amount);

    // Help text
    try w.print("{s}", .{flag.help});

    // Default value
    if (flag.default_str) |def| {
        try w.print(" [default: {s}]", .{def});
    }

    // Required indicator
    if (flag.required) {
        if (use_color) {
            try w.print(" " ++ ansi_red ++ "(required)" ++ ansi_reset, .{});
        } else {
            try w.print(" (required)", .{});
        }
    }

    // Deprecated indicator
    if (flag.is_deprecated) {
        if (use_color) {
            try w.print(" " ++ ansi_yellow ++ "(deprecated)" ++ ansi_reset, .{});
        } else {
            try w.print(" (deprecated)", .{});
        }
    }

    // Environment variable indicator
    if (flag.env) |env_var| {
        if (use_color) {
            try w.print(" " ++ ansi_cyan ++ "[${s}]" ++ ansi_reset, .{env_var});
        } else {
            try w.print(" [${s}]", .{env_var});
        }
    }

    try w.print("\n", .{});
}

/// Print footer section
fn printSectionFooter(w: anytype, cmd: *const Command, template: *const HelpTemplate) !void {
    if (!template.show_footer) return;

    if (template.footer_text) |footer| {
        try w.print("\n{s}\n", .{footer});
    } else {
        try w.print("\nFor full help: {s} --help\n", .{cmd.name});
    }
}

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
fn printJsonHelp(cmd: *const Command, ctx: *Context) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    buf.ensureTotalCapacity(ctx.allocator, 1024) catch {};
    const w = buf.writer(ctx.allocator);

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

    try ctx.stdout.writeAll(buf.items);
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
        try w.print("\"short\":\"{c}\",", .{s});
    } else {
        try w.print("\"short\":null,", .{});
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
    var list: std.ArrayList(u8) = .empty;
    list.ensureTotalCapacity(allocator, 4096) catch {};
    const w = list.writer(allocator);

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
            try w.print("\\fB\\-{c}\\fR, ", .{s});
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

    return list.toOwnedSlice(allocator);
}

/// Print version information.
/// Write errors (e.g., broken pipe) are silently ignored for CLI robustness.
pub fn printVersion(cmd: *const Command, ctx: *Context) void {
    printVersionImpl(cmd, ctx) catch {};
}

/// Print version, returning errors to callers that want to handle them.
pub fn printVersionReturningError(cmd: *const Command, ctx: *Context) !void {
    try printVersionImpl(cmd, ctx);
}

/// Default version string used when no version is specified on a command.
pub const default_version = "0.0.0";

fn printVersionImpl(cmd: *const Command, ctx: *Context) !void {
    const w = ctx.stdout;
    const version = if (cmd.version.len > 0) cmd.version else default_version;

    if (ctx.json) {
        try w.writeAll("{\"name\":\"");
        try writeJsonEscapedString(w, cmd.name);
        try w.writeAll("\",\"version\":\"");
        try writeJsonEscapedString(w, version);
        try w.writeAll("\"}\n");
    } else {
        try w.print("{s} {s}\n", .{ cmd.name, version });
    }
}

/// Generate Markdown documentation for a command tree
pub fn generateMarkdown(cmd: *const Command, allocator: std.mem.Allocator) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    list.ensureTotalCapacity(allocator, 4096) catch {};
    const w = list.writer(allocator);

    try generateMarkdownCommand(w, cmd, 1);

    return list.toOwnedSlice(allocator);
}

/// Write a string to `w` with characters escaped for Markdown table cells.
/// Escapes: `|` -> `\|`, `` ` `` -> `` \` ``, `<` -> `&lt;`, `>` -> `&gt;`.
fn writeMarkdownEscaped(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '|' => "\\|",
            '`' => "\\`",
            '<' => "&lt;",
            '>' => "&gt;",
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

fn generateMarkdownCommand(w: anytype, cmd: *const Command, depth: usize) !void {
    // Header (depth determines heading level)
    for (0..depth) |_| {
        try w.writeAll("#");
    }
    try w.print(" {s}\n\n", .{cmd.name});

    // Summary
    try w.print("{s}\n\n", .{cmd.summary});

    // Synopsis
    try w.print("## Synopsis\n\n", .{});
    try w.print("```\n{s} [OPTIONS]", .{cmd.name});
    if (cmd.hasSubcommands()) {
        try w.print(" <COMMAND> [ARGS]", .{});
    }
    try w.print("\n```\n\n", .{});

    // Description
    if (cmd.long_help.len > 0) {
        try w.print("## Description\n\n", .{});
        try w.print("{s}\n\n", .{cmd.long_help});
    }

    // Examples
    if (cmd.examples.len > 0) {
        try w.print("## Examples\n\n", .{});
        for (cmd.examples) |example| {
            try w.print("```bash\n{s}\n```\n\n", .{example});
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
                try w.print("### {s}\n\n", .{group_name});
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
// Tests
// ============================================================================

test "writeRoffEscaped escapes special chars" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeRoffEscaped(w, "hello-world");
    try std.testing.expectEqualStrings("hello\\-world", list.items);

    list.clearRetainingCapacity();
    try writeRoffEscaped(w, "path\\to");
    try std.testing.expectEqualStrings("path\\\\to", list.items);

    list.clearRetainingCapacity();
    try writeRoffEscaped(w, ".TH inject");
    try std.testing.expectEqualStrings("\\&.TH inject", list.items);

    list.clearRetainingCapacity();
    try writeRoffEscaped(w, "'comment");
    try std.testing.expectEqualStrings("\\&'comment", list.items);

    list.clearRetainingCapacity();
    try writeRoffEscaped(w, "normal text");
    try std.testing.expectEqualStrings("normal text", list.items);
}

test "writeRoffEscaped escapes dot after newline to prevent injection" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeRoffEscaped(w, "line1\n.system echo pwned");
    try std.testing.expectEqualStrings("line1\n\\&.system echo pwned", list.items);

    list.clearRetainingCapacity();
    try writeRoffEscaped(w, "line1\n'comment injection");
    try std.testing.expectEqualStrings("line1\n\\&'comment injection", list.items);
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
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeMarkdownEscaped(w, "a|b|c");
    const result = list.items;
    try std.testing.expectEqualStrings("a\\|b\\|c", result);
}

test "help: writeMarkdownEscaped no special chars" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeMarkdownEscaped(w, "hello world");
    try std.testing.expectEqualStrings("hello world", list.items);
}

test "help: writeMarkdownEscaped escapes backticks" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeMarkdownEscaped(w, "use `code` here");
    try std.testing.expectEqualStrings("use \\`code\\` here", list.items);
}

test "help: writeMarkdownEscaped escapes angle brackets" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeMarkdownEscaped(w, "<script>alert('xss')</script>");
    try std.testing.expectEqualStrings("&lt;script&gt;alert('xss')&lt;/script&gt;", list.items);
}

test "help: writeMarkdownEscaped mixed special chars" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeMarkdownEscaped(w, "a|b`c<d>e");
    try std.testing.expectEqualStrings("a\\|b\\`c&lt;d&gt;e", list.items);
}

// ============================================================================
// HelpTemplate Tests
// ============================================================================

test "help: HelpTemplate presets exist" {
    // Test that all preset templates are accessible
    const default_t = HelpTemplate.default;
    const minimal_t = HelpTemplate.minimal;
    const verbose_t = HelpTemplate.verbose;
    const manpage_t = HelpTemplate.manpage;

    // Default template has all sections
    try std.testing.expectEqual(@as(usize, 7), default_t.sections.len);

    // Minimal template has fewer sections
    try std.testing.expectEqual(@as(usize, 2), minimal_t.sections.len);
    try std.testing.expect(!minimal_t.show_global_flags);
    try std.testing.expect(!minimal_t.show_footer);

    // Verbose template has uppercase headers
    try std.testing.expect(mem.eql(u8, verbose_t.usage_header, "USAGE"));
    try std.testing.expect(mem.eql(u8, verbose_t.examples_header, "EXAMPLES"));

    // Manpage template uses SYNOPSIS instead of Usage
    try std.testing.expect(mem.eql(u8, manpage_t.usage_header, "SYNOPSIS"));
    try std.testing.expect(mem.eql(u8, manpage_t.description_header, "DESCRIPTION"));
}

test "help: HelpTemplate custom section order" {
    // Test that we can create a custom template with different section order
    const custom = HelpTemplate{
        .sections = &.{ .usage, .flags, .examples }, // Different order
        .show_footer = false,
    };

    try std.testing.expectEqual(@as(usize, 3), custom.sections.len);
    try std.testing.expectEqual(HelpSection.usage, custom.sections[0]);
    try std.testing.expectEqual(HelpSection.flags, custom.sections[1]);
    try std.testing.expectEqual(HelpSection.examples, custom.sections[2]);
}

test "help: HelpTemplate custom headers" {
    const custom = HelpTemplate{
        .usage_header = "HOW TO USE",
        .examples_header = "SAMPLE USAGE",
        .commands_header = "SUBCOMMANDS",
        .flags_header = "OPTIONS",
    };

    try std.testing.expect(mem.eql(u8, custom.usage_header, "HOW TO USE"));
    try std.testing.expect(mem.eql(u8, custom.examples_header, "SAMPLE USAGE"));
    try std.testing.expect(mem.eql(u8, custom.commands_header, "SUBCOMMANDS"));
    try std.testing.expect(mem.eql(u8, custom.flags_header, "OPTIONS"));
}

test "help: HelpTemplate custom footer" {
    const custom = HelpTemplate{
        .footer_text = "Visit https://example.com for more info",
    };

    try std.testing.expect(custom.footer_text != null);
    try std.testing.expect(mem.eql(u8, custom.footer_text.?, "Visit https://example.com for more info"));
}

test "help: HelpTemplate formatting options" {
    const custom = HelpTemplate{
        .indent = 4,
        .name_column_width = 30,
    };

    try std.testing.expectEqual(@as(u8, 4), custom.indent);
    try std.testing.expectEqual(@as(u8, 30), custom.name_column_width);
}

test "help: HelpSection enum values" {
    // Ensure all section types exist
    try std.testing.expectEqual(@as(u4, 0), @intFromEnum(HelpSection.header));
    try std.testing.expectEqual(@as(u4, 1), @intFromEnum(HelpSection.usage));
    try std.testing.expectEqual(@as(u4, 2), @intFromEnum(HelpSection.examples));
    try std.testing.expectEqual(@as(u4, 3), @intFromEnum(HelpSection.description));
    try std.testing.expectEqual(@as(u4, 4), @intFromEnum(HelpSection.commands));
    try std.testing.expectEqual(@as(u4, 5), @intFromEnum(HelpSection.flags));
    try std.testing.expectEqual(@as(u4, 6), @intFromEnum(HelpSection.env_vars));
    try std.testing.expectEqual(@as(u4, 7), @intFromEnum(HelpSection.footer));
}

// ============================================================================
// JSON Escaping Tests
// ============================================================================

test "help: writeJsonEscapedString plain text" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeJsonEscapedString(w, "hello world");
    try std.testing.expectEqualStrings("hello world", list.items);
}

test "help: writeJsonEscapedString with double quote" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeJsonEscapedString(w, "say \"hi\"");
    try std.testing.expectEqualStrings("say \\\"hi\\\"", list.items);
}

test "help: writeJsonEscapedString with backslash" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeJsonEscapedString(w, "path\\to\\file");
    try std.testing.expectEqualStrings("path\\\\to\\\\file", list.items);
}

test "help: writeJsonEscapedString with newline" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeJsonEscapedString(w, "line1\nline2");
    try std.testing.expectEqualStrings("line1\\nline2", list.items);
}

test "help: writeJsonEscapedString with tab and carriage return" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeJsonEscapedString(w, "a\tb\rc");
    try std.testing.expectEqualStrings("a\\tb\\rc", list.items);
}

test "help: writeJsonEscapedString with control char" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    // ASCII 0x01 (SOH)
    try writeJsonEscapedString(w, "\x01");
    try std.testing.expectEqualStrings("\\u0001", list.items);
}

test "help: writeJsonEscapedString empty string" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    try writeJsonEscapedString(w, "");
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

// ============================================================================
// Environment Variables Section Tests (GAP-0054)
// ============================================================================

test "help: env section prints flag-sourced env vars when enabled" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .help = "Config file path",
                .ftype = .path,
                .env = "MYAPP_CONFIG",
            },
            FlagSpec{
                .name = "verbose",
                .help = "Verbose output",
                .ftype = .bool,
            },
            FlagSpec{
                .name = "port",
                .help = "Listen port",
                .ftype = .int,
                .env = "MYAPP_PORT",
            },
        },
    };

    const template = HelpTemplate{
        .show_env_section = true,
        .show_standard_env_vars = false,
    };

    try printSectionEnvVars(w, false, &cmd, &template);
    const output = list.items;

    // Section header
    try std.testing.expect(mem.indexOf(u8, output, "Environment Variables:") != null);
    // Flag-sourced env vars listed
    try std.testing.expect(mem.indexOf(u8, output, "MYAPP_CONFIG") != null);
    try std.testing.expect(mem.indexOf(u8, output, "Config file path") != null);
    try std.testing.expect(mem.indexOf(u8, output, "MYAPP_PORT") != null);
    try std.testing.expect(mem.indexOf(u8, output, "Listen port") != null);
    // verbose has no env, should not appear as an env var entry
    // (it may appear in some other line but not with "Verbose output" as an env entry)
}

test "help: env section includes standard env vars by default" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const template = HelpTemplate{
        .show_env_section = true,
        .show_standard_env_vars = true,
    };

    try printSectionEnvVars(w, false, &cmd, &template);
    const output = list.items;

    // Standard env vars should be listed
    try std.testing.expect(mem.indexOf(u8, output, "NO_COLOR") != null);
    try std.testing.expect(mem.indexOf(u8, output, "TERM") != null);
    try std.testing.expect(mem.indexOf(u8, output, "Disable colored output") != null);
}

test "help: env section hidden when show_env_section is false" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

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
        },
    };

    const template = HelpTemplate{
        .show_env_section = false,
    };

    try printSectionEnvVars(w, false, &cmd, &template);
    // Should produce no output
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "help: env section custom header" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            FlagSpec{
                .name = "token",
                .help = "Auth token",
                .ftype = .string,
                .env = "MYAPP_TOKEN",
            },
        },
    };

    const template = HelpTemplate{
        .show_env_section = true,
        .env_header = "ENV VARS",
        .show_standard_env_vars = false,
    };

    try printSectionEnvVars(w, false, &cmd, &template);
    const output = list.items;

    try std.testing.expect(mem.indexOf(u8, output, "ENV VARS:") != null);
    try std.testing.expect(mem.indexOf(u8, output, "MYAPP_TOKEN") != null);
}

test "help: HelpTemplate show_env_section defaults to false" {
    const template = HelpTemplate{};
    try std.testing.expect(!template.show_env_section);
    try std.testing.expect(mem.eql(u8, template.env_header, "Environment Variables"));
}

test "help: env section in template sections list renders correctly" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    const w = list.writer(std.testing.allocator);

    const cmd = Command{
        .name = "envapp",
        .summary = "Env test app",
        .flags = &.{
            FlagSpec{
                .name = "host",
                .help = "Server host",
                .ftype = .string,
                .env = "ENVAPP_HOST",
            },
        },
    };

    // Template with env_vars section included
    const template = HelpTemplate{
        .sections = &.{ .env_vars, .footer },
        .show_env_section = true,
        .show_standard_env_vars = true,
        .show_footer = false,
    };

    // Render directly through the section dispatch loop
    for (template.sections) |section| {
        switch (section) {
            .env_vars => try printSectionEnvVars(w, false, &cmd, &template),
            .footer => try printSectionFooter(w, &cmd, &template),
            else => {},
        }
    }

    const output = list.items;
    try std.testing.expect(mem.indexOf(u8, output, "Environment Variables:") != null);
    try std.testing.expect(mem.indexOf(u8, output, "ENVAPP_HOST") != null);
    try std.testing.expect(mem.indexOf(u8, output, "NO_COLOR") != null);
    try std.testing.expect(mem.indexOf(u8, output, "TERM") != null);
}
