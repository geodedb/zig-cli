// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Parser: Environment and Default-Value Machinery
//!
//! Env-default machinery for the argument parser: cross-platform
//! environment variable lookup, env-based flag defaults (with parse-error
//! recording), and `default_str` defaults.
//!
//! Functions here are free, public-for-internal functions taking a
//! `*Parser`; they are not part of the stable API. The mutual file import
//! (parser.zig <-> parser/env.zig) is legal in Zig within a module; the
//! help/ split uses the same pattern.

const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");

const command = @import("../command.zig");
const Command = command.Command;
const Context = command.Context;

const parser_mod = @import("../parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;

/// Record of an environment variable parse failure
pub const EnvParseErrorEntry = struct {
    env_name: []const u8 = "",
    flag_name: []const u8 = "",
    value: []const u8 = "",
    expected_type: []const u8 = "",
};

/// Cross-platform environment variable lookup.
/// On POSIX, returns a borrowed pointer into the environment block (no allocation).
/// On Windows, returns null: env-based flag defaults are POSIX-focused, and
/// getAlloc would require heap storage outliving this call to be sound (the
/// previous stack-backed FixedBufferAllocator here returned a dangling slice —
/// UB on Windows). Returning null disables env-bound flag defaults on Windows,
/// which is a documented limitation.
/// Note: this mirrors the documented behaviour of term/env.zig's getEnvValueRuntime,
/// which also returns null on Windows for the same reason.
pub fn getEnvVar(name: []const u8) ?[]const u8 {
    // Env-based flag defaults are POSIX-focused: process_environ's getAlloc
    // would require heap storage outliving this call to be sound (a
    // stack-backed FixedBufferAllocator here previously returned a dangling
    // slice — UB). Returning null disables env-bound flag defaults on
    // Windows — a documented limitation.
    if (comptime builtin.os.tag == .windows) return null;
    return std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix(name);
}

/// Populate context fields from environment variables (NO_COLOR,
/// TERM=dumb) and fill flag values whose specs declare an `env` name.
/// Processes both root command flags and the resolved current command's flags.
pub fn applyEnvDefaults(p: *Parser, ctx: *Context) ParseError!void {
    // Check NO_COLOR
    if (getEnvVar("NO_COLOR")) |_| {
        ctx.no_color = true;
    }

    // Check TERM=dumb
    if (getEnvVar("TERM")) |term| {
        if (mem.eql(u8, term, "dumb")) {
            ctx.no_color = true;
        }
    }

    // Apply environment variable flags for root command
    try applyEnvDefaultsForCommand(p, ctx, p.root);
}

/// Apply environment variable defaults for a specific command's flags.
/// Called for the root command during initial parsing, and again for
/// the resolved subcommand after subcommand resolution.
pub fn applyEnvDefaultsForCommand(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    for (cmd.flags) |flag| {
        if (flag.env) |env_name| {
            // Check if secret - skip env for secrets
            if (flag.secret == .from_file_or_stdin) continue;

            // Skip if already set (CLI flag takes priority over env)
            if (ctx.flags.get(flag.name) != null) continue;

            if (getEnvVar(env_name)) |value| {
                const fval = p.parseValue(flag.ftype, value) catch {
                    // Record the parse failure for error reporting
                    if (p.env_parse_error_count < p.env_parse_errors.len) {
                        p.env_parse_errors[p.env_parse_error_count] = .{
                            .env_name = env_name,
                            .flag_name = flag.name,
                            .value = value,
                            .expected_type = flag.ftype.format(),
                        };
                        p.env_parse_error_count += 1;
                    } else {
                        // Detail buffer is full: count the drop so the
                        // total failure count is not lost (NQ-NEW-013).
                        p.env_parse_errors_dropped += 1;
                    }
                    continue;
                };
                // Propagate allocation failure instead of silently
                // dropping the env value (GAP-0097).
                ctx.flags.put(flag.name, fval) catch return ParseError.OutOfMemory;
            }
        }
    }
}

/// Apply default values to flags that were not set during parsing,
/// starting with the root command and then the current command.
pub fn applyDefaultValues(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    try applyDefaultsForCommand(p, ctx, p.root);
    if (cmd != p.root) {
        try applyDefaultsForCommand(p, ctx, cmd);
    }
}

/// Apply default values from a single command's flag specifications.
/// Skips flags that already have a value or have a secret policy
/// (secrets must be provided via file/stdin, never via defaults).
pub fn applyDefaultsForCommand(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    for (cmd.flags) |flag| {
        // Never apply defaults to secret flags -- they must come from
        // file or stdin, not from a hardcoded default value.
        if (flag.secret == .from_file_or_stdin) continue;
        if (flag.default_str) |def| {
            if (ctx.getFlag(flag.name) != null) continue;
            const fval = p.parseValue(flag.ftype, def) catch {
                // An unparseable default is a programmer error in the
                // command definition: fail loudly instead of silently
                // skipping (GAP-0097).
                p.invalid_default_flag = flag.name;
                return ParseError.InvalidValue;
            };
            ctx.flags.put(flag.name, fval) catch return ParseError.OutOfMemory;
        }
    }
}
