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
const FlagSpec = command.FlagSpec;

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
/// TERM=dumb). Env-bound FLAG defaults are intentionally NOT applied
/// here: they run during finalize, after the argv loop, so CLI values
/// always take precedence -- including for repeatable string_array flags,
/// which would otherwise append to an env-seeded array (iter3 finding 2).
pub fn applyEnvContextDefaults(ctx: *Context) void {
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
}

/// Record an environment-variable failure (unparseable or rejected by the
/// flag's custom validator) in the parser's bounded error buffer. The flag
/// stays unset; required-flag validation later promotes the failure to a
/// hard `InvalidValue` error with env provenance.
fn recordEnvFailure(p: *Parser, env_name: []const u8, flag: *const FlagSpec, value: []const u8) void {
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
}

/// Apply environment variable defaults for a specific command's flags.
/// Called during finalize for every command in the resolved chain, root
/// through leaf. Skips flags already set (CLI takes priority over env)
/// and enforces the flag's custom validator just like the CLI path
/// (iter3 finding 3): a rejected env value is recorded as an env failure
/// and skipped, matching the unparseable-env-value behavior.
pub fn applyEnvDefaultsForCommand(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    for (cmd.flags) |flag| {
        if (flag.env) |env_name| {
            // Check if secret - skip env for secrets
            if (flag.secret == .from_file_or_stdin) continue;

            // Skip if already set (CLI flag takes priority over env)
            if (ctx.flags.get(flag.name) != null) continue;

            if (getEnvVar(env_name)) |value| {
                if (!flag.validate(value)) {
                    // Custom validator rejected the env value: record and
                    // skip, same channel as a parse failure.
                    recordEnvFailure(p, env_name, &flag, value);
                    continue;
                }
                const fval = p.parseValue(flag.ftype, value) catch {
                    // Record the parse failure for error reporting
                    recordEnvFailure(p, env_name, &flag, value);
                    continue;
                };
                // Propagate allocation failure instead of silently
                // dropping the env value (GAP-0097).
                ctx.flags.put(flag.name, fval) catch return ParseError.OutOfMemory;
            }
        }
    }
}

/// Apply default values from a single command's flag specifications.
/// Called during finalize for every command in the resolved chain, root
/// through leaf (iter3 finding 5). Skips flags that already have a value
/// or have a secret policy (secrets must be provided via file/stdin,
/// never via defaults). Defaults must satisfy the flag's custom validator
/// just like CLI values (iter3 finding 3).
pub fn applyDefaultsForCommand(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    for (cmd.flags) |flag| {
        // Never apply defaults to secret flags -- they must come from
        // file or stdin, not from a hardcoded default value.
        if (flag.secret == .from_file_or_stdin) continue;
        if (flag.default_str) |def| {
            if (ctx.getFlag(flag.name) != null) continue;
            // A default that fails its own validator or cannot be parsed
            // is a programmer error in the command definition: fail
            // loudly instead of silently skipping (GAP-0097).
            if (!flag.validate(def)) {
                p.invalid_default_flag = flag.name;
                return ParseError.InvalidValue;
            }
            const fval = p.parseValue(flag.ftype, def) catch {
                p.invalid_default_flag = flag.name;
                return ParseError.InvalidValue;
            };
            ctx.flags.put(flag.name, fval) catch return ParseError.OutOfMemory;
        }
    }
}
