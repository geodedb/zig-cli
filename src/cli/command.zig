// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Command Module
//!
//! Core command tree definition for building CLI applications with
//! nested subcommands, flags, and lifecycle hooks.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Flag value types
pub const FlagType = enum {
    bool,
    int,
    float,
    string,
    path,
    string_array,

    pub fn format(self: FlagType) []const u8 {
        return switch (self) {
            .bool => "bool",
            .int => "int",
            .float => "float",
            .string => "string",
            .path => "path",
            .string_array => "string_array",
        };
    }
};

/// Secret handling policy
/// Controls how a flag's value may be provided, protecting secrets from
/// appearing in process listings and shell history.
///
/// **Workflow for secret flags:**
///
/// 1. Declare the flag with `.secret = .from_file_or_stdin`.
/// 2. The parser rejects `--token=<value>` on the command line and
///    rejects `$APP_TOKEN` from the environment (returns `SecretInFlagOrEnv`).
/// 3. Provide the secret via file (`--token-file /path/to/token`) or via
///    stdin (`echo $SECRET | myapp login`).
/// 4. On `Context.deinit()`, string flag values (including secrets) are
///    zeroed from the HashMap to reduce in-memory exposure.
///
/// **Example:**
/// ```
/// .{ .name = "token", .secret = .from_file_or_stdin, .ftype = .string, .help = "Auth token" },
/// .{ .name = "token-file", .ftype = .path, .help = "Path to token file" },
/// ```
pub const SecretPolicy = enum {
    /// Not a secret, can be passed via flags/env
    none,
    /// Must be provided via file or stdin, not flags/env
    from_file_or_stdin,
};

/// Flag specification for command-line arguments
pub const FlagSpec = struct {
    /// Long flag name (e.g., "verbose" for --verbose)
    name: []const u8,
    /// Short flag character (e.g., 'v' for -v)
    short: ?u8 = null,
    /// Help text for this flag
    help: []const u8,
    /// The type of value this flag accepts
    ftype: FlagType,
    /// Whether this flag is required
    required: bool = false,
    /// Default value as string (will be parsed)
    default_str: ?[]const u8 = null,
    /// Environment variable name for this flag
    env: ?[]const u8 = null,
    /// Whether this flag can be specified multiple times
    is_repeatable: bool = false,
    /// Whether this flag is deprecated
    is_deprecated: bool = false,
    /// Secret handling policy
    secret: SecretPolicy = .none,
    /// Custom validator function
    validator: ?*const fn ([]const u8) bool = null,
    /// Static completion values for shell completion
    completions: []const []const u8 = &.{},
    /// Dynamic completion function for shell completion
    complete_fn: ?*const fn ([]const u8) []const []const u8 = null,

    /// Get the display name for help text
    pub fn displayName(self: *const FlagSpec) []const u8 {
        return self.name;
    }

    /// Check if a value is valid for this flag
    pub fn validate(self: *const FlagSpec, value: []const u8) bool {
        if (self.validator) |v| {
            return v(value);
        }
        return true;
    }
};

