// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: Plain-Text Section Rendering
//!
//! Section renderers for plain-text help output. The public entry points
//! (`printHelp`, `printHelpWithTemplate`) live in `help.zig` and dispatch
//! into `renderTextSection` here.

const std = @import("std");
const mem = std.mem;

const command = @import("../command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

// Template types live in help.zig; group-collection helper lives in common.zig.
const help = @import("../help.zig");
const HelpSection = help.HelpSection;
const HelpTemplate = help.HelpTemplate;
const collectUniqueGroups = @import("common.zig").collectUniqueGroups;

/// Control-byte filtering for plain-text help output (NS-056 / CWE-150).
/// Provided by the first-class `sanitize` module (single source of truth).
const sanitize = @import("sanitize");

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

/// Render a single plain-text help section to `w`.
/// All Command-struct metadata (names, summaries, help strings, examples, env
/// var names, defaults) is filtered through `sanitize.writeControlFiltered` to
/// neutralize terminal escape/control bytes (CWE-150).
/// HelpTemplate fields (section headers, footer_text) are developer
/// configuration and are emitted as-is.
// Internal to the help subsystem; pub for cross-file use within the module.
pub fn renderTextSection(w: anytype, use_color: bool, cmd: *const Command, template: *const HelpTemplate, section: HelpSection) !void {
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

/// Print header section (name and summary)
fn printSectionHeader(w: anytype, use_color: bool, cmd: *const Command) !void {
    if (use_color) {
        try w.writeAll(ansi_bold);
        try sanitize.writeControlFiltered(w, cmd.name);
        try w.writeAll(ansi_reset);
    } else {
        try sanitize.writeControlFiltered(w, cmd.name);
    }
    try w.writeAll(" - ");
    try sanitize.writeControlFiltered(w, cmd.summary);
    try w.writeAll("\n");
}

/// Print usage section
fn printSectionUsage(w: anytype, cmd: *const Command, template: *const HelpTemplate) !void {
    try w.print("\n{s}: ", .{template.usage_header});
    try sanitize.writeControlFiltered(w, cmd.name);
    try w.writeAll(" [flags]");
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
        try w.splatByteAll(' ', template.indent);
        try sanitize.writeControlFiltered(w, example);
        try w.writeAll("\n");
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
    try sanitize.writeControlFiltered(w, cmd.long_help);
    try w.writeAll("\n");
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
                try w.writeAll("\n" ++ ansi_bold);
                try sanitize.writeControlFiltered(w, group_name);
                try w.writeAll(":" ++ ansi_reset ++ "\n");
            } else {
                try w.writeAll("\n");
                try sanitize.writeControlFiltered(w, group_name);
                try w.writeAll(":\n");
            }
        } else {
            try w.print("\n{s}:\n", .{template.commands_header});
        }

        for (cmd.subcommands) |subcmd| {
            if (subcmd.hidden) continue;
            if (!std.mem.eql(u8, subcmd.group, group_name)) continue;

            // Write indent
            try w.splatByteAll(' ', template.indent);

            if (use_color) {
                try w.writeAll(ansi_cyan);
                try sanitize.writeControlFiltered(w, subcmd.name);
                try w.writeAll(ansi_reset);
            } else {
                try sanitize.writeControlFiltered(w, subcmd.name);
            }

            // Padding to align descriptions. Computed from the raw name
            // length: well-formed metadata contains no control bytes, so
            // raw and filtered lengths match in practice; filtering above
            // is the security boundary, alignment is cosmetic.
            // Saturating: a dev template may set indent > name_column_width
            // (R2-01); degrade to zero-width alignment instead of underflow.
            const sub_name_len: usize = subcmd.name.len;
            const col_width: usize = @as(usize, template.name_column_width) -| template.indent;
            const sub_min_len: usize = @min(sub_name_len, col_width);
            const sub_padding: usize = col_width - sub_min_len;
            try w.splatByteAll(' ', sub_padding);
            try sanitize.writeControlFiltered(w, subcmd.summary);
            try w.writeAll("\n");
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
    try w.splatByteAll(' ', template.indent);

    if (use_color) {
        try w.writeAll(ansi_cyan);
        try sanitize.writeControlFiltered(w, name);
        try w.writeAll(ansi_reset);
    } else {
        try sanitize.writeControlFiltered(w, name);
    }

    // Padding to align descriptions. Computed from the raw name length:
    // well-formed metadata contains no control bytes, so raw and filtered
    // lengths match in practice.
    // Saturating: a dev template may set indent > name_column_width (R2-01).
    const name_len: usize = name.len;
    const col_width: usize = @as(usize, template.name_column_width) -| template.indent;
    const min_len: usize = @min(name_len, col_width);
    const pad: usize = col_width - min_len;
    try w.splatByteAll(' ', pad);

    try sanitize.writeControlFiltered(w, description);
    try w.writeAll("\n");
}

/// Print a single flag with template settings
fn printFlagWithTemplate(w: anytype, use_color: bool, template: *const HelpTemplate, flag: *const FlagSpec) !void {
    // Write indent
    try w.splatByteAll(' ', template.indent);

    // Short flag
    // Short flags must be alphanumeric (see FlagSpec.short); other bytes are
    // never a valid short option, so omit them — consistent with the parser
    // and the completion generators.
    if (flag.short) |s| {
        if (std.ascii.isAlphanumeric(s)) {
            if (use_color) {
                try w.print(ansi_yellow ++ "-{c}" ++ ansi_reset ++ ", ", .{s});
            } else {
                try w.print("-{c}, ", .{s});
            }
        } else {
            try w.print("    ", .{});
        }
    } else {
        try w.print("    ", .{});
    }

    // Long flag
    if (use_color) {
        try w.writeAll(ansi_yellow ++ "--");
        try sanitize.writeControlFiltered(w, flag.name);
        try w.writeAll(ansi_reset);
    } else {
        try w.writeAll("--");
        try sanitize.writeControlFiltered(w, flag.name);
    }

    // Padding. Computed from the raw name length: well-formed metadata
    // contains no control bytes, so raw and filtered lengths match in
    // practice.
    // Saturating: a dev template may set name_column_width < indent + 6
    // (R2-01); degrade to zero-width alignment instead of underflow.
    const name_len: usize = flag.name.len;
    const col_width: usize = @as(usize, template.name_column_width) -| template.indent -| 6; // -6 for "  -X, "
    const min_len: usize = @min(name_len, col_width);
    const padding_amount: usize = if (col_width > min_len) col_width - min_len else 0;
    try w.splatByteAll(' ', padding_amount);

    // Help text
    try sanitize.writeControlFiltered(w, flag.help);

    // Default value
    if (flag.default_str) |def| {
        try w.writeAll(" [default: ");
        try sanitize.writeControlFiltered(w, def);
        try w.writeAll("]");
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
            try w.writeAll(" " ++ ansi_cyan ++ "[$");
            try sanitize.writeControlFiltered(w, env_var);
            try w.writeAll("]" ++ ansi_reset);
        } else {
            try w.writeAll(" [$");
            try sanitize.writeControlFiltered(w, env_var);
            try w.writeAll("]");
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
        try w.writeAll("\nFor full help: ");
        try sanitize.writeControlFiltered(w, cmd.name);
        try w.writeAll(" --help\n");
    }
}

// ============================================================================
// Environment Variables Section Tests (GAP-0054)
// ============================================================================

test "help: env section prints flag-sourced env vars when enabled" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

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
    const output = buf.written();

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
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
    };

    const template = HelpTemplate{
        .show_env_section = true,
        .show_standard_env_vars = true,
    };

    try printSectionEnvVars(w, false, &cmd, &template);
    const output = buf.written();

    // Standard env vars should be listed
    try std.testing.expect(mem.indexOf(u8, output, "NO_COLOR") != null);
    try std.testing.expect(mem.indexOf(u8, output, "TERM") != null);
    try std.testing.expect(mem.indexOf(u8, output, "Disable colored output") != null);
}

