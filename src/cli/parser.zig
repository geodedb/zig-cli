// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Parser Module
//!
//! Command-line argument parser with support for flags, subcommands,
//! and positional arguments. Implements order-independent parsing.

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const command = @import("command.zig");
const Command = command.Command;
const Context = command.Context;
const FlagSpec = command.FlagSpec;
const FlagValue = command.FlagValue;
const FlagType = command.FlagType;
const SecretPolicy = command.SecretPolicy;
const FlagGroup = command.FlagGroup;
const FlagGroupType = command.FlagGroupType;
const ArgsValidator = command.ArgsValidator;
const ArgsValidationError = command.ArgsValidationError;
const ArgsErrorDetails = command.ArgsErrorDetails;
const help = @import("help.zig");

// Env/default-value machinery and error rendering live in sibling files.
// The mutual file imports (parser.zig <-> parser/env.zig) are legal in
// Zig within a module; the help/ split uses the same pattern.
const env_defaults = @import("parser/env.zig");
const format = @import("parser/format.zig");
const validate = @import("parser/validate.zig");

/// Parse errors
pub const ParseError = error{
    UnknownFlag,
    UnknownCommand,
    MissingValue,
    InvalidValue,
    MissingRequired,
    SecretInFlagOrEnv,
    HelpRequested,
    VersionRequested,
    OutOfMemory,
    MutuallyExclusiveFlags,
    RequiredTogetherFlags,
    OneRequiredFlags,
    InvalidArgs,
};

/// Parse result
pub const ParseResult = struct {
    /// The resolved command to execute
    command: *const Command,
    /// Execution context with parsed values
    context: Context,
    /// Whether help was requested
    help_requested: bool = false,
    /// Whether version was requested
    version_requested: bool = false,
    /// Chain of commands from root to current (for persistent hooks)
    command_chain: std.ArrayList(*const Command),
    /// Allocator used during parsing (stored so deinit does not require it)
    allocator: Allocator,

    /// Clean up all allocated resources.
    /// The allocator parameter is accepted for backward compatibility but ignored;
    /// the stored allocator is always used.
    pub fn deinit(self: *ParseResult, _: Allocator) void {
        self.command_chain.deinit(self.allocator);
        self.context.deinit();
    }
};

