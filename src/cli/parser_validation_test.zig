// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Public-API tests for the argument parser: validation and command-tree
//! behavior.
//!
//! Covers flag groups (mutually exclusive, required together, one
//! required), positional argument validators, command-chain tracking for
//! persistent hooks, and flag inheritance across the command chain. All
//! tests exercise the parser exclusively through its public API.

const std = @import("std");

const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;

const command = @import("command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;
const FlagGroup = command.FlagGroup;

// ============================================================================
// Flag Group Tests
// ============================================================================

test "parser: mutually exclusive flags - valid (one set)" {
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
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--json" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.getBool("json"));
}

test "parser: mutually exclusive flags - error (both set)" {
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
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--json", "--yaml" });

    try std.testing.expectError(ParseError.MutuallyExclusiveFlags, result);
}

test "parser: required together flags - valid (all set)" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "username", .help = "Username", .ftype = .string },
            FlagSpec{ .name = "password", .help = "Password", .ftype = .string },
        },
        .flag_groups = &.{
            FlagGroup{ .group_type = .required_together, .flags = &.{ "username", "password" } },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--username", "user", "--password", "pass" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("user", result.context.getString("username").?);
    try std.testing.expectEqualStrings("pass", result.context.getString("password").?);
}

test "parser: required together flags - error (only one set)" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "username", .help = "Username", .ftype = .string },
            FlagSpec{ .name = "password", .help = "Password", .ftype = .string },
        },
        .flag_groups = &.{
            FlagGroup{ .group_type = .required_together, .flags = &.{ "username", "password" } },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--username", "user" });

    try std.testing.expectError(ParseError.RequiredTogetherFlags, result);
}

test "parser: one required flags - valid (one set)" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "token", .help = "Auth token", .ftype = .string },
            FlagSpec{ .name = "username", .help = "Username", .ftype = .string },
        },
        .flag_groups = &.{
            FlagGroup{ .group_type = .one_required, .flags = &.{ "token", "username" } },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--token", "abc123" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("abc123", result.context.getString("token").?);
}

test "parser: one required flags - error (none set)" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "token", .help = "Auth token", .ftype = .string },
            FlagSpec{ .name = "username", .help = "Username", .ftype = .string },
        },
        .flag_groups = &.{
            FlagGroup{ .group_type = .one_required, .flags = &.{ "token", "username" } },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{"test"});

    try std.testing.expectError(ParseError.OneRequiredFlags, result);
}

// ============================================================================
// Argument Validator Tests
// ============================================================================

test "parser: args validator - exact args valid" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .exact = 2 },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "arg1", "arg2" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.context.positionals.items.len);
}

test "parser: args validator - exact args error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .exact = 2 },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "arg1" });

    try std.testing.expectError(ParseError.InvalidArgs, result);
}

test "parser: args validator - no args valid" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .none = {} },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{"test"});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), result.context.positionals.items.len);
}

test "parser: args validator - no args error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .none = {} },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "unexpected" });

    try std.testing.expectError(ParseError.InvalidArgs, result);
}

test "parser: args validator - minimum args valid" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .minimum = 2 },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "arg1", "arg2", "arg3" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), result.context.positionals.items.len);
}

test "parser: args validator - minimum args error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .minimum = 2 },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "arg1" });

    try std.testing.expectError(ParseError.InvalidArgs, result);
}

test "parser: args validator - maximum args valid" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .maximum = 2 },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "arg1" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.context.positionals.items.len);
}

test "parser: args validator - maximum args error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .maximum = 2 },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "arg1", "arg2", "arg3" });

    try std.testing.expectError(ParseError.InvalidArgs, result);
}

test "parser: args validator - range valid" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .range = .{ .min = 1, .max = 3 } },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "arg1", "arg2" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.context.positionals.items.len);
}

test "parser: args validator - range error too few" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .range = .{ .min = 2, .max = 4 } },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "arg1" });

    try std.testing.expectError(ParseError.InvalidArgs, result);
}

test "parser: args validator - only valid values" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .only_valid = &.{ "start", "stop", "restart" } },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "start" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("start", result.context.positionals.items[0]);
}

