// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Parser: Post-Parse Validation
//!
//! Required-flag, flag-group, and positional-argument validation run by
//! the parser's finalize phase. Required-flag and flag-group checks are
//! applied to every command in the resolved chain (root through leaf);
//! positional rules apply to the leaf only.
//!
//! Functions here are free, public-for-internal functions taking a
//! `*Parser`; they are not part of the stable API. The mutual file import
//! (parser.zig <-> parser/validate.zig) is legal in Zig within a module;
//! the help/ split uses the same pattern.

const std = @import("std");
const mem = std.mem;

const command = @import("../command.zig");
const Command = command.Command;
const Context = command.Context;

const parser_mod = @import("../parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;

/// Verify that all flags marked as `required` have been provided.
/// Records the first missing flag name for error reporting.
/// If a missing required flag had an env parse/validation error, the
/// failure is promoted to `InvalidValue` and the originating env error
/// entry index is recorded so diagnostics render the env message only
/// when it is actually the cause (iter3 finding 6).
pub fn checkRequired(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    for (cmd.flags) |flag| {
        if (flag.required) {
            if (ctx.getFlag(flag.name) == null) {
                // Check if there was an env parse error for this flag
                for (p.env_parse_errors[0..p.env_parse_error_count], 0..) |env_err, idx| {
                    if (mem.eql(u8, env_err.flag_name, flag.name)) {
                        // The flag was provided via env but failed to
                        // parse or validate: promote with provenance.
                        p.missing_required_flag = flag.name;
                        p.invalid_value_env_index = idx;
                        return ParseError.InvalidValue;
                    }
                }
                // Store the missing flag name for better error reporting
                p.missing_required_flag = flag.name;
                return ParseError.MissingRequired;
            }
        }
    }
}

/// Check flag group constraints for one command's groups. Group members
/// are looked up in the shared flag map, so groups defined on ancestors
/// are enforced regardless of which command in the chain is resolved.
pub fn checkFlagGroups(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    for (cmd.flag_groups) |group| {
        switch (group.group_type) {
            .mutually_exclusive => {
                // Check that at most one flag in the group is set
                var set_count: usize = 0;
                var first_set: ?[]const u8 = null;
                var second_set: ?[]const u8 = null;
                for (group.flags) |flag_name| {
                    if (ctx.getFlag(flag_name) != null) {
                        set_count += 1;
                        if (first_set == null) {
                            first_set = flag_name;
                        } else if (second_set == null) {
                            second_set = flag_name;
                        }
                    }
                }
                if (set_count > 1) {
                    if (first_set != null and second_set != null) {
                        p.conflicting_flags = .{ first_set.?, second_set.? };
                    }
                    return ParseError.MutuallyExclusiveFlags;
                }
            },
            .required_together => {
                // Check that either all or none are set
                var any_set = false;
                var all_set = true;
                for (group.flags) |flag_name| {
                    if (ctx.getFlag(flag_name) != null) {
                        any_set = true;
                    } else {
                        all_set = false;
                    }
                }
                if (any_set and !all_set) {
                    p.missing_together_flags = group.flags;
                    return ParseError.RequiredTogetherFlags;
                }
            },
            .one_required => {
                // Check that at least one flag in the group is set
                var any_set = false;
                for (group.flags) |flag_name| {
                    if (ctx.getFlag(flag_name) != null) {
                        any_set = true;
                        break;
                    }
                }
                if (!any_set) {
                    p.one_required_group = group.flags;
                    return ParseError.OneRequiredFlags;
                }
            },
        }
    }
}

/// Check positional argument constraints (leaf command only; positional
/// rules belong to the command that actually consumes the positionals).
pub fn checkArgs(p: *Parser, ctx: *Context, cmd: *const Command) ParseError!void {
    if (cmd.args) |args_validator| {
        args_validator.validate(ctx.positionals.items) catch {
            // Get error details for better error messages
            p.args_error = args_validator.getErrorDetails(ctx.positionals.items);
            return ParseError.InvalidArgs;
        };
    }
}
