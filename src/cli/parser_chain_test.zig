// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Public-API tests for chain-wide parser validation and diagnostic
//! provenance (iteration-3 convergence findings 4 and 6).
//!
//! Covers required-flag and flag-group enforcement across the full
//! resolved command chain (root through leaf), leaf-only positional
//! rules, and InvalidValue diagnostic provenance (env-promoted vs
//! CLI-supplied). All tests exercise the parser exclusively through
//! its public API.

const std = @import("std");
const builtin = @import("builtin");

const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;
const format = @import("parser/format.zig");

const command = @import("command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;
const FlagGroup = command.FlagGroup;

test "parser: root required flag enforced when subcommand runs (iter3-4)" {
    const subcmd = Command{
        .name = "sub",
        .summary = "Subcommand",
    };
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "name", .help = "Required name", .ftype = .string, .required = true },
        },
        .subcommands = &.{&subcmd},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    // The root flag is required regardless of which command in the tree
    // is resolved; it must not pass silently when a subcommand runs.
    try std.testing.expectError(ParseError.MissingRequired, parser.parse(&.{ "test", "sub" }));
    try std.testing.expectEqualStrings("name", parser.missing_required_flag.?);
}

test "parser: root flag group conflict enforced when subcommand runs (iter3-4)" {
    const subcmd = Command{
        .name = "sub",
        .summary = "Subcommand",
    };
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "json", .help = "JSON output", .ftype = .bool },
            FlagSpec{ .name = "yaml", .help = "YAML output", .ftype = .bool },
        },
        .flag_groups = &.{
            FlagGroup{ .group_type = .mutually_exclusive, .flags = &.{ "json", "yaml" } },
        },
        .subcommands = &.{&subcmd},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    // Both root flags set while a subcommand is resolved: the root's
    // mutually-exclusive group spans the chain and must be enforced.
    try std.testing.expectError(
        ParseError.MutuallyExclusiveFlags,
        parser.parse(&.{ "test", "sub", "--json", "--yaml" }),
    );
}

test "parser: args rules stay leaf-only when subcommand runs (iter3-4)" {
    const subcmd = Command{
        .name = "sub",
        .summary = "Subcommand",
    };
    const root = Command{
        .name = "test",
        .summary = "Test command",
        // Root restricts positionals, but positional rules belong to the
        // resolved leaf: this must not reject the subcommand's args.
        .args = .{ .only_valid = &.{"start"} },
        .subcommands = &.{&subcmd},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "sub", "freeform" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("freeform", result.context.positionals.items[0]);
}

test "parser: CLI InvalidValue not rendered as env-parse error (iter3-6)" {
    if (comptime builtin.os.tag == .windows) return;

    // PATH is set on all POSIX test systems and never parses as an integer.
    const path_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("PATH") orelse return;
    if (std.fmt.parseInt(i64, path_val, 10)) |_| {
        return; // Environment too unusual to test against.
    } else |_| {}

    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "alpha", .help = "Env-bound int", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "beta", .help = "Plain int", .ftype = .int },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--beta", "notanint" });
    try std.testing.expectError(ParseError.InvalidValue, result);

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try format.formatParseError(&parser, ParseError.InvalidValue, &w);
    const msg = w.buffered();

    // The failure came from the CLI value for --beta; the diagnostic must
    // not be hijacked by --alpha's unrelated env-var problem.
    try std.testing.expect(std.mem.indexOf(u8, msg, "PATH") == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "alpha") == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Invalid value") != null);
}

test "parser: required flag with unparseable env renders env-parse message (iter3-6)" {
    if (comptime builtin.os.tag == .windows) return;

    const path_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("PATH") orelse return;
    if (std.fmt.parseInt(i64, path_val, 10)) |_| {
        return; // Environment too unusual to test against.
    } else |_| {}

    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "num", .help = "Env-bound int", .ftype = .int, .env = "PATH", .required = true },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{"test"});
    try std.testing.expectError(ParseError.InvalidValue, result);

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try format.formatParseError(&parser, ParseError.InvalidValue, &w);
    const msg = w.buffered();

    // Here the InvalidValue genuinely originated from env promotion in
    // checkRequired: the env diagnostic is the right one to render.
    try std.testing.expect(std.mem.indexOf(u8, msg, "PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "num") != null);
}