/// Argument parser
pub const Parser = struct {
    allocator: Allocator,
    root: *const Command,
    version: []const u8,
    env_prefix: []const u8,
    /// Name of missing required flag (for error reporting)
    missing_required_flag: ?[]const u8 = null,
    /// Name of the flag whose value was missing (for error reporting)
    missing_value_flag: ?[]const u8 = null,
    /// Current command being parsed (for error reporting)
    current_command: ?*const Command = null,
    /// Conflicting flags for mutually exclusive error
    conflicting_flags: ?[2][]const u8 = null,
    /// Missing flags for required together error
    missing_together_flags: ?[]const []const u8 = null,
    /// Group name for one required error
    one_required_group: ?[]const []const u8 = null,
    /// Name of secret flag rejected via flag/env (for error reporting)
    secret_flag_name: ?[]const u8 = null,
    /// Args validation error details
    args_error: ?ArgsErrorDetails = null,
    /// Env parse errors collected during applyEnvDefaults.
    /// **Limit:** At most 8 errors are tracked in detail. Failures beyond
    /// this limit are counted in `env_parse_errors_dropped` (the flag still
    /// won't be set, and the count is surfaced in error rendering).
    env_parse_errors: [8]EnvParseErrorEntry = .{EnvParseErrorEntry{}} ** 8,
    /// Number of env parse errors recorded (capped at env_parse_errors.len)
    env_parse_error_count: usize = 0,
    /// Number of env parse errors that could not be recorded because
    /// `env_parse_errors` was already full (NQ-NEW-013)
    env_parse_errors_dropped: usize = 0,
    /// Name of the flag whose `default_str` failed to parse or validate
    /// (for error reporting). An invalid default is a programmer error in
    /// the command definition (GAP-0097).
    invalid_default_flag: ?[]const u8 = null,
    /// Index into `env_parse_errors` when an `InvalidValue` error was
    /// promoted from an environment-variable failure (a required flag
    /// whose env value could not be parsed/validated). Null when the
    /// `InvalidValue` came from a CLI value or a default, so diagnostics
    /// only render the env message when env was actually the cause.
    invalid_value_env_index: ?usize = null,

    const Self = @This();

    /// Record of an environment variable parse failure.
    /// Defined in parser/env.zig; re-exported here for API stability.
    pub const EnvParseErrorEntry = env_defaults.EnvParseErrorEntry;

    /// Initialize a new parser
    pub fn init(
        allocator: Allocator,
        root: *const Command,
        version: []const u8,
        env_prefix: []const u8,
    ) Self {
        return .{
            .allocator = allocator,
            .root = root,
            .version = version,
            .env_prefix = env_prefix,
        };
    }

    /// Reset all per-parse diagnostic state so a Parser instance can be
    /// reused across multiple parse() calls without leaking stale error
    /// context from a previous invocation (NQ-NEW-011).
    fn resetErrorState(self: *Self) void {
        self.missing_required_flag = null;
        self.missing_value_flag = null;
        self.current_command = null;
        self.conflicting_flags = null;
        self.missing_together_flags = null;
        self.one_required_group = null;
        self.secret_flag_name = null;
        self.args_error = null;
        self.env_parse_error_count = 0;
        self.env_parse_errors_dropped = 0;
        self.invalid_default_flag = null;
        self.invalid_value_env_index = null;
        // env_parse_errors entries are overwritten on next use; only the
        // count gates reads, so the array itself needs no zeroing.
    }

    /// Result of consuming one argv token in the parse loop.
    const TokenOutcome = union(enum) {
        /// Continue scanning at this argv index.
        next: usize,
        /// `--help`/`-h` was encountered; return immediately.
        help,
        /// `--version`/`-V` was encountered; return immediately.
        version,
    };

    /// Parse command-line arguments.
    ///
    /// Runs as a phase pipeline: reset per-parse diagnostic state, set up
    /// the context and command chain, apply environment context defaults
    /// (NO_COLOR/TERM), consume argv tokens one at a time (flags,
    /// subcommands, positionals), then finalize (chain-wide env defaults,
    /// default values, and required/group/args validation).
    pub fn parse(self: *Self, argv: []const []const u8) ParseError!ParseResult {
        self.resetErrorState();

        var ctx = Context.init(self.allocator);
        errdefer ctx.deinit();
        ctx.env_prefix = self.env_prefix;

        // Track command chain for persistent hooks (pre-allocate for typical 4-level depth)
        var command_chain: std.ArrayList(*const Command) = .empty;
        errdefer command_chain.deinit(self.allocator);
        command_chain.ensureTotalCapacity(self.allocator, 4) catch return ParseError.OutOfMemory;
        command_chain.append(self.allocator, self.root) catch return ParseError.OutOfMemory;

        // Apply environment-based context defaults (NO_COLOR, TERM=dumb).
        // Env-bound flag defaults are applied during finalize, AFTER the
        // argv loop, so CLI values always take precedence -- including for
        // repeatable string_array flags, which would otherwise append to an
        // env-seeded array (iter3 finding 2).
        env_defaults.applyEnvContextDefaults(&ctx);

        var current_cmd = self.root;
        self.current_command = self.root;

        // Skip program name
        var i: usize = if (argv.len > 0) 1 else 0;

        while (i < argv.len) {
            const arg = argv[i];
            const outcome = if (mem.startsWith(u8, arg, "--"))
                try self.handleLongToken(&ctx, current_cmd, command_chain.items, argv, i)
            else if (mem.startsWith(u8, arg, "-") and arg.len > 1)
                try self.handleShortToken(&ctx, current_cmd, command_chain.items, argv, i)
            else
                try self.handlePlainToken(&ctx, &command_chain, &current_cmd, arg, i);

            switch (outcome) {
                .next => |next_i| i = next_i,
                .help => return earlyResult(self.allocator, current_cmd, ctx, command_chain, true),
                .version => return earlyResult(self.allocator, current_cmd, ctx, command_chain, false),
            }
        }

        try self.finalize(&ctx, command_chain.items);

        return ParseResult{
            .command = current_cmd,
            .context = ctx,
            .command_chain = command_chain,
            .allocator = self.allocator,
        };
    }

    /// Build a ParseResult for an early `--help`/`--version` exit.
    /// Matches historical behavior: help/version return before defaults
    /// and validation run.
    fn earlyResult(
        allocator: Allocator,
        cmd: *const Command,
        ctx: Context,
        chain: std.ArrayList(*const Command),
        is_help: bool,
    ) ParseResult {
        return .{
            .command = cmd,
            .context = ctx,
            .help_requested = is_help,
            .version_requested = !is_help,
            .command_chain = chain,
            .allocator = allocator,
        };
    }

    /// Consume one `--`-prefixed token: bare `--` (end of flags),
    /// `--flag=value`, `--flag [value]`, the built-in `--help`/`--version`,
    /// or a global flag.
    fn handleLongToken(
        self: *Self,
        ctx: *Context,
        cmd: *const Command,
        chain: []const *const Command,
        argv: []const []const u8,
        i: usize,
    ) ParseError!TokenOutcome {
        const flag_part = argv[i][2..];

        // Handle -- (end of flags): rest are positionals
        if (flag_part.len == 0) {
            for (argv[i + 1 ..]) |rest| {
                ctx.positionals.append(ctx.allocator, rest) catch return ParseError.OutOfMemory;
            }
            return .{ .next = argv.len };
        }

        // Check for --flag=value format
        if (mem.indexOf(u8, flag_part, "=")) |eq_pos| {
            const name = flag_part[0..eq_pos];
            const value = flag_part[eq_pos + 1 ..];
            if (self.findFlagInFullChain(cmd, chain, name) != null) {
                try self.handleFlagWithChain(ctx, cmd, chain, name, value);
                return .{ .next = i + 1 };
            }
            // Fall through to global flags (e.g. --quiet=true)
            return self.handleGlobalFlagEquals(ctx, name, value, i);
        }

        // Check if it's a boolean flag or needs a value
        if (self.findFlagInFullChain(cmd, chain, flag_part)) |flag| {
            if (flag.ftype == .bool) {
                try self.handleFlagWithChain(ctx, cmd, chain, flag_part, "true");
                return .{ .next = i + 1 };
            }
            // Need next arg as value
            if (i + 1 >= argv.len) {
                self.missing_value_flag = flag.name;
                return ParseError.MissingValue;
            }
            try self.handleFlagWithChain(ctx, cmd, chain, flag_part, argv[i + 1]);
            return .{ .next = i + 2 };
        }

        // Check global flags
        if (mem.eql(u8, flag_part, "help")) return .help;
        if (mem.eql(u8, flag_part, "version")) return .version;

        // Handle other global flags
        try self.handleGlobalFlag(ctx, flag_part);
        return .{ .next = i + 1 };
    }

    /// Consume one `-x`/`-xyz` short-flag token. Combined boolean short
    /// flags are all applied; a non-boolean short flag is only legal in
    /// the last position, where it consumes the next argv entry as its
    /// value. A value-taking short flag anywhere else in the cluster is
    /// a `MissingValue` error (it has no token to consume).
    fn handleShortToken(
        self: *Self,
        ctx: *Context,
        cmd: *const Command,
        chain: []const *const Command,
        argv: []const []const u8,
        i: usize,
    ) ParseError!TokenOutcome {
        const flags = argv[i][1..];
        var next = i + 1;
        for (flags, 0..) |c, j| {
            if (c == 'h') return .help;
            if (c == 'V') return .version;

            if (self.findFlagByShortInFullChain(cmd, chain, c)) |flag| {
                if (flag.ftype == .bool) {
                    // Route through the same guarded path as long flags so
                    // secret-policy and validator checks apply.
                    try self.handleFlagWithChain(ctx, cmd, chain, flag.name, "true");
                } else if (j == flags.len - 1) {
                    // Last short flag, next arg is value
                    if (i + 1 >= argv.len) {
                        self.missing_value_flag = flag.name;
                        return ParseError.MissingValue;
                    }
                    try self.handleFlagWithChain(ctx, cmd, chain, flag.name, argv[i + 1]);
                    next = i + 2;
                } else {
                    // Mid-cluster value flag has no token to consume as
                    // its value; report it instead of dropping the flag.
                    self.missing_value_flag = flag.name;
                    return ParseError.MissingValue;
                }
            } else {
                try self.handleGlobalShortFlag(ctx, c);
            }
        }
        return .{ .next = next };
    }

    /// Consume one non-flag token: a single `-` (stdin/stdout placeholder)
    /// is recorded as a positional; anything else is resolved as a
    /// subcommand or appended as a positional.
    fn handlePlainToken(
        self: *Self,
        ctx: *Context,
        command_chain: *std.ArrayList(*const Command),
        current_cmd: **const Command,
        arg: []const u8,
        i: usize,
    ) ParseError!TokenOutcome {
        if (arg.len == 1 and arg[0] == '-') {
            // Single dash means stdin/stdout
            ctx.positionals.append(ctx.allocator, arg) catch return ParseError.OutOfMemory;
            return .{ .next = i + 1 };
        }
        try self.resolveSubcommand(ctx, command_chain, current_cmd, arg);
        return .{ .next = i + 1 };
    }

    /// Resolve a bare token against the current command's subcommands:
    /// descend into a matching subcommand (updating the command chain and
    /// command path) or record the token as a positional.
    fn resolveSubcommand(
        self: *Self,
        ctx: *Context,
        command_chain: *std.ArrayList(*const Command),
        current_cmd: **const Command,
        arg: []const u8,
    ) ParseError!void {
        if (current_cmd.*.findSubcommand(arg)) |subcmd| {
            current_cmd.* = subcmd;
            self.current_command = subcmd;
            ctx.command_path.append(ctx.allocator, arg) catch return ParseError.OutOfMemory;
            // Track command chain for persistent hooks
            command_chain.append(self.allocator, subcmd) catch return ParseError.OutOfMemory;
        } else {
            ctx.positionals.append(ctx.allocator, arg) catch return ParseError.OutOfMemory;
        }
    }

    /// Finalization phase: walk the full resolved command chain (root
    /// through leaf) applying env defaults, then `default_str` defaults
    /// (both skip flags already set, so CLI values win and env beats
    /// defaults), then run required-flag and flag-group validation for
    /// every command in the chain. Positional-args validation applies to
    /// the leaf only (iter3 findings 2, 4, 5).
    fn finalize(self: *Self, ctx: *Context, chain: []const *const Command) ParseError!void {
        // Env defaults for the whole chain first: env has priority over
        // default_str, so all env values must land before any default.
        for (chain) |c| try env_defaults.applyEnvDefaultsForCommand(self, ctx, c);
        for (chain) |c| try env_defaults.applyDefaultsForCommand(self, ctx, c);

        // Required flags and flag groups are enforced chain-wide: a root
        // flag marked required must not pass silently when a subcommand
        // runs, and ancestor flag-group constraints span the chain.
        for (chain) |c| try validate.checkRequired(self, ctx, c);
        for (chain) |c| try validate.checkFlagGroups(self, ctx, c);

        // Positional rules belong to the resolved leaf command.
        try validate.checkArgs(self, ctx, chain[chain.len - 1]);
    }

    /// Walk the full command chain for flag lookup.
    fn handleFlagWithChain(
        self: *Self,
        ctx: *Context,
        cmd: *const Command,
        chain: []const *const Command,
        name: []const u8,
        value: []const u8,
    ) ParseError!void {
        if (self.findFlagInFullChain(cmd, chain, name)) |flag| {
            if (flag.secret == .from_file_or_stdin) {
                self.secret_flag_name = flag.name;
                return ParseError.SecretInFlagOrEnv;
            }
            if (!flag.validate(value)) {
                return ParseError.InvalidValue;
            }
            if (flag.ftype == .string_array) {
                try self.appendToStringArray(ctx, name, value);
            } else {
                const fval = try self.parseValue(flag.ftype, value);
                try self.setFlagValue(ctx, name, fval);
            }
        } else {
            return ParseError.UnknownFlag;
        }
    }

    /// Apply a global flag by name to the Context. Flag names are validated
    /// against `command.global_flags` -- the single canonical list -- so that
    /// adding a new global flag only requires updating that list and the
    /// `applyGlobalFlagToContext` mapping below. Returns `UnknownFlag` for
    /// unrecognised names.
    fn handleGlobalFlag(self: *Self, ctx: *Context, name: []const u8) ParseError!void {
        _ = self;
        // Validate against canonical global_flags list
        for (command.global_flags) |*gf| {
            if (mem.eql(u8, gf.name, name)) {
                applyGlobalFlagToContext(ctx, name);
                return;
            }
        }
        return ParseError.UnknownFlag;
    }

    /// Apply `--name=value` syntax for a global flag. All global flags are
    /// boolean, so the value must be exactly "true" or "false" (anything
    /// else is `InvalidValue`). `--help=true`/`--version=true` behave like
    /// their bare forms; a "false" value is a no-op. Returns `UnknownFlag`
    /// for names not in the canonical `command.global_flags` list.
    fn handleGlobalFlagEquals(self: *Self, ctx: *Context, name: []const u8, value: []const u8, i: usize) ParseError!TokenOutcome {
        for (command.global_flags) |*gf| {
            if (!mem.eql(u8, gf.name, name)) continue;
            const enabled = (try self.parseValue(.bool, value)).bool;
            if (enabled) {
                if (mem.eql(u8, name, "help")) return .help;
                if (mem.eql(u8, name, "version")) return .version;
                applyGlobalFlagToContext(ctx, name);
            }
            return .{ .next = i + 1 };
        }
        return ParseError.UnknownFlag;
    }

    /// Map a short global flag character to its long name via
    /// `command.global_flags`, then apply. Returns `UnknownFlag` for
    /// unrecognised characters.
    fn handleGlobalShortFlag(self: *Self, ctx: *Context, c: u8) ParseError!void {
        _ = self;
        for (command.global_flags) |*gf| {
            if (gf.short) |short| {
                if (short == c) {
                    applyGlobalFlagToContext(ctx, gf.name);
                    return;
                }
            }
        }
        return ParseError.UnknownFlag;
    }

    /// Single mapping from global flag name to Context boolean field.
    /// This is the ONLY place where global flag names are coupled to
    /// Context struct fields.
    fn applyGlobalFlagToContext(ctx: *Context, name: []const u8) void {
        if (mem.eql(u8, name, "quiet")) {
            ctx.quiet = true;
        } else if (mem.eql(u8, name, "json")) {
            ctx.json = true;
        } else if (mem.eql(u8, name, "plain")) {
            ctx.plain = true;
        } else if (mem.eql(u8, name, "no-color")) {
            ctx.no_color = true;
        } else if (mem.eql(u8, name, "dry-run")) {
            ctx.dry_run = true;
        } else if (mem.eql(u8, name, "no-input")) {
            ctx.no_input = true;
        }
        // help and version are handled separately in parse() before
        // handleGlobalFlag is called, so they are intentionally not
        // mapped here.
    }

    /// Split a comma-separated value string and append each trimmed,
    /// non-empty item to `arr`.
    fn splitAndAppendCsv(self: *Self, arr: *std.ArrayList([]const u8), value: []const u8) ParseError!void {
        var iter = mem.splitSequence(u8, value, ",");
        while (iter.next()) |item| {
            const trimmed = mem.trim(u8, item, " \t");
            if (trimmed.len > 0) {
                arr.append(self.allocator, trimmed) catch return ParseError.OutOfMemory;
            }
        }
    }

    /// Convert a raw string value to a typed `FlagValue` according to the
    /// flag's declared type. Returns `InvalidValue` if the conversion fails.
    /// Boolean values are strict: exactly "true" or "false" (anything else,
    /// including the formerly-truthy "1", is `InvalidValue`).
    /// Public for internal use by parser/env.zig; not part of the stable API.
    pub fn parseValue(self: *Self, ftype: FlagType, value: []const u8) ParseError!FlagValue {
        return switch (ftype) {
            .bool => if (mem.eql(u8, value, "true")) FlagValue{ .bool = true } else if (mem.eql(u8, value, "false")) FlagValue{ .bool = false } else return ParseError.InvalidValue,
            .int => FlagValue{ .int = std.fmt.parseInt(i64, value, 10) catch return ParseError.InvalidValue },
            .float => FlagValue{ .float = std.fmt.parseFloat(f64, value) catch return ParseError.InvalidValue },
            .string, .path => FlagValue{ .string = value },
            .string_array => blk: {
                var arr: std.ArrayList([]const u8) = .empty;
                try self.splitAndAppendCsv(&arr, value);
                break :blk FlagValue{ .string_array = arr };
            },
        };
    }

    /// Append comma-separated items to an existing string_array flag, or
    /// create a new one if this is the first occurrence of the flag.
    fn appendToStringArray(self: *Self, ctx: *Context, name: []const u8, value: []const u8) ParseError!void {
        if (ctx.flags.getPtr(name)) |existing| {
            switch (existing.*) {
                .string_array => |*arr| {
                    try self.splitAndAppendCsv(arr, value);
                },
                else => {
                    // Shouldn't happen - type mismatch
                    return ParseError.InvalidValue;
                },
            }
        } else {
            // First occurrence, create new array
            const fval = try self.parseValue(.string_array, value);
            try self.setFlagValue(ctx, name, fval);
        }
    }

    /// Store a parsed flag value in the context's flag map.
    fn setFlagValue(self: *Self, ctx: *Context, name: []const u8, value: FlagValue) ParseError!void {
        _ = self;
        ctx.flags.put(name, value) catch return ParseError.OutOfMemory;
    }

    /// Search for a long flag by name, walking the full command chain.
    /// Checks current command first, then each ancestor up to root.
    fn findFlagInFullChain(_: *Self, cmd: *const Command, chain: []const *const Command, name: []const u8) ?*const FlagSpec {
        // Check current command flags first (most specific)
        if (cmd.findFlag(name)) |f| return f;

        // Walk ancestors in reverse order (parent, grandparent, ... root)
        // chain includes root at [0] and current cmd may be at the end
        var i: usize = chain.len;
        while (i > 0) {
            i -= 1;
            const ancestor = chain[i];
            if (ancestor == cmd) continue; // Skip current (already checked)
            if (ancestor.findFlag(name)) |f| return f;
        }

        return null;
    }

    /// Search for a short flag by character, walking the full command chain.
    fn findFlagByShortInFullChain(_: *Self, cmd: *const Command, chain: []const *const Command, short: u8) ?*const FlagSpec {
        // Check current command flags first
        if (cmd.findFlagByShort(short)) |f| return f;

        // Walk ancestors in reverse order
        var i: usize = chain.len;
        while (i > 0) {
            i -= 1;
            const ancestor = chain[i];
            if (ancestor == cmd) continue;
            if (ancestor.findFlagByShort(short)) |f| return f;
        }

        return null;
    }
};