test "parser: args validator - only valid values error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .only_valid = &.{ "start", "stop", "restart" } },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "invalid" });

    try std.testing.expectError(ParseError.InvalidArgs, result);
}

test "parser: only_valid error message filters control bytes end-to-end (N-01)" {
    // Full pipeline: parse a hostile positional, render the diagnostic via
    // formatParseError, and assert the ESC byte never reaches the output
    // (CWE-150) while the message stays informative.
    const format = @import("parser/format.zig");
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .args = .{ .only_valid = &.{ "start", "stop" } },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "\x1b[2Jx" });
    try std.testing.expectError(ParseError.InvalidArgs, result);

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try format.formatParseError(&parser, ParseError.InvalidArgs, &w);
    const msg = w.buffered();

    try std.testing.expect(std.mem.indexOfScalar(u8, msg, 0x1b) == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "invalid argument") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "[2Jx") != null);
}

// ============================================================================
// Command Chain Tests (for persistent hooks)
// ============================================================================
// Chain-wide validation tests (iter3 findings 4, 6) live in
// parser_chain_test.zig to keep this file within the size budget.

test "parser: command chain includes root" {
    const root = Command{
        .name = "root",
        .summary = "Root command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{"root"});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.command_chain.items.len);
    try std.testing.expectEqualStrings("root", result.command_chain.items[0].name);
}

test "parser: command chain includes subcommand" {
    const subcmd = Command{
        .name = "sub",
        .summary = "Subcommand",
    };
    const root = Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&subcmd},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "root", "sub" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.command_chain.items.len);
    try std.testing.expectEqualStrings("root", result.command_chain.items[0].name);
    try std.testing.expectEqualStrings("sub", result.command_chain.items[1].name);
}

test "parser: command chain includes nested subcommands" {
    const leaf = Command{
        .name = "leaf",
        .summary = "Leaf command",
    };
    const middle = Command{
        .name = "middle",
        .summary = "Middle command",
        .subcommands = &.{&leaf},
    };
    const root = Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&middle},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "root", "middle", "leaf" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), result.command_chain.items.len);
    try std.testing.expectEqualStrings("root", result.command_chain.items[0].name);
    try std.testing.expectEqualStrings("middle", result.command_chain.items[1].name);
    try std.testing.expectEqualStrings("leaf", result.command_chain.items[2].name);
}

// ============================================================================
// Flag Inheritance Chain Tests (NQ-036)
// ============================================================================