test "help: env section hidden when show_env_section is false" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

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
    try std.testing.expectEqual(@as(usize, 0), buf.written().len);
}

test "help: env section custom header" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

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
    const output = buf.written();

    try std.testing.expect(mem.indexOf(u8, output, "ENV VARS:") != null);
    try std.testing.expect(mem.indexOf(u8, output, "MYAPP_TOKEN") != null);
}

test "help: env section in template sections list renders correctly" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

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

    const output = buf.written();
    try std.testing.expect(mem.indexOf(u8, output, "Environment Variables:") != null);
    try std.testing.expect(mem.indexOf(u8, output, "ENVAPP_HOST") != null);
    try std.testing.expect(mem.indexOf(u8, output, "NO_COLOR") != null);
    try std.testing.expect(mem.indexOf(u8, output, "TERM") != null);
}

// ============================================================================
// Control-Byte Filtering Tests (NS-056 / CWE-150)
// ============================================================================

test "help: text output strips terminal escape bytes from metadata" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const cmd = Command{
        .name = "esc",
        .summary = "s\x1b[2Jummary",
        .flags = &.{
            FlagSpec{
                .name = "bad",
                .help = "h\x1b]0;evil\x07elp",
                .ftype = .bool,
                .default_str = "d\x1befault",
                .env = "EV\x1bIL_VAR",
            },
        },
    };

    const template = HelpTemplate.default;
    for (template.sections) |section| {
        try renderTextSection(w, false, &cmd, &template, section);
    }

    const output = buf.written();
    try std.testing.expect(mem.indexOfScalar(u8, output, 0x1b) == null);
    try std.testing.expect(mem.indexOfScalar(u8, output, 0x07) == null);
    // Printable remainder survives (only the control bytes are removed)
    try std.testing.expect(mem.indexOf(u8, output, "s[2Jummary") != null);
    try std.testing.expect(mem.indexOf(u8, output, "h]0;evilelp") != null);
}