/// Command execution context
pub const Context = struct {
    /// Memory allocator
    allocator: Allocator,
    /// Standard output writer
    stdout: std.fs.File.DeprecatedWriter,
    /// Standard error writer
    stderr: std.fs.File.DeprecatedWriter,
    /// Whether stdout is a TTY
    is_tty_out: bool,
    /// Whether stderr is a TTY
    is_tty_err: bool,
    /// Quiet mode (-q/--quiet)
    quiet: bool = false,
    /// JSON output mode (--json)
    json: bool = false,
    /// Plain output mode (--plain)
    plain: bool = false,
    /// Disable color output (--no-color or NO_COLOR env)
    no_color: bool = false,
    /// Dry run mode (-n/--dry-run)
    dry_run: bool = false,
    /// Non-interactive mode (--no-input)
    no_input: bool = false,
    /// Environment variable prefix for config
    env_prefix: []const u8 = "",
    /// Parsed flag values
    flags: std.StringHashMap(FlagValue),
    /// Positional arguments
    positionals: std.ArrayList([]const u8),
    /// The command path (e.g., ["kv", "get"])
    command_path: std.ArrayList([]const u8),

    /// Initialize a new context
    pub fn init(allocator: Allocator) Context {
        const stdout_file = std.fs.File.stdout();
        const stderr_file = std.fs.File.stderr();
        var flags = std.StringHashMap(FlagValue).init(allocator);
        // Pre-allocate for typical flag count (16 entries) to reduce
        // incremental rehashing during parsing.
        flags.ensureTotalCapacity(16) catch {};
        var positionals: std.ArrayList([]const u8) = .empty;
        positionals.ensureTotalCapacity(allocator, 8) catch {};
        var command_path: std.ArrayList([]const u8) = .empty;
        command_path.ensureTotalCapacity(allocator, 4) catch {};
        return .{
            .allocator = allocator,
            .stdout = stdout_file.deprecatedWriter(),
            .stderr = stderr_file.deprecatedWriter(),
            .is_tty_out = stdout_file.isTty(),
            .is_tty_err = stderr_file.isTty(),
            .flags = flags,
            .positionals = positionals,
            .command_path = command_path,
        };
    }

    /// Deinitialize the context.
    /// String flag values are zeroed before deallocation as a defense-in-depth
    /// measure to prevent secret values from lingering in freed heap memory.
    pub fn deinit(self: *Context) void {
        // Clean up flag values: zero strings, free arrays
        var iter = self.flags.valueIterator();
        while (iter.next()) |val| {
            switch (val.*) {
                .string => {
                    // Zero the slice metadata (pointer + length) so that
                    // freed HashMap memory does not retain references to
                    // potentially secret values.
                    val.* = FlagValue{ .string = "" };
                },
                .string_array => |*arr| arr.deinit(self.allocator),
                else => {},
            }
        }
        self.flags.deinit();
        self.positionals.deinit(self.allocator);
        self.command_path.deinit(self.allocator);
    }

    /// Get a flag value by name
    pub fn getFlag(self: *const Context, name: []const u8) ?FlagValue {
        return self.flags.get(name);
    }

    /// Get a string flag value
    pub fn getString(self: *const Context, name: []const u8) ?[]const u8 {
        if (self.getFlag(name)) |v| {
            return switch (v) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    /// Get a boolean flag value
    pub fn getBool(self: *const Context, name: []const u8) bool {
        if (self.getFlag(name)) |v| {
            return switch (v) {
                .bool => |b| b,
                else => false,
            };
        }
        return false;
    }

    /// Get an integer flag value
    pub fn getInt(self: *const Context, name: []const u8) ?i64 {
        if (self.getFlag(name)) |v| {
            return switch (v) {
                .int => |i| i,
                else => null,
            };
        }
        return null;
    }

    /// Get a floating-point flag value
    pub fn getFloat(self: *const Context, name: []const u8) ?f64 {
        if (self.getFlag(name)) |v| {
            return switch (v) {
                .float => |f| f,
                else => null,
            };
        }
        return null;
    }

    /// Get a string array flag value
    pub fn getStringArray(self: *const Context, name: []const u8) ?[]const []const u8 {
        if (self.getFlag(name)) |v| {
            return switch (v) {
                .string_array => |arr| arr.items,
                else => null,
            };
        }
        return null;
    }

    /// Write to stdout (respects quiet mode)
    pub fn print(self: *Context, comptime fmt: []const u8, args: anytype) !void {
        if (!self.quiet) {
            try self.stdout.print(fmt, args);
        }
    }

    /// Write to stderr (always writes, for errors/warnings)
    pub fn err(self: *Context, comptime fmt: []const u8, args: anytype) !void {
        try self.stderr.print(fmt, args);
    }

    /// Check if color should be used.
    ///
    /// Relies on `no_color` and `plain` fields which are already populated
    /// during parsing (from flags and env vars like NO_COLOR, TERM=dumb).
    /// No environment variable access is needed here.
    pub fn useColor(self: *const Context) bool {
        if (self.no_color or self.plain) return false;
        if (!self.is_tty_out) return false;
        return true;
    }
};

/// Parsed flag value
pub const FlagValue = union(enum) {
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    string_array: std.ArrayList([]const u8),

    // Note: FlagValue cleanup is handled by Context.deinit(), which has
    // access to the allocator needed to free string_array data. Individual
    // FlagValue instances should NOT be freed independently.
};

/// Command pre/post run hook type
pub const HookFn = *const fn (*Context) anyerror!void;

/// Command run function type
pub const RunFn = *const fn (*Context) anyerror!void;

/// Flag group type for validation
pub const FlagGroupType = enum {
    /// Flags that cannot be used together
    mutually_exclusive,
    /// Flags that must all be used together if any is used
    required_together,
    /// At least one flag from the group must be provided
    one_required,
};

/// Flag group definition
pub const FlagGroup = struct {
    /// Type of validation for this group
    group_type: FlagGroupType,
    /// Names of flags in this group
    flags: []const []const u8,
};

/// Argument validation error type
pub const ArgsValidationError = error{
    NoArgsExpected,
    ExactArgsMismatch,
    TooFewArgs,
    TooManyArgs,
    RangeArgsMismatch,
    InvalidArg,
};

/// Argument validation error details (for error messages)
pub const ArgsErrorDetails = union(enum) {
    no_args_expected: usize,
    exact_args: struct { expected: usize, got: usize },
    minimum_args: struct { min: usize, got: usize },
    maximum_args: struct { max: usize, got: usize },
    range_args: struct { min: usize, max: usize, got: usize },
    invalid_arg: []const u8,

    pub fn format(self: ArgsErrorDetails, buf: []u8) []const u8 {
        return switch (self) {
            .no_args_expected => |n| std.fmt.bufPrint(buf, "expected no arguments, got {d}", .{n}) catch "no arguments expected",
            .exact_args => |e| std.fmt.bufPrint(buf, "expected exactly {d} argument(s), got {d}", .{ e.expected, e.got }) catch "wrong argument count",
            .minimum_args => |m| std.fmt.bufPrint(buf, "expected at least {d} argument(s), got {d}", .{ m.min, m.got }) catch "too few arguments",
            .maximum_args => |m| std.fmt.bufPrint(buf, "expected at most {d} argument(s), got {d}", .{ m.max, m.got }) catch "too many arguments",
            .range_args => |r| std.fmt.bufPrint(buf, "expected {d}-{d} arguments, got {d}", .{ r.min, r.max, r.got }) catch "wrong argument count",
            .invalid_arg => |a| std.fmt.bufPrint(buf, "invalid argument: '{s}'", .{a}) catch "invalid argument",
        };
    }
};

/// Positional argument validation rules
pub const ArgsValidator = union(enum) {
    /// No positional arguments allowed
    none: void,
    /// Any number of arguments (no validation)
    arbitrary: void,
    /// Exactly N arguments required
    exact: usize,
    /// At least N arguments required
    minimum: usize,
    /// At most N arguments allowed
    maximum: usize,
    /// Between min and max arguments (inclusive)
    range: struct {
        min: usize,
        max: usize,
    },
    /// Only values from a predefined list.
    /// **Note:** Empty positional args (`args.len == 0`) are accepted
    /// silently -- this validator only rejects individual values not in
    /// the list. Combine with `.minimum` if at least one arg is required.
    only_valid: []const []const u8,

    /// Validate the given positional arguments.
    ///
    /// Delegates to `getErrorDetails` to avoid duplicating the validation
    /// logic, then maps the detail variant to the corresponding error.
    pub fn validate(self: ArgsValidator, args: []const []const u8) ArgsValidationError!void {
        if (self.getErrorDetails(args)) |details| {
            return switch (details) {
                .no_args_expected => ArgsValidationError.NoArgsExpected,
                .exact_args => ArgsValidationError.ExactArgsMismatch,
                .minimum_args => ArgsValidationError.TooFewArgs,
                .maximum_args => ArgsValidationError.TooManyArgs,
                .range_args => ArgsValidationError.RangeArgsMismatch,
                .invalid_arg => ArgsValidationError.InvalidArg,
            };
        }
    }

    /// Get error details for a validation failure
    pub fn getErrorDetails(self: ArgsValidator, args: []const []const u8) ?ArgsErrorDetails {
        switch (self) {
            .none => {
                if (args.len > 0) {
                    return ArgsErrorDetails{ .no_args_expected = args.len };
                }
            },
            .arbitrary => {},
            .exact => |n| {
                if (args.len != n) {
                    return ArgsErrorDetails{ .exact_args = .{ .expected = n, .got = args.len } };
                }
            },
            .minimum => |n| {
                if (args.len < n) {
                    return ArgsErrorDetails{ .minimum_args = .{ .min = n, .got = args.len } };
                }
            },
            .maximum => |n| {
                if (args.len > n) {
                    return ArgsErrorDetails{ .maximum_args = .{ .max = n, .got = args.len } };
                }
            },
            .range => |r| {
                if (args.len < r.min or args.len > r.max) {
                    return ArgsErrorDetails{ .range_args = .{ .min = r.min, .max = r.max, .got = args.len } };
                }
            },
            .only_valid => |valid_args| {
                for (args) |arg| {
                    var found = false;
                    for (valid_args) |valid| {
                        if (std.mem.eql(u8, arg, valid)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        return ArgsErrorDetails{ .invalid_arg = arg };
                    }
                }
            },
        }
        return null;
    }
};

/// Command definition
pub const Command = struct {
    /// Command name
    name: []const u8,
    /// Short summary for help (one line)
    summary: []const u8,
    /// Long help text (multiple paragraphs)
    long_help: []const u8 = "",
    /// Usage examples
    examples: []const []const u8 = &.{},
    /// Flag specifications
    flags: []const FlagSpec = &.{},
    /// Pre-run hook (runs only for this command)
    pre_run: ?HookFn = null,
    /// Main run function
    run: ?RunFn = null,
    /// Post-run hook (runs only for this command)
    post_run: ?HookFn = null,
    /// Persistent pre-run hook (runs for this command AND all subcommands)
    persistent_pre_run: ?HookFn = null,
    /// Persistent post-run hook (runs for this command AND all subcommands)
    persistent_post_run: ?HookFn = null,
    /// Command aliases
    aliases: []const []const u8 = &.{},
    /// Whether this command is hidden from help
    hidden: bool = false,
    /// Deprecation message (null if not deprecated)
    deprecated: ?[]const u8 = null,
    /// Subcommands
    subcommands: []const *const Command = &.{},
    /// Flag groups for validation (mutually exclusive, required together, etc.)
    flag_groups: []const FlagGroup = &.{},
    /// Positional argument validation rules
    args: ?ArgsValidator = null,
    /// Group name for organizing commands in help output
    group: []const u8 = "",
    /// Version string (e.g., "1.0.0")
    version: []const u8 = "",
    /// Active help messages for shell completion (displayed as hints during completion)
    /// These messages help guide users when typing commands
    active_help: []const []const u8 = &.{},
    /// Dynamic active help function - called during completion to generate contextual hints
    /// Return messages to display, or empty slice for no active help
    active_help_fn: ?*const fn (*const Command, []const []const u8) []const []const u8 = null,
    /// Author name for man page generation (optional)
    author: []const u8 = "",

    /// Find a subcommand by name or alias
    pub fn findSubcommand(self: *const Command, name: []const u8) ?*const Command {
        for (self.subcommands) |cmd| {
            if (std.mem.eql(u8, cmd.name, name)) {
                return cmd;
            }
            for (cmd.aliases) |alias| {
                if (std.mem.eql(u8, alias, name)) {
                    return cmd;
                }
            }
        }
        return null;
    }

    /// Find a flag by name
    pub fn findFlag(self: *const Command, name: []const u8) ?*const FlagSpec {
        for (self.flags) |*flag| {
            if (std.mem.eql(u8, flag.name, name)) {
                return flag;
            }
        }
        return null;
    }

    /// Find a flag by short character
    pub fn findFlagByShort(self: *const Command, short: u8) ?*const FlagSpec {
        for (self.flags) |*flag| {
            if (flag.short) |s| {
                if (s == short) {
                    return flag;
                }
            }
        }
        return null;
    }

    /// Return the number of visible (non-hidden) subcommands.
    ///
    /// Callers that need to iterate visible commands should loop over
    /// `subcommands` and skip entries where `.hidden` is true.
    pub fn visibleSubcommandCount(self: *const Command) usize {
        var count: usize = 0;
        for (self.subcommands) |cmd| {
            if (!cmd.hidden) count += 1;
        }
        return count;
    }

    /// Check if this command has any subcommands
    pub fn hasSubcommands(self: *const Command) bool {
        return self.subcommands.len > 0;
    }

    /// Check if this command is runnable
    pub fn isRunnable(self: *const Command) bool {
        return self.run != null;
    }

    /// Get the full usage string, reflecting whether this command
    /// accepts flags, subcommands, and/or positional arguments.
    pub fn usage(self: *const Command) []const u8 {
        const has_flags = self.flags.len > 0;
        const has_subcmds = self.subcommands.len > 0;

        if (has_flags and has_subcmds) {
            return "[flags] <command> [args]";
        } else if (has_flags) {
            return "[flags] [args]";
        } else if (has_subcmds) {
            return "<command> [args]";
        } else {
            return "[args]";
        }
    }
};

/// Global flags that apply to all commands
pub const global_flags: []const FlagSpec = &.{
    .{
        .name = "help",
        .short = 'h',
        .help = "Print help information",
        .ftype = .bool,
    },
    .{
        .name = "version",
        .short = 'V',
        .help = "Print version information",
        .ftype = .bool,
    },
    .{
        .name = "quiet",
        .short = 'q',
        .help = "Suppress non-essential output",
        .ftype = .bool,
    },
    .{
        .name = "json",
        .short = null,
        .help = "Output in JSON format",
        .ftype = .bool,
    },
    .{
        .name = "plain",
        .short = null,
        .help = "Output in plain text (no formatting)",
        .ftype = .bool,
    },
    .{
        .name = "no-color",
        .short = null,
        .help = "Disable colored output",
        .ftype = .bool,
    },
    .{
        .name = "dry-run",
        .short = 'n',
        .help = "Show what would be done without doing it",
        .ftype = .bool,
    },
    .{
        .name = "no-input",
        .short = null,
        .help = "Disable interactive prompts",
        .ftype = .bool,
    },
};

// ============================================================================
// Tests
// ============================================================================

test "FlagSpec validation" {
    const flag = FlagSpec{
        .name = "test",
        .help = "Test flag",
        .ftype = .string,
    };

    try std.testing.expect(flag.validate("any value"));
}

test "Command findSubcommand" {
    const sub = Command{
        .name = "sub",
        .summary = "Subcommand",
        .aliases = &.{"s"},
    };

    const root = Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&sub},
    };

    try std.testing.expect(root.findSubcommand("sub") != null);
    try std.testing.expect(root.findSubcommand("s") != null);
    try std.testing.expect(root.findSubcommand("unknown") == null);
}

test "Context initialization" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.quiet);
    try std.testing.expect(!ctx.json);
}

