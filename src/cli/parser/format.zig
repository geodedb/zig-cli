// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Parser: Error-Message Rendering
//!
//! Human-readable rendering of `ParseError` diagnostics, using the
//! contextual details (missing flag names, env parse errors, group
//! conflicts, args validation details) recorded on the Parser instance.
//!
//! Public-for-internal; not part of the stable API. The mutual file
//! import (parser.zig <-> parser/format.zig) is legal in Zig within a
//! module; the help/ split uses the same pattern.

const parser_mod = @import("../parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;

/// Write a human-readable error message for the given ParseError to stderr,
/// using contextual details stored on the Parser instance.
pub fn formatParseError(parser: *const Parser, err: ParseError, stderr: anytype) !void {
    switch (err) {
        ParseError.UnknownFlag => try stderr.print("Error: Unknown flag\n\n", .{}),
        ParseError.UnknownCommand => try stderr.print("Error: Unknown command\n\n", .{}),
        ParseError.MissingValue => try stderr.print("Error: Missing value for flag\n\n", .{}),
        ParseError.InvalidValue => {
            if (parser.invalid_default_flag) |flag_name| {
                try stderr.print("Error: Invalid default value for --{s}\n\n", .{flag_name});
            } else if (parser.env_parse_error_count > 0) {
                const env_err = parser.env_parse_errors[0];
                try stderr.print("Error: Invalid value for --{s}: environment variable ${s} has value that cannot be parsed as {s}", .{
                    env_err.flag_name, env_err.env_name, env_err.expected_type,
                });
                // Only the first error is rendered; count the remaining
                // recorded errors plus any dropped beyond the buffer.
                const more = (parser.env_parse_error_count - 1) + parser.env_parse_errors_dropped;
                if (more > 0) {
                    try stderr.print(" (+{d} more)", .{more});
                }
                try stderr.print("\n\n", .{});
            } else {
                try stderr.print("Error: Invalid value\n\n", .{});
            }
        },
        ParseError.MissingRequired => {
            if (parser.missing_required_flag) |flag_name| {
                try stderr.print("Error: Missing required flag --{s}\n\n", .{flag_name});
            } else {
                try stderr.print("Error: Missing required flag\n\n", .{});
            }
        },
        ParseError.SecretInFlagOrEnv => {
            if (parser.secret_flag_name) |sname| {
                try stderr.print("Error: Secret '{s}' cannot be passed via --flag or environment variable. Provide via stdin: echo $SECRET | myapp\n\n", .{sname});
            } else {
                try stderr.print("Error: Secret cannot be passed via --flag or environment variable. Provide via stdin: echo $SECRET | myapp\n\n", .{});
            }
        },
        ParseError.MutuallyExclusiveFlags => {
            if (parser.conflicting_flags) |flags| {
                try stderr.print("Error: Flags --{s} and --{s} are mutually exclusive\n\n", .{ flags[0], flags[1] });
            } else {
                try stderr.print("Error: Mutually exclusive flags specified\n\n", .{});
            }
        },
        ParseError.RequiredTogetherFlags => {
            if (parser.missing_together_flags) |flags| {
                try stderr.print("Error: Flags must be used together: ", .{});
                for (flags, 0..) |f, idx| {
                    if (idx > 0) try stderr.print(", ", .{});
                    try stderr.print("--{s}", .{f});
                }
                try stderr.print("\n\n", .{});
            } else {
                try stderr.print("Error: Required flags must be used together\n\n", .{});
            }
        },
        ParseError.OneRequiredFlags => {
            if (parser.one_required_group) |flags| {
                try stderr.print("Error: At least one of these flags is required: ", .{});
                for (flags, 0..) |f, idx| {
                    if (idx > 0) try stderr.print(", ", .{});
                    try stderr.print("--{s}", .{f});
                }
                try stderr.print("\n\n", .{});
            } else {
                try stderr.print("Error: At least one flag from group is required\n\n", .{});
            }
        },
        ParseError.InvalidArgs => {
            if (parser.args_error) |args_err| {
                var buf: [256]u8 = undefined;
                const msg = args_err.format(&buf);
                try stderr.print("Error: {s}\n\n", .{msg});
            } else {
                try stderr.print("Error: Invalid positional arguments\n\n", .{});
            }
        },
        else => try stderr.print("Error: Parse error\n\n", .{}),
    }
}