test "parser: flag inheritance walks full 3-level chain" {
    const leaf = Command{
        .name = "leaf",
        .summary = "Leaf command",
    };
    const middle = Command{
        .name = "middle",
        .summary = "Middle command",
        .subcommands = &.{&leaf},
        .flags = &.{
            FlagSpec{ .name = "mid-flag", .help = "Middle flag", .ftype = .string },
        },
    };
    const root = Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&middle},
        .flags = &.{
            FlagSpec{ .name = "root-flag", .help = "Root flag", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");

    // Leaf command should be able to access middle's flag through full chain
    var result = try parser.parse(&.{ "root", "middle", "leaf", "--mid-flag", "hello", "--root-flag" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("leaf", result.command.name);
    try std.testing.expectEqualStrings("hello", result.context.getString("mid-flag").?);
    try std.testing.expect(result.context.getBool("root-flag"));
}

test "parser: flag inheritance - middle flag short from leaf" {
    const leaf = Command{
        .name = "leaf",
        .summary = "Leaf command",
    };
    const middle = Command{
        .name = "middle",
        .summary = "Middle command",
        .subcommands = &.{&leaf},
        .flags = &.{
            FlagSpec{ .name = "mid-flag", .short = 'm', .help = "Middle flag", .ftype = .bool },
        },
    };
    const root = Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&middle},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");

    // Leaf command should be able to access middle's short flag
    var result = try parser.parse(&.{ "root", "middle", "leaf", "-m" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("leaf", result.command.name);
    try std.testing.expect(result.context.getBool("mid-flag"));
}

test "parser: leaf flag takes precedence over parent in chain" {
    const leaf = Command{
        .name = "leaf",
        .summary = "Leaf command",
        .flags = &.{
            FlagSpec{ .name = "output", .help = "Leaf output", .ftype = .string },
        },
    };
    const middle = Command{
        .name = "middle",
        .summary = "Middle command",
        .subcommands = &.{&leaf},
        .flags = &.{
            FlagSpec{ .name = "output", .help = "Middle output", .ftype = .string },
        },
    };
    const root = Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&middle},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");

    // Current command's flag takes priority
    var result = try parser.parse(&.{ "root", "middle", "leaf", "--output", "leaf-value" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("leaf-value", result.context.getString("output").?);
}

// ============================================================================
// Token-Handling Defect Tests (convergence review iter-3 findings 1,7,9,10)
// ============================================================================

fn rejectTrueValidator(value: []const u8) bool {
    return !std.mem.eql(u8, value, "true");
}

test "parser: non-bool short flag mid-cluster returns MissingValue" {
    // Finding 1: `-ov file.txt` (o=string, v=bool) used to silently drop
    // -o because only the LAST cluster position may consume a value.
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "output", .short = 'o', .help = "Output file", .ftype = .string },
            FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "-ov", "file.txt" });

    try std.testing.expectError(ParseError.MissingValue, result);
    // The diagnostic names the flag whose value was missing.
    try std.testing.expectEqualStrings("output", parser.missing_value_flag.?);
}

test "parser: bool-first short cluster with trailing value flag still works" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "output", .short = 'o', .help = "Output file", .ftype = .string },
            FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-vo", "file.txt" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.getBool("verbose"));
    try std.testing.expectEqualStrings("file.txt", result.context.getString("output").?);
}

test "parser: secret bool flag rejected via short form" {
    // Finding 7: bool short flags used to bypass the secret-policy check
    // that the long form enforces.
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "danger",
                .short = 'd',
                .help = "Secret toggle",
                .ftype = .bool,
                .secret = .from_file_or_stdin,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "-d" });

    try std.testing.expectError(ParseError.SecretInFlagOrEnv, result);
}

test "parser: secret bool flag rejected via long form" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "danger",
                .short = 'd',
                .help = "Secret toggle",
                .ftype = .bool,
                .secret = .from_file_or_stdin,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--danger" });

    try std.testing.expectError(ParseError.SecretInFlagOrEnv, result);
}

test "parser: bool short flag runs custom validator" {
    // Finding 7: bool short flags used to bypass flag.validate.
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "verbose",
                .short = 'v',
                .help = "Verbose",
                .ftype = .bool,
                .validator = &rejectTrueValidator,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "-v" });

    try std.testing.expectError(ParseError.InvalidValue, result);
}

test "parser: global flag accepts equals syntax with true" {
    // Finding 9: `--quiet=true` used to fail with UnknownFlag because the
    // `=` branch never fell through to the global-flag check.
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--quiet=true" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.quiet);
}

test "parser: global flag equals false leaves flag unset" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--quiet=false" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.context.quiet);
}

test "parser: global flag equals invalid value returns InvalidValue" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--quiet=banana" });

    try std.testing.expectError(ParseError.InvalidValue, result);
}

test "parser: help via equals syntax returns help_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--help=true" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.help_requested);
}

test "parser: bool flag with garbage explicit value returns InvalidValue" {
    // Finding 10: anything other than "true" used to silently parse as
    // false; bool values are now strictly "true"/"false".
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .help = "Verbose", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--verbose=ture" });

    try std.testing.expectError(ParseError.InvalidValue, result);
}

test "parser: bool flag explicit true and false values parse" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .help = "Verbose", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    {
        var result = try parser.parse(&.{ "test", "--verbose=true" });
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(result.context.getBool("verbose"));
    }
    {
        var result = try parser.parse(&.{ "test", "--verbose=false" });
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(!result.context.getBool("verbose"));
    }
}

test "parser: bool flag numeric value is no longer accepted" {
    // Behavior change with finding 10: "1" was previously truthy.
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .help = "Verbose", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--verbose=1" });

    try std.testing.expectError(ParseError.InvalidValue, result);
}