test "Context getFloat returns float value" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("threshold", FlagValue{ .float = 3.14 });
    try std.testing.expectEqual(@as(?f64, 3.14), ctx.getFloat("threshold"));
}

test "Context getFloat returns null for missing flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(?f64, null), ctx.getFloat("missing"));
}

test "Context getFloat returns null for non-float flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("count", FlagValue{ .int = 42 });
    try std.testing.expectEqual(@as(?f64, null), ctx.getFloat("count"));
}

// ============================================================================
// ArgsValidator Tests
// ============================================================================

test "ArgsValidator.none: allows zero args" {
    const v = ArgsValidator{ .none = {} };
    try v.validate(&.{});
}

test "ArgsValidator.none: rejects args" {
    const v = ArgsValidator{ .none = {} };
    const result = v.validate(&.{"unexpected"});
    try std.testing.expectError(ArgsValidationError.NoArgsExpected, result);
}

test "ArgsValidator.none: error details report count" {
    const v = ArgsValidator{ .none = {} };
    const details = v.getErrorDetails(&.{ "a", "b" });
    try std.testing.expect(details != null);
    switch (details.?) {
        .no_args_expected => |n| try std.testing.expectEqual(@as(usize, 2), n),
        else => return error.TestUnexpectedResult,
    }
}

