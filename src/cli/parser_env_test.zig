// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Public-API tests for the argument parser: environment-variable
//! defaults, `default_str` defaults, and per-parse error-state handling.
//!
//! All tests exercise the parser exclusively through its public API
//! (`Parser.init`, `Parser.parse`, public fields).

const std = @import("std");
const builtin = @import("builtin");

const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const ParseError = parser_mod.ParseError;

const command = @import("command.zig");
const Command = command.Command;
const FlagSpec = command.FlagSpec;

test "parser: subcommand env defaults are applied" {
    // Use HOME which is set on all POSIX test systems
    if (comptime builtin.os.tag == .windows) return;

    // Verify HOME is set so this test is meaningful
    const home_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;

    const subcmd = Command{
        .name = "sub",
        .summary = "Subcommand",
        .flags = &.{
            .{
                .name = "sub-flag",
                .help = "A subcommand flag",
                .ftype = .string,
                .env = "HOME",
            },
        },
    };

    const root = Command{
        .name = "test",
        .summary = "Test",
        .subcommands = &.{&subcmd},
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{ "test", "sub" });
    defer result.deinit(std.testing.allocator);

    // The subcommand's flag should have been populated from the env var
    const val = result.context.getString("sub-flag");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings(home_val, val.?);
}

test "parser: root flag env still works (regression check)" {
    if (comptime builtin.os.tag == .windows) return;

    // Use HOME which is set on all POSIX test systems
    const home_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;

    const root = Command{
        .name = "test",
        .summary = "Test",
        .flags = &.{
            .{
                .name = "root-flag",
                .help = "A root flag",
                .ftype = .string,
                .env = "HOME",
            },
        },
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{"test"});
    defer result.deinit(std.testing.allocator);

    const val = result.context.getString("root-flag");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings(home_val, val.?);
}

test "parser: subcommand env flag does not override CLI flag" {
    // Verify CLI args take priority over env defaults for subcommand flags
    if (comptime builtin.os.tag == .windows) return;

    // Ensure HOME is set
    _ = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;

    const subcmd = Command{
        .name = "sub",
        .summary = "Subcommand",
        .flags = &.{
            .{
                .name = "sub-flag",
                .help = "A subcommand flag",
                .ftype = .string,
                .env = "HOME",
            },
        },
    };

    const root = Command{
        .name = "test",
        .summary = "Test",
        .subcommands = &.{&subcmd},
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{ "test", "sub", "--sub-flag", "explicit_value" });
    defer result.deinit(std.testing.allocator);

    // CLI value should take priority over env var
    const val = result.context.getString("sub-flag");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("explicit_value", val.?);
}

test "parser: invalid default_str surfaces InvalidValue with flag name" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "n",
                .help = "A numeric flag",
                .ftype = .int,
                .default_str = "not-a-number",
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    try std.testing.expectError(ParseError.InvalidValue, parser.parse(&.{"test"}));
    try std.testing.expect(parser.invalid_default_flag != null);
    try std.testing.expectEqualStrings("n", parser.invalid_default_flag.?);
}

test "parser: error state is reset between parse calls" {
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{
                .name = "name",
                .help = "Required name",
                .ftype = .string,
                .required = true,
            },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");

    // First parse fails and records diagnostic state.
    try std.testing.expectError(ParseError.MissingRequired, parser.parse(&.{"test"}));
    try std.testing.expectEqualStrings("name", parser.missing_required_flag.?);

    // Second parse with valid input must succeed and clear stale state.
    var result = try parser.parse(&.{ "test", "--name", "ok" });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), parser.env_parse_error_count);
    try std.testing.expectEqual(@as(usize, 0), parser.env_parse_errors_dropped);
    try std.testing.expect(parser.missing_required_flag == null);
    try std.testing.expect(parser.invalid_default_flag == null);
    try std.testing.expectEqualStrings("ok", result.context.getString("name").?);
}

// Validator used by the iter3-3 tests: rejects every value.
fn rejectAll(_: []const u8) bool {
    return false;
}

test "parser: CLI occurrences of string_array flag replace env-seeded values (iter3-2)" {
    // Documented precedence: flags > env. CLI occurrences of a repeatable
    // flag must REPLACE the env-seeded array, not append to it.
    if (comptime builtin.os.tag == .windows) return;

    const home_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;
    // A comma in HOME would split into multiple items; environment is too
    // unusual to test against.
    if (std.mem.indexOfScalar(u8, home_val, ',') != null) return;

    const root = Command{
        .name = "test",
        .summary = "Test",
        .flags = &.{
            .{
                .name = "tag",
                .help = "Tags",
                .ftype = .string_array,
                .env = "HOME",
                .is_repeatable = true,
            },
        },
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{ "test", "--tag", "b", "--tag", "c" });
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("tag").?;
    try std.testing.expectEqual(@as(usize, 2), arr.len);
    try std.testing.expectEqualStrings("b", arr[0]);
    try std.testing.expectEqualStrings("c", arr[1]);
}