/// Execute the full hook lifecycle around a command dispatch:
///   persistent_pre_run (root to leaf) -> pre_run -> run -> post_run ->
///   persistent_post_run (leaf to root).
/// Returns the exit code: 0 on success, 1 on hook/run error.
fn executeHooks(result: *ParseResult) !u8 {
    const cmd = result.command;
    const chain = result.command_chain.items;

    // Persistent pre-run hooks from root to current (in order)
    for (chain) |parent_cmd| {
        if (parent_cmd.persistent_pre_run) |persistent_pre| {
            persistent_pre(&result.context) catch |err| {
                try result.context.stderr.print("Error in persistent pre-run: {}\n", .{err});
                return 1;
            };
        }
    }

    // Pre-run hook (only for current command)
    if (cmd.pre_run) |pre| {
        pre(&result.context) catch |err| {
            try result.context.stderr.print("Error in pre-run: {}\n", .{err});
            return 1;
        };
    }

    // Main run
    if (cmd.run) |run_fn| {
        run_fn(&result.context) catch |err| {
            try result.context.stderr.print("Error: {}\n", .{err});
            return 1;
        };
    } else if (cmd.hasSubcommands()) {
        // No run function but has subcommands - show help
        help.printHelp(cmd, &result.context);
        return 0;
    }

    // Post-run hook (only for current command)
    if (cmd.post_run) |post| {
        post(&result.context) catch |err| {
            try result.context.stderr.print("Error in post-run: {}\n", .{err});
            return 1;
        };
    }

    // Persistent post-run hooks from current to root (reverse order)
    var i: usize = chain.len;
    while (i > 0) {
        i -= 1;
        if (chain[i].persistent_post_run) |persistent_post| {
            persistent_post(&result.context) catch |err| {
                try result.context.stderr.print("Error in persistent post-run: {}\n", .{err});
                return 1;
            };
        }
    }

    return 0;
}