test "help: text output strips escape bytes from examples, subcommands, long help, groups, env section" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const subcmd = Command{
        .name = "su\x1b[1mb",
        .summary = "sub \x1b[31msummary",
        .group = "Gr\x1b[2Joup",
    };
    const cmd = Command{
        .name = "esc",
        .summary = "summary",
        .long_help = "long\x1bc help text",
        .examples = &.{"esc run \x1b[2J--force"},
        .subcommands = &.{&subcmd},
        .flags = &.{
            FlagSpec{
                .name = "token",
                .help = "auth \x1b[9999Htoken",
                .ftype = .string,
                .env = "ESC_\x1b[2JTOKEN",
            },
        },
    };

    const template = HelpTemplate{
        .sections = &.{ .header, .usage, .examples, .description, .commands, .flags, .env_vars, .footer },
        .show_env_section = true,
    };
    for (template.sections) |section| {
        try renderTextSection(w, false, &cmd, &template, section);
    }

    const output = buf.written();
    try std.testing.expect(mem.indexOfScalar(u8, output, 0x1b) == null);
    // Printable content survives
    try std.testing.expect(mem.indexOf(u8, output, "long") != null);
    try std.testing.expect(mem.indexOf(u8, output, "--force") != null);
    try std.testing.expect(mem.indexOf(u8, output, "sub ") != null);
}

test "help: colored text output strips escape bytes from metadata but keeps styling" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const cmd = Command{
        .name = "e\x1b[2Jsc",
        .summary = "summary",
        .flags = &.{
            FlagSpec{
                .name = "ba\x1b[31md",
                .help = "help",
                .ftype = .bool,
            },
        },
    };

    const template = HelpTemplate.default;
    for (template.sections) |section| {
        try renderTextSection(w, true, &cmd, &template, section);
    }

    const output = buf.written();
    // Framework styling is present...
    try std.testing.expect(mem.indexOf(u8, output, ansi_bold) != null);
    // ...but injected escape sequences from metadata are neutralized
    // (the ESC byte is stripped; the printable remainder is harmless)
    try std.testing.expect(mem.indexOf(u8, output, "\x1b[2J") == null);
    try std.testing.expect(mem.indexOf(u8, output, "\x1b[31m") == null);
}

test "help: pathological template column widths do not panic (R2-01)" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const subcmd = Command{ .name = "subcommand", .summary = "Sub summary" };
    const cmd = Command{
        .name = "app",
        .summary = "test",
        .subcommands = &.{&subcmd},
        .flags = &.{
            FlagSpec{
                .name = "config",
                .short = 'c',
                .help = "Config file",
                .ftype = .string,
                .env = "APP_CONFIG",
            },
        },
    };

    // indent greater than name_column_width used to underflow the usize
    // column math (debug panic). Must render, degraded but safe.
    const template = HelpTemplate{
        .sections = &.{ .header, .usage, .commands, .flags, .env_vars, .footer },
        .show_env_section = true,
        .indent = 30,
        .name_column_width = 1,
    };
    for (template.sections) |section| {
        try renderTextSection(w, false, &cmd, &template, section);
    }
    try std.testing.expect(mem.indexOf(u8, buf.written(), "--config") != null);
}

test "help: short flag with control byte is not emitted (CWE-150)" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const cmd = Command{
        .name = "myapp",
        .summary = "test",
        .flags = &.{
            FlagSpec{
                .name = "evil",
                .short = 0x1b, // ESC — a non-printable byte
                .help = "should not emit ESC",
                .ftype = .bool,
            },
        },
    };

    const template = HelpTemplate.default;
    for (template.sections) |section| {
        try renderTextSection(w, false, &cmd, &template, section);
    }

    const output = buf.written();
    try std.testing.expect(mem.indexOfScalar(u8, output, 0x1b) == null);
}

test "help: printable metacharacter short flag is not emitted" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const w = &buf.writer;

    const cmd = Command{
        .name = "myapp",
        .summary = "test",
        .flags = &.{
            FlagSpec{
                .name = "evil",
                .short = '`', // printable, but a shell metacharacter
                .help = "should not emit a backtick short",
                .ftype = .bool,
            },
        },
    };

    const template = HelpTemplate.default;
    for (template.sections) |section| {
        try renderTextSection(w, false, &cmd, &template, section);
    }

    const output = buf.written();
    // The backtick short must be omitted; the long form still renders.
    try std.testing.expect(mem.indexOfScalar(u8, output, '`') == null);
    try std.testing.expect(mem.indexOf(u8, output, "--evil") != null);
}