test "ArgsValidator.arbitrary: allows zero args" {
    const v = ArgsValidator{ .arbitrary = {} };
    try v.validate(&.{});
}

test "ArgsValidator.arbitrary: allows many args" {
    const v = ArgsValidator{ .arbitrary = {} };
    try v.validate(&.{ "a", "b", "c", "d" });
}

test "ArgsValidator.exact: accepts matching count" {
    const v = ArgsValidator{ .exact = 3 };
    try v.validate(&.{ "a", "b", "c" });
}

test "ArgsValidator.exact: rejects too few" {
    const v = ArgsValidator{ .exact = 3 };
    const result = v.validate(&.{"a"});
    try std.testing.expectError(ArgsValidationError.ExactArgsMismatch, result);
}

test "ArgsValidator.exact: rejects too many" {
    const v = ArgsValidator{ .exact = 1 };
    const result = v.validate(&.{ "a", "b" });
    try std.testing.expectError(ArgsValidationError.ExactArgsMismatch, result);
}

test "ArgsValidator.exact: error details include expected and got" {
    const v = ArgsValidator{ .exact = 2 };
    const details = v.getErrorDetails(&.{"a"});
    try std.testing.expect(details != null);
    switch (details.?) {
        .exact_args => |e| {
            try std.testing.expectEqual(@as(usize, 2), e.expected);
            try std.testing.expectEqual(@as(usize, 1), e.got);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArgsValidator.minimum: accepts at boundary" {
    const v = ArgsValidator{ .minimum = 2 };
    try v.validate(&.{ "a", "b" });
}

test "ArgsValidator.minimum: accepts above boundary" {
    const v = ArgsValidator{ .minimum = 1 };
    try v.validate(&.{ "a", "b", "c" });
}

test "ArgsValidator.minimum: rejects below boundary" {
    const v = ArgsValidator{ .minimum = 3 };
    const result = v.validate(&.{ "a", "b" });
    try std.testing.expectError(ArgsValidationError.TooFewArgs, result);
}

test "ArgsValidator.minimum: error details include min and got" {
    const v = ArgsValidator{ .minimum = 5 };
    const details = v.getErrorDetails(&.{"x"});
    try std.testing.expect(details != null);
    switch (details.?) {
        .minimum_args => |m| {
            try std.testing.expectEqual(@as(usize, 5), m.min);
            try std.testing.expectEqual(@as(usize, 1), m.got);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArgsValidator.maximum: accepts below boundary" {
    const v = ArgsValidator{ .maximum = 3 };
    try v.validate(&.{"a"});
}

test "ArgsValidator.maximum: accepts at boundary" {
    const v = ArgsValidator{ .maximum = 2 };
    try v.validate(&.{ "a", "b" });
}

test "ArgsValidator.maximum: rejects above boundary" {
    const v = ArgsValidator{ .maximum = 1 };
    const result = v.validate(&.{ "a", "b" });
    try std.testing.expectError(ArgsValidationError.TooManyArgs, result);
}

test "ArgsValidator.maximum: error details include max and got" {
    const v = ArgsValidator{ .maximum = 2 };
    const details = v.getErrorDetails(&.{ "a", "b", "c" });
    try std.testing.expect(details != null);
    switch (details.?) {
        .maximum_args => |m| {
            try std.testing.expectEqual(@as(usize, 2), m.max);
            try std.testing.expectEqual(@as(usize, 3), m.got);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArgsValidator.range: accepts at min boundary" {
    const v = ArgsValidator{ .range = .{ .min = 2, .max = 4 } };
    try v.validate(&.{ "a", "b" });
}

test "ArgsValidator.range: accepts at max boundary" {
    const v = ArgsValidator{ .range = .{ .min = 1, .max = 3 } };
    try v.validate(&.{ "a", "b", "c" });
}

test "ArgsValidator.range: accepts within range" {
    const v = ArgsValidator{ .range = .{ .min = 1, .max = 5 } };
    try v.validate(&.{ "a", "b", "c" });
}

test "ArgsValidator.range: rejects below range" {
    const v = ArgsValidator{ .range = .{ .min = 2, .max = 4 } };
    const result = v.validate(&.{"a"});
    try std.testing.expectError(ArgsValidationError.RangeArgsMismatch, result);
}

test "ArgsValidator.range: rejects above range" {
    const v = ArgsValidator{ .range = .{ .min = 1, .max = 2 } };
    const result = v.validate(&.{ "a", "b", "c" });
    try std.testing.expectError(ArgsValidationError.RangeArgsMismatch, result);
}

test "ArgsValidator.range: error details include min, max, and got" {
    const v = ArgsValidator{ .range = .{ .min = 2, .max = 4 } };
    const details = v.getErrorDetails(&.{"a"});
    try std.testing.expect(details != null);
    switch (details.?) {
        .range_args => |r| {
            try std.testing.expectEqual(@as(usize, 2), r.min);
            try std.testing.expectEqual(@as(usize, 4), r.max);
            try std.testing.expectEqual(@as(usize, 1), r.got);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ArgsValidator.only_valid: accepts valid values" {
    const v = ArgsValidator{ .only_valid = &.{ "start", "stop", "restart" } };
    try v.validate(&.{ "start", "stop" });
}

test "ArgsValidator.only_valid: accepts single valid value" {
    const v = ArgsValidator{ .only_valid = &.{ "on", "off" } };
    try v.validate(&.{"off"});
}

test "ArgsValidator.only_valid: accepts empty args" {
    const v = ArgsValidator{ .only_valid = &.{ "a", "b" } };
    try v.validate(&.{});
}

test "ArgsValidator.only_valid: rejects invalid value" {
    const v = ArgsValidator{ .only_valid = &.{ "start", "stop" } };
    const result = v.validate(&.{"pause"});
    try std.testing.expectError(ArgsValidationError.InvalidArg, result);
}

test "ArgsValidator.only_valid: rejects mixed valid and invalid" {
    const v = ArgsValidator{ .only_valid = &.{ "start", "stop" } };
    const result = v.validate(&.{ "start", "invalid" });
    try std.testing.expectError(ArgsValidationError.InvalidArg, result);
}

test "ArgsValidator.only_valid: error details include invalid arg name" {
    const v = ArgsValidator{ .only_valid = &.{ "a", "b" } };
    const details = v.getErrorDetails(&.{"bad"});
    try std.testing.expect(details != null);
    switch (details.?) {
        .invalid_arg => |a| try std.testing.expectEqualStrings("bad", a),
        else => return error.TestUnexpectedResult,
    }
}

// ============================================================================
// Context Accessor Tests
// ============================================================================

test "Context getString returns string value" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("name", FlagValue{ .string = "hello" });
    try std.testing.expectEqualStrings("hello", ctx.getString("name").?);
}

test "Context getString returns null for missing flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), ctx.getString("missing"));
}

test "Context getString returns null for non-string flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("flag", FlagValue{ .bool = true });
    try std.testing.expectEqual(@as(?[]const u8, null), ctx.getString("flag"));
}

test "Context getBool returns true" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("verbose", FlagValue{ .bool = true });
    try std.testing.expect(ctx.getBool("verbose"));
}

test "Context getBool returns false for missing flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.getBool("missing"));
}

test "Context getBool returns false for non-bool flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("flag", FlagValue{ .string = "true" });
    try std.testing.expect(!ctx.getBool("flag"));
}

test "Context getInt returns integer value" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("port", FlagValue{ .int = 8080 });
    try std.testing.expectEqual(@as(?i64, 8080), ctx.getInt("port"));
}

test "Context getInt returns null for missing flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(?i64, null), ctx.getInt("missing"));
}