/// Run a command with the given arguments through the full lifecycle:
///
/// 1. **Parse** -- Walk `argv`, resolve subcommands, set flags
/// 2. **Env defaults** -- Populate flags from environment variables
/// 3. **Global flag handling** -- Apply --quiet, --json, --no-color, etc.
/// 4. **Validation** -- Check required flags, flag groups, positional args
/// 5. **Hooks** -- Execute persistent_pre_run (root to leaf), then pre_run
/// 6. **Dispatch** -- Call the resolved command's `run` function
/// 7. **Post hooks** -- Execute post_run, then persistent_post_run (leaf to root)
/// 8. **Error handling** -- Print diagnostics and help on parse/run failure
/// 9. **Cleanup** -- Free ParseResult and Context resources via defer
///
/// Returns the process exit code: 0 on success, 1 on run error, 2 on parse error.
pub fn run(root: *const Command, argv: []const []const u8, allocator: Allocator) !u8 {
    const version = if (root.version.len > 0) root.version else help.default_version;
    var parser = Parser.init(allocator, root, version, "");

    var result = parser.parse(argv) catch |err| {
        const io = std.Io.Threaded.global_single_threaded.io();
        var stderr_buf: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
        const stderr = &stderr_writer.interface;
        defer stderr.flush() catch {};
        try format.formatParseError(&parser, err, stderr);

        // Show help for the current command on error
        if (parser.current_command) |cmd| {
            var ctx = Context.init(allocator);
            defer ctx.deinit();
            help.printHelp(cmd, &ctx);
        }

        return 2;
    };

    defer result.deinit(allocator);

    if (result.help_requested) {
        help.printHelp(result.command, &result.context);
        return 0;
    }

    if (result.version_requested) {
        try result.context.stdout.print("{s}\n", .{parser.version});
        return 0;
    }

    return try executeHooks(&result);
}
