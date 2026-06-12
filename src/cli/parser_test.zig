// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Public-API tests for the argument parser.
//!
//! Covers flag parsing (long/short/equals forms), positionals, global
//! flags, parse errors, string-array flags, and run()-path lifecycle
//! behavior. All tests exercise the parser exclusively through its
//! public API (`Parser.init`, `Parser.parse`, public fields).

const std = @import("std");

const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;

const command = @import("command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

test "Parser initialization" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    const parser = Parser.init(std.testing.allocator, &root, "1.0.0", "TEST_");
    try std.testing.expectEqualStrings("1.0.0", parser.version);
    try std.testing.expectEqualStrings("TEST_", parser.env_prefix);
}

test "Parse long flag with value" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .string,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--config", "test.toml" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.getString("config") != null);
}

test "Parse boolean flag" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "verbose",
                .short = 'v',
                .help = "Verbose output",
                .ftype = .bool,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-v" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.getBool("verbose"));
}

test "parser: help flag returns help_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--help" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.help_requested);
}

test "parser: short help flag returns help_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-h" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.help_requested);
}

test "parser: version flag returns version_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--version" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.version_requested);
}

test "parser: short version flag returns version_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-V" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.version_requested);
}

test "parser: flag with equals syntax" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .string,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--config=test.toml" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("test.toml", result.context.getString("config").?);
}

test "parser: integer flag" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "port",
                .help = "Port number",
                .ftype = .int,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--port", "8080" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i64, 8080), result.context.getInt("port").?);
}

test "parser: float flag" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "rate",
                .help = "Rate value",
                .ftype = .float,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--rate", "3.14" });
    defer result.deinit(std.testing.allocator);

    // Float is stored in FlagValue, verify it was parsed
    const flag_val = result.context.getFlag("rate");
    try std.testing.expect(flag_val != null);
}

test "parser: subcommand parsing" {
    const subcmd = Command{
        .name = "run",
        .summary = "Run command",
    };
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .subcommands = &.{&subcmd},
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "run" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("run", result.command.name);
}

test "parser: positional arguments" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "arg1", "arg2", "arg3" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), result.context.positionals.items.len);
    try std.testing.expectEqualStrings("arg1", result.context.positionals.items[0]);
    try std.testing.expectEqualStrings("arg2", result.context.positionals.items[1]);
    try std.testing.expectEqualStrings("arg3", result.context.positionals.items[2]);
}

test "parser: double dash ends flags" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--", "--not-a-flag", "-x" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.context.positionals.items.len);
    try std.testing.expectEqualStrings("--not-a-flag", result.context.positionals.items[0]);
    try std.testing.expectEqualStrings("-x", result.context.positionals.items[1]);
}

test "parser: global flags quiet" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--quiet" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.quiet);
}

test "parser: global flags short quiet" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-q" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.quiet);
}

test "parser: global flags json" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--json" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.json);
}

test "parser: global flags plain" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--plain" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.plain);
}

test "parser: global flags no-color" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--no-color" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.no_color);
}

test "parser: global flags dry-run" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--dry-run" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.dry_run);
}

test "parser: global flags no-input" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--no-input" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.no_input);
}

test "parser: unknown flag returns error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--unknown" });

    try std.testing.expectError(ParseError.UnknownFlag, result);
}

test "parser: non-alphanumeric short flag is not matched (treated as unknown)" {
    // A short flag must be alphanumeric (see FlagSpec.short). A flag that
    // declares a non-alphanumeric short is uniformly inert: the parser does
    // not match it, mirroring help/completion output, which omit it.
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "evil", .short = '!', .help = "h", .ftype = .bool },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "-!" });
    try std.testing.expectError(ParseError.UnknownFlag, result);
}

test "parser: missing value returns error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .string,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--config" });

    try std.testing.expectError(ParseError.MissingValue, result);
}

test "parser: invalid integer returns error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "port",
                .help = "Port number",
                .ftype = .int,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--port", "not-a-number" });

    try std.testing.expectError(ParseError.InvalidValue, result);
}

test "parser: missing required flag returns error" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "required-flag",
                .help = "Required flag",
                .ftype = .string,
                .required = true,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{"test"});

    try std.testing.expectError(ParseError.MissingRequired, result);
}

test "parser: multiple short flags combined" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-qn" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.quiet);
    try std.testing.expect(result.context.dry_run);
}

test "parser: single dash as positional" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.context.positionals.items.len);
    try std.testing.expectEqualStrings("-", result.context.positionals.items[0]);
}