test "Context getInt returns null for non-int flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("flag", FlagValue{ .float = 3.14 });
    try std.testing.expectEqual(@as(?i64, null), ctx.getInt("flag"));
}

test "Context getInt handles negative values" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("offset", FlagValue{ .int = -42 });
    try std.testing.expectEqual(@as(?i64, -42), ctx.getInt("offset"));
}

test "Context getStringArray returns array items" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    var arr: std.ArrayList([]const u8) = .empty;
    try arr.append(std.testing.allocator, "one");
    try arr.append(std.testing.allocator, "two");
    try arr.append(std.testing.allocator, "three");
    try ctx.flags.put("tags", FlagValue{ .string_array = arr });

    const result = ctx.getStringArray("tags");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 3), result.?.len);
    try std.testing.expectEqualStrings("one", result.?[0]);
    try std.testing.expectEqualStrings("two", result.?[1]);
    try std.testing.expectEqualStrings("three", result.?[2]);
}

test "Context getStringArray returns null for missing flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(?[]const []const u8, null), ctx.getStringArray("missing"));
}

test "Context getStringArray returns null for non-array flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("flag", FlagValue{ .string = "not-an-array" });
    try std.testing.expectEqual(@as(?[]const []const u8, null), ctx.getStringArray("flag"));
}