test "parser: env still seeds string_array without CLI occurrences (iter3-2)" {
    if (comptime builtin.os.tag == .windows) return;

    const home_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;
    if (std.mem.indexOfScalar(u8, home_val, ',') != null) return;

    const root = Command{
        .name = "test",
        .summary = "Test",
        .flags = &.{
            .{
                .name = "tag",
                .help = "Tags",
                .ftype = .string_array,
                .env = "HOME",
                .is_repeatable = true,
            },
        },
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{"test"});
    defer result.deinit(std.testing.allocator);

    const arr = result.context.getStringArray("tag").?;
    try std.testing.expectEqual(@as(usize, 1), arr.len);
    try std.testing.expectEqualStrings(home_val, arr[0]);
}

test "parser: custom validator rejects env value -> flag unset, env error recorded (iter3-3)" {
    if (comptime builtin.os.tag == .windows) return;
    _ = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;

    const root = Command{
        .name = "test",
        .summary = "Test",
        .flags = &.{
            .{
                .name = "opt",
                .help = "Validated option",
                .ftype = .string,
                .env = "HOME",
                .validator = &rejectAll,
            },
        },
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{"test"});
    defer result.deinit(std.testing.allocator);

    // The env value failed validation: flag must NOT be set, and the
    // failure must be recorded in the env-parse-error channel.
    try std.testing.expect(result.context.getFlag("opt") == null);
    try std.testing.expectEqual(@as(usize, 1), p.env_parse_error_count);
    try std.testing.expectEqualStrings("opt", p.env_parse_errors[0].flag_name);
    try std.testing.expectEqualStrings("HOME", p.env_parse_errors[0].env_name);
}

test "parser: custom validator rejects default_str -> InvalidValue with flag name (iter3-3)" {
    const root = Command{
        .name = "test",
        .summary = "Test",
        .flags = &.{
            .{
                .name = "opt",
                .help = "Validated option",
                .ftype = .string,
                .default_str = "rejected-default",
                .validator = &rejectAll,
            },
        },
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    // A default that fails its own validator is a programmer error in the
    // command definition, just like an unparseable default.
    try std.testing.expectError(ParseError.InvalidValue, p.parse(&.{"test"}));
    try std.testing.expect(p.invalid_default_flag != null);
    try std.testing.expectEqualStrings("opt", p.invalid_default_flag.?);
}

test "parser: mid-chain command receives default_str and env defaults (iter3-5)" {
    if (comptime builtin.os.tag == .windows) return;
    const home_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("HOME") orelse return;

    const leaf = Command{
        .name = "leaf",
        .summary = "Leaf",
    };
    const mid = Command{
        .name = "mid",
        .summary = "Middle",
        .flags = &.{
            .{
                .name = "mid-def",
                .help = "Mid default",
                .ftype = .string,
                .default_str = "default-value",
            },
            .{
                .name = "mid-env",
                .help = "Mid env",
                .ftype = .string,
                .env = "HOME",
            },
        },
        .subcommands = &.{&leaf},
    };
    const root = Command{
        .name = "prog",
        .summary = "Root",
        .subcommands = &.{&mid},
    };

    var p = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try p.parse(&.{ "prog", "mid", "leaf" });
    defer result.deinit(std.testing.allocator);

    // Mid-chain commands must receive both default_str and env defaults,
    // not just root and leaf.
    const def_val = result.context.getString("mid-def");
    try std.testing.expect(def_val != null);
    try std.testing.expectEqualStrings("default-value", def_val.?);

    const env_val = result.context.getString("mid-env");
    try std.testing.expect(env_val != null);
    try std.testing.expectEqualStrings(home_val, env_val.?);
}

test "parser: env parse errors beyond cap are counted not lost" {
    if (comptime builtin.os.tag == .windows) return;

    // PATH is set on all POSIX test systems and never parses as an integer.
    const path_val = std.Io.Threaded.global_single_threaded.environ.process_environ.getPosix("PATH") orelse return;
    if (std.fmt.parseInt(i64, path_val, 10)) |_| {
        // Environment is too unusual to test against; skip.
        return;
    } else |_| {}

    // 10 int flags all bound to PATH: each one fails to parse, exceeding
    // the 8-entry env_parse_errors capacity by 2.
    const root = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "i0", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i1", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i2", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i3", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i4", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i5", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i6", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i7", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i8", .help = "h", .ftype = .int, .env = "PATH" },
            FlagSpec{ .name = "i9", .help = "h", .ftype = .int, .env = "PATH" },
        },
    };

    var parser = Parser.init(std.testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{"test"});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 8), parser.env_parse_error_count);
    try std.testing.expectEqual(@as(usize, 2), parser.env_parse_errors_dropped);
}
