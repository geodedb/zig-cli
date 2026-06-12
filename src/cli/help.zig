// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help Module
//!
//! Help text generation with examples-first approach and
//! support for concise vs. full help output.
//!
//! This file holds the template types, the public entry points, and version
//! printing. Format-specific renderers live in the `help/` subdirectory:
//! - `help/text.zig` — plain-text section renderers
//! - `help/json.zig` — JSON help output and JSON string escaping
//! - `help/man.zig` — man page (roff) generation
//! - `help/markdown.zig` — Markdown documentation generation
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

const common = @import("help/common.zig");
const json = @import("help/json.zig");
const man = @import("help/man.zig");
const markdown = @import("help/markdown.zig");
const text = @import("help/text.zig");

// ============================================================================
// Re-exports from the format-specific renderers (public API preserved)
// ============================================================================

/// JSON string escaping (shared with version printing). See `help/json.zig`.
pub const writeJsonEscapedString = json.writeJsonEscapedString;
/// Man page (roff) generation. See `help/man.zig`.
pub const generateMan = man.generateMan;
/// Roff escaping for man page output. See `help/man.zig`.
pub const writeRoffEscaped = man.writeRoffEscaped;
/// Markdown documentation generation. See `help/markdown.zig`.
pub const generateMarkdown = markdown.generateMarkdown;

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
        json.printJsonHelp(cmd, ctx) catch {};
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
        try json.printJsonHelp(cmd, ctx);
    } else {
        try printTextHelpWithTemplate(cmd, ctx, template);
    }
}

/// Print text-format help using a template.
/// Renders all sections into a memory buffer first, then writes to stdout
/// in a single call to reduce syscall overhead.
fn printTextHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) !void {
    var buf: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer buf.deinit();
    buf.ensureUnusedCapacity(2048) catch {};
    const w = &buf.writer;
    const use_color = ctx.useColor();

    for (template.sections) |section| {
        // Check for custom renderer first
        if (template.custom_renderer) |renderer| {
            if (renderer(cmd, ctx, section, template)) {
                continue; // Custom renderer handled this section
            }
        }

        try text.renderTextSection(w, use_color, cmd, template, section);
    }

    try ctx.stdout.writeAll(buf.written());
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

// ============================================================================
// Tests
// ============================================================================

test {
    // Pull in tests from the format-specific renderer files and shared helpers.
    _ = common;
    _ = json;
    _ = man;
    _ = markdown;
    _ = text;
}

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