test "Context getFlag returns exact FlagValue" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("count", FlagValue{ .int = 99 });
    const val = ctx.getFlag("count");
    try std.testing.expect(val != null);
    switch (val.?) {
        .int => |i| try std.testing.expectEqual(@as(i64, 99), i),
        else => return error.TestUnexpectedResult,
    }
}

test "Context getFlag returns null for missing key" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(ctx.getFlag("nonexistent") == null);
}

// ============================================================================
// Command findFlag and findFlagByShort Tests
// ============================================================================

test "Command findFlag finds by name" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
            FlagSpec{ .name = "config", .short = 'c', .help = "Config file", .ftype = .string },
        },
    };

    const flag = cmd.findFlag("config");
    try std.testing.expect(flag != null);
    try std.testing.expectEqualStrings("config", flag.?.name);
}

test "Command findFlag returns null for unknown name" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .help = "Verbose", .ftype = .bool },
        },
    };

    try std.testing.expect(cmd.findFlag("missing") == null);
}

test "Command findFlag with empty flags" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
    };

    try std.testing.expect(cmd.findFlag("anything") == null);
}

test "Command findFlagByShort finds by short character" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
            FlagSpec{ .name = "config", .short = 'c', .help = "Config file", .ftype = .string },
        },
    };

    const flag = cmd.findFlagByShort('v');
    try std.testing.expect(flag != null);
    try std.testing.expectEqualStrings("verbose", flag.?.name);
}

