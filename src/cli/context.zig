// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Flag specifications (FlagSpec/FlagType/SecretPolicy), parsed flag
//! values, and the execution context passed to command handlers.

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
/// 4. On `Context.deinit()`, string flag value *references* are cleared
///    from the flag map. The referenced bytes live in OS-owned argv/environ
///    memory and CANNOT be scrubbed by this library; OS-level exposure of
///    argv (e.g. /proc/<pid>/cmdline) is inherent. This is why secret
///    values must never be passed via flags or env in the first place.
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
    /// Short flag character (e.g., 'v' for -v). Must be alphanumeric:
    /// non-alphanumeric bytes are treated as "no short flag" uniformly by
    /// the parser, help, and every completion generator (they are never a
    /// valid short option and would be a shell-injection vector otherwise).
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

/// Minimal stdout/stderr writer wrapper that supports print/writeAll with
/// ephemeral buffering. Uses std.Io.Threaded.global_single_threaded.io().
pub const StdioWriter = struct {
    file: std.Io.File,

    pub fn print(self: StdioWriter, comptime fmt: []const u8, args: anytype) !void {
        var wbuf: [4096]u8 = undefined;
        var fw = self.file.writer(io_global(), &wbuf);
        try fw.interface.print(fmt, args);
        try fw.interface.flush();
    }

    pub fn writeAll(self: StdioWriter, data: []const u8) !void {
        var wbuf: [4096]u8 = undefined;
        var fw = self.file.writer(io_global(), &wbuf);
        try fw.interface.writeAll(data);
        try fw.interface.flush();
    }

    pub fn writeByte(self: StdioWriter, byte: u8) !void {
        return self.writeAll(&[_]u8{byte});
    }
};

inline fn io_global() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Command execution context
pub const Context = struct {
    /// Memory allocator
    allocator: Allocator,
    /// Standard output writer
    stdout: StdioWriter,
    /// Standard error writer
    stderr: StdioWriter,
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
        const stdout_file = std.Io.File.stdout();
        const stderr_file = std.Io.File.stderr();
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
            .stdout = .{ .file = stdout_file },
            .stderr = .{ .file = stderr_file },
            .is_tty_out = stdout_file.isTty(io_global()) catch false,
            .is_tty_err = stderr_file.isTty(io_global()) catch false,
            .flags = flags,
            .positionals = positionals,
            .command_path = command_path,
        };
    }

    /// Deinitialize the context.
    /// String flag value references are dropped from the map. NOTE: the
    /// underlying bytes are argv/environ-backed and are NOT zeroed — they
    /// cannot be scrubbed from library code. See `SecretPolicy` docs.
    pub fn deinit(self: *Context) void {
        // Clean up flag values: clear string references, free arrays
        var iter = self.flags.valueIterator();
        while (iter.next()) |val| {
            switch (val.*) {
                .string => {
                    // Clear the slice reference from the HashMap so that
                    // freed HashMap memory does not retain the pointer.
                    // The backing bytes (argv/environ) are NOT zeroed.
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

    /// Get a boolean flag value, or null when the flag has no value (not
    /// provided on the CLI, via env, or via a default). A type mismatch
    /// (the name resolves to a non-bool flag) is also treated as absent.
    /// `getBool` collapses "absent" to `false` for ergonomic everyday use;
    /// use this variant when callers must distinguish absent from false.
    pub fn getBoolOpt(self: *const Context, name: []const u8) ?bool {
        if (self.getFlag(name)) |v| {
            return switch (v) {
                .bool => |b| b,
                else => null,
            };
        }
        return null;
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

test "Context getBoolOpt distinguishes explicit false from absent" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("verbose", FlagValue{ .bool = false });
    try std.testing.expectEqual(@as(?bool, false), ctx.getBoolOpt("verbose"));
}

test "Context getBoolOpt returns null for missing flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(?bool, null), ctx.getBoolOpt("missing"));
}

test "Context getBoolOpt returns null for non-bool flag" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("flag", FlagValue{ .string = "true" });
    try std.testing.expectEqual(@as(?bool, null), ctx.getBoolOpt("flag"));
}

test "Context getBoolOpt returns true when flag set true" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.flags.put("verbose", FlagValue{ .bool = true });
    try std.testing.expectEqual(@as(?bool, true), ctx.getBoolOpt("verbose"));
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