test "parser: empty args" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("test", result.command.name);
}

test "parser: string array flag single value" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "include",
                .help = "Include paths",
                .ftype = .string_array,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--include", "foo" });
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("include");
    try std.testing.expect(arr != null);
    try std.testing.expectEqual(@as(usize, 1), arr.?.len);
    try std.testing.expectEqualStrings("foo", arr.?[0]);
}

test "parser: string array flag multiple values" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "include",
                .help = "Include paths",
                .ftype = .string_array,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--include", "foo", "--include", "bar", "--include", "baz" });
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("include");
    try std.testing.expect(arr != null);
    try std.testing.expectEqual(@as(usize, 3), arr.?.len);
    try std.testing.expectEqualStrings("foo", arr.?[0]);
    try std.testing.expectEqualStrings("bar", arr.?[1]);
    try std.testing.expectEqualStrings("baz", arr.?[2]);
}

test "parser: string array flag comma-separated" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "include",
                .help = "Include paths",
                .ftype = .string_array,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--include", "foo,bar,baz" });
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("include");
    try std.testing.expect(arr != null);
    try std.testing.expectEqual(@as(usize, 3), arr.?.len);
    try std.testing.expectEqualStrings("foo", arr.?[0]);
    try std.testing.expectEqualStrings("bar", arr.?[1]);
    try std.testing.expectEqualStrings("baz", arr.?[2]);
}

test "parser: string array flag mixed repeated and comma" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "include",
                .help = "Include paths",
                .ftype = .string_array,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--include", "a,b", "--include", "c" });
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("include");
    try std.testing.expect(arr != null);
    try std.testing.expectEqual(@as(usize, 3), arr.?.len);
    try std.testing.expectEqualStrings("a", arr.?[0]);
    try std.testing.expectEqualStrings("b", arr.?[1]);
    try std.testing.expectEqualStrings("c", arr.?[2]);
}

test "parser: string array flag with equals syntax" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "include",
                .help = "Include paths",
                .ftype = .string_array,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--include=foo,bar" });
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("include");
    try std.testing.expect(arr != null);
    try std.testing.expectEqual(@as(usize, 2), arr.?.len);
    try std.testing.expectEqualStrings("foo", arr.?[0]);
    try std.testing.expectEqualStrings("bar", arr.?[1]);
}

// ============================================================================
// run() Lifecycle Tests (NQ-035)
// ============================================================================

test "run: help flag sets help_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--help" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.help_requested);
    try std.testing.expect(!result.version_requested);
}

test "run: version flag sets version_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .version = "1.0.0",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--version" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.version_requested);
    try std.testing.expect(!result.help_requested);
}

test "run: unknown flag returns UnknownFlag" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{ "test", "--unknown-flag" });

    try std.testing.expectError(ParseError.UnknownFlag, result);
}

test "run: missing required flag returns MissingRequired" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "required-flag",
                .help = "Required flag",
                .ftype = .string,
                .required = true,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    const result = parser.parse(&.{"test"});

    try std.testing.expectError(ParseError.MissingRequired, result);
}

test "run: quiet flag is parsed via run path" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--quiet" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.quiet);
}

test "run: json flag is parsed via run path" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--json" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.json);
}

test "run: no-color flag is parsed via run path" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--no-color" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.no_color);
}

test "run: command without run has isRunnable false" {
    const sub = Command{
        .name = "sub",
        .summary = "Subcommand",
    };
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .subcommands = &.{&sub},
    };

    try std.testing.expect(!root.isRunnable());
    try std.testing.expect(root.hasSubcommands());
}

test "run: default version is used when none specified" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "0.0.0", "");
    var result = try parser.parse(&.{ "test", "-V" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.version_requested);
    try std.testing.expectEqualStrings("0.0.0", parser.version);
}

test "run: short help flag sets help_requested" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "-h" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.help_requested);
}

test "run: dry-run flag is parsed" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "test", "--dry-run" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.dry_run);
}

test "run: no-input flag is parsed" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{ "test", "--no-input" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.context.no_input);
}

test "parser: empty string argv token becomes a positional" {
    // Pre-refactor code indexed arg[0] unconditionally and panicked on "".
    // The decomposed pipeline treats "" as a plain token -> positional.
    const root = Command{
        .name = "test",
        .summary = "Test command",
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    // argv[0] is the binary name; the second token is the empty string.
    var result = try parser.parse(&.{ "test", "" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.context.positionals.items.len);
    try std.testing.expectEqualStrings("", result.context.positionals.items[0]);
}