test "Command findFlagByShort returns null for unknown short" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
        },
    };

    try std.testing.expect(cmd.findFlagByShort('x') == null);
}

test "Command findFlagByShort skips flags without short" {
    const cmd = Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            FlagSpec{ .name = "config", .help = "Config file", .ftype = .string },
            FlagSpec{ .name = "output", .short = 'o', .help = "Output", .ftype = .string },
        },
    };

    const flag = cmd.findFlagByShort('o');
    try std.testing.expect(flag != null);
    try std.testing.expectEqualStrings("output", flag.?.name);
}

// ============================================================================
// FlagType and FlagValue Tests
// ============================================================================

test "FlagType format returns correct strings" {
    try std.testing.expectEqualStrings("bool", FlagType.bool.format());
    try std.testing.expectEqualStrings("int", FlagType.int.format());
    try std.testing.expectEqualStrings("float", FlagType.float.format());
    try std.testing.expectEqualStrings("string", FlagType.string.format());
    try std.testing.expectEqualStrings("path", FlagType.path.format());
    try std.testing.expectEqualStrings("string_array", FlagType.string_array.format());
}

test "FlagSpec displayName returns name" {
    const flag = FlagSpec{
        .name = "my-flag",
        .help = "A test flag",
        .ftype = .string,
    };
    try std.testing.expectEqualStrings("my-flag", flag.displayName());
}

test "FlagSpec validate with no validator returns true" {
    const flag = FlagSpec{
        .name = "test",
        .help = "Test flag",
        .ftype = .string,
    };
    try std.testing.expect(flag.validate("anything"));
}

fn rejectEmpty(value: []const u8) bool {
    return value.len > 0;
}

test "FlagSpec validate with custom validator" {
    const flag = FlagSpec{
        .name = "test",
        .help = "Test flag",
        .ftype = .string,
        .validator = &rejectEmpty,
    };
    try std.testing.expect(flag.validate("hello"));
    try std.testing.expect(!flag.validate(""));
}

// ============================================================================
// ArgsErrorDetails format Tests
// ============================================================================

test "ArgsErrorDetails format no_args_expected" {
    const details = ArgsErrorDetails{ .no_args_expected = 3 };
    var buf: [256]u8 = undefined;
    const msg = details.format(&buf);
    try std.testing.expectEqualStrings("expected no arguments, got 3", msg);
}

test "ArgsErrorDetails format exact_args" {
    const details = ArgsErrorDetails{ .exact_args = .{ .expected = 2, .got = 5 } };
    var buf: [256]u8 = undefined;
    const msg = details.format(&buf);
    try std.testing.expectEqualStrings("expected exactly 2 argument(s), got 5", msg);
}

test "ArgsErrorDetails format minimum_args" {
    const details = ArgsErrorDetails{ .minimum_args = .{ .min = 3, .got = 1 } };
    var buf: [256]u8 = undefined;
    const msg = details.format(&buf);
    try std.testing.expectEqualStrings("expected at least 3 argument(s), got 1", msg);
}

test "ArgsErrorDetails format maximum_args" {
    const details = ArgsErrorDetails{ .maximum_args = .{ .max = 2, .got = 5 } };
    var buf: [256]u8 = undefined;
    const msg = details.format(&buf);
    try std.testing.expectEqualStrings("expected at most 2 argument(s), got 5", msg);
}

test "ArgsErrorDetails format range_args" {
    const details = ArgsErrorDetails{ .range_args = .{ .min = 1, .max = 3, .got = 5 } };
    var buf: [256]u8 = undefined;
    const msg = details.format(&buf);
    try std.testing.expectEqualStrings("expected 1-3 arguments, got 5", msg);
}

test "ArgsErrorDetails format invalid_arg" {
    const details = ArgsErrorDetails{ .invalid_arg = "badval" };
    var buf: [256]u8 = undefined;
    const msg = details.format(&buf);
    try std.testing.expectEqualStrings("invalid argument: 'badval'", msg);
}

// ============================================================================
// Command utility method Tests
// ============================================================================

test "Command hasSubcommands true" {
    const sub = Command{ .name = "sub", .summary = "Sub" };
    const cmd = Command{
        .name = "root",
        .summary = "Root",
        .subcommands = &.{&sub},
    };
    try std.testing.expect(cmd.hasSubcommands());
}

test "Command hasSubcommands false" {
    const cmd = Command{ .name = "root", .summary = "Root" };
    try std.testing.expect(!cmd.hasSubcommands());
}

test "Command isRunnable true" {
    const runFn = struct {
        fn run(_: *Context) anyerror!void {}
    }.run;
    const cmd = Command{
        .name = "root",
        .summary = "Root",
        .run = &runFn,
    };
    try std.testing.expect(cmd.isRunnable());
}

test "Command isRunnable false" {
    const cmd = Command{ .name = "root", .summary = "Root" };
    try std.testing.expect(!cmd.isRunnable());
}

test "Command findSubcommand by alias" {
    const sub = Command{
        .name = "subcommand",
        .summary = "A subcommand",
        .aliases = &.{ "sub", "sc" },
    };
    const root = Command{
        .name = "root",
        .summary = "Root",
        .subcommands = &.{&sub},
    };
    try std.testing.expect(root.findSubcommand("sc") != null);
    try std.testing.expectEqualStrings("subcommand", root.findSubcommand("sc").?.name);
}

test "Context useColor returns false when no_color is set" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();
    ctx.no_color = true;
    try std.testing.expect(!ctx.useColor());
}

test "Context useColor returns false when plain is set" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();
    ctx.plain = true;
    try std.testing.expect(!ctx.useColor());
}
