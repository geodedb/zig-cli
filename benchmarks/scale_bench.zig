// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Scale Benchmarks
//!
//! Measures CLI library performance across increasing command-tree sizes.
//! Outputs machine-readable JSON to stdout and human-readable summary to stderr.
//!
//! ## Tiers
//!
//! | Tier   | Subcommands | Flags | Description        |
//! |--------|-------------|-------|--------------------|
//! | small  | 8           | 24    | Minimal CLI tool   |
//! | medium | 24          | 80    | kubectl-class tool |
//! | large  | 64          | 256   | Enterprise CLI     |
//! | xlarge | 128         | 512   | Monorepo CLI       |
//!
//! ## Usage
//!
//! ```sh
//! zig build scale-bench 2>/dev/null              # JSON only
//! zig build scale-bench 2>/dev/null > result.json # Save results
//! zig build scale-bench -- medium                 # Run up to medium tier
//! ```

const std = @import("std");
const cli = @import("cli");
const util = @import("util");
const parallel = @import("parallel");
const build_options = @import("build_options");

const WARMUP = 50;
const RUNS = 5;

// ============================================================================
// Tier definitions
// ============================================================================

const Tier = struct {
    name: []const u8,
    subcmd_count: usize,
    flags_per_subcmd: usize,
    root_flags: usize,
    parse_iterations: usize,
    help_iterations: usize,
    completion_iterations: usize,
};

const tiers = [_]Tier{
    .{ .name = "small", .subcmd_count = 8, .flags_per_subcmd = 2, .root_flags = 8, .parse_iterations = 10_000, .help_iterations = 5_000, .completion_iterations = 2_000 },
    .{ .name = "medium", .subcmd_count = 24, .flags_per_subcmd = 3, .root_flags = 8, .parse_iterations = 5_000, .help_iterations = 2_000, .completion_iterations = 1_000 },
    .{ .name = "large", .subcmd_count = 64, .flags_per_subcmd = 3, .root_flags = 16, .parse_iterations = 2_000, .help_iterations = 1_000, .completion_iterations = 500 },
    .{ .name = "xlarge", .subcmd_count = 128, .flags_per_subcmd = 3, .root_flags = 16, .parse_iterations = 1_000, .help_iterations = 500, .completion_iterations = 250 },
};

// ============================================================================
// JSON output
// ============================================================================

const JsonWriter = struct {
    file: std.Io.File,

    fn init() JsonWriter {
        return .{ .file = std.Io.File.stdout() };
    }

    fn write(self: *JsonWriter, bytes: []const u8) void {
        self.file.writeAll(bytes) catch {};
    }

    fn print(self: *JsonWriter, comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.write(slice);
    }
};

// ============================================================================
// Metric collection
// ============================================================================

fn median(values: []u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[values.len / 2];
}

// ============================================================================
// Command tree generation
// ============================================================================

const MAX_SUBCMDS = 128;
const MAX_FLAGS_PER_CMD = 4;
const MAX_TOTAL_FLAGS = MAX_SUBCMDS * MAX_FLAGS_PER_CMD + 16;

// Static storage for generated names
var subcmd_name_bufs: [MAX_SUBCMDS][32]u8 = undefined;
var subcmd_summary_bufs: [MAX_SUBCMDS][48]u8 = undefined;
var flag_name_bufs: [MAX_TOTAL_FLAGS][32]u8 = undefined;
var flag_help_bufs: [MAX_TOTAL_FLAGS][48]u8 = undefined;

// Storage for FlagSpec arrays
var subcmd_flag_storage: [MAX_SUBCMDS][MAX_FLAGS_PER_CMD]cli.FlagSpec = undefined;
var root_flag_storage: [16]cli.FlagSpec = undefined;

// Storage for subcommand structs and pointer array
var subcmd_storage: [MAX_SUBCMDS]cli.Command = undefined;
var subcmd_ptrs: [MAX_SUBCMDS]*const cli.Command = undefined;

fn genName(buf: *[32]u8, prefix: []const u8, index: usize) []const u8 {
    const slice = std.fmt.bufPrint(buf, "{s}{d}", .{ prefix, index }) catch return prefix;
    return slice;
}

fn genHelp(buf: *[48]u8, prefix: []const u8, index: usize) []const u8 {
    const slice = std.fmt.bufPrint(buf, "{s} {d}", .{ prefix, index }) catch return prefix;
    return slice;
}

fn buildCommandTree(tier: Tier) cli.Command {
    // Generate root flags
    for (0..tier.root_flags) |i| {
        const name = genName(&flag_name_bufs[i], "root-flag-", i);
        const help = genHelp(&flag_help_bufs[i], "Root flag", i);
        root_flag_storage[i] = cli.FlagSpec{
            .name = name,
            .ftype = if (i % 3 == 0) .bool else if (i % 3 == 1) .string else .int,
            .help = help,
        };
    }

    // Generate subcommands with their flags
    for (0..tier.subcmd_count) |si| {
        const sub_name = genName(&subcmd_name_bufs[si], "subcmd-", si);
        const sub_summary = genHelp(&subcmd_summary_bufs[si], "Subcommand", si);

        for (0..tier.flags_per_subcmd) |fi| {
            const flag_idx = tier.root_flags + si * tier.flags_per_subcmd + fi;
            const fname = genName(&flag_name_bufs[flag_idx], "flag-", flag_idx);
            const fhelp = genHelp(&flag_help_bufs[flag_idx], "Flag", flag_idx);
            subcmd_flag_storage[si][fi] = cli.FlagSpec{
                .name = fname,
                .ftype = if (fi % 2 == 0) .string else .bool,
                .help = fhelp,
            };
        }

        subcmd_storage[si] = cli.Command{
            .name = sub_name,
            .summary = sub_summary,
            .flags = subcmd_flag_storage[si][0..tier.flags_per_subcmd],
        };
        subcmd_ptrs[si] = &subcmd_storage[si];
    }

    return cli.Command{
        .name = "bench-app",
        .summary = "Benchmark application",
        .flags = root_flag_storage[0..tier.root_flags],
        .subcommands = subcmd_ptrs[0..tier.subcmd_count],
    };
}

// ============================================================================
// Individual benchmarks
// ============================================================================

fn benchParse(cmd: *const cli.Command, iterations: usize) u64 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    for (0..WARMUP) |_| {
        var p = cli.Parser.init(alloc, cmd, "1.0.0", "");
        var result = p.parse(&.{ "bench-app", "subcmd-0", "--flag-0", "value" }) catch continue;
        result.deinit(alloc);
        _ = arena.reset(.retain_capacity);
    }

    var timer = std.time.Timer.start() catch return 0;
    for (0..iterations) |_| {
        var p = cli.Parser.init(alloc, cmd, "1.0.0", "");
        var result = p.parse(&.{ "bench-app", "subcmd-0", "--flag-0", "value" }) catch continue;
        result.deinit(alloc);
        _ = arena.reset(.retain_capacity);
    }
    return timer.read() / iterations;
}

fn benchHelpGen(cmd: *const cli.Command, iterations: usize) u64 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ctx = cli.Context.init(alloc);
    defer ctx.deinit();

    const devnull = std.Io.Dir.openFileAbsolute("/dev/null", .{ .mode = .write_only }) catch return 0;
    defer devnull.close();
    ctx.stdout = devnull.writerStreaming(std.Io.Threaded.global_single_threaded.io(), &buf);

    for (0..WARMUP) |_| {
        cli.printHelp(cmd, &ctx);
    }

    var timer = std.time.Timer.start() catch return 0;
    for (0..iterations) |_| {
        cli.printHelp(cmd, &ctx);
    }
    return timer.read() / iterations;
}

fn benchCompletion(comptime gen: anytype, cmd: *const cli.Command, iterations: usize) u64 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    for (0..WARMUP) |_| {
        const script = gen.generate(cmd, alloc) catch continue;
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }

    var timer = std.time.Timer.start() catch return 0;
    for (0..iterations) |_| {
        const script = gen.generate(cmd, alloc) catch continue;
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }
    return timer.read() / iterations;
}

fn benchLevenshtein(iterations: usize) u64 {
    const candidates = [_][]const u8{
        "create", "delete", "get",    "list",    "update",
        "describe", "apply", "deploy", "rollback", "scale",
        "logs",   "exec",   "auth",   "config",  "plugin",
        "version", "status", "diff",  "export",  "import",
    };

    for (0..WARMUP) |_| {
        _ = util.suggestClosest("craete", &candidates, 3);
    }

    var timer = std.time.Timer.start() catch return 0;
    for (0..iterations) |_| {
        _ = util.suggestClosest("craete", &candidates, 3);
        _ = util.suggestClosest("delet", &candidates, 3);
        _ = util.suggestClosest("statsu", &candidates, 3);
    }
    return timer.read() / (iterations * 3);
}

fn benchParallelForEach(iterations: usize) u64 {
    const items = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    var results: [16]u64 = undefined;

    if (build_options.enable_spice) {
        parallel.initPool(.{ .worker_count = 4 });
    }
    defer {
        if (build_options.enable_spice) parallel.deinitPool();
    }

    const compute = struct {
        fn f(x: u32) u64 {
            var acc: u64 = x;
            for (0..100) |_| acc = acc *% 6364136223846793005 +% 1442695040888963407;
            return acc;
        }
    }.f;

    for (0..WARMUP) |_| {
        parallel.forEach(u32, u64, &items, &results, compute);
    }

    var timer = std.time.Timer.start() catch return 0;
    for (0..iterations) |_| {
        parallel.forEach(u32, u64, &items, &results, compute);
    }
    return timer.read() / iterations;
}

// ============================================================================
// Multi-run with median
// ============================================================================

fn runMulti(comptime f: anytype, args: anytype) u64 {
    var samples: [RUNS]u64 = undefined;
    for (&samples) |*s| {
        s.* = @call(.auto, f, args);
    }
    return median(&samples);
}

// ============================================================================
// Formatting
// ============================================================================

fn formatNs(ns: u64) [12]u8 {
    var buf: [12]u8 = .{' '} ** 12;
    if (ns >= 1_000_000_000) {
        _ = std.fmt.bufPrint(&buf, "{d:>7.1} s ", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000.0}) catch {};
    } else if (ns >= 1_000_000) {
        _ = std.fmt.bufPrint(&buf, "{d:>7.1} ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000.0}) catch {};
    } else if (ns >= 1_000) {
        _ = std.fmt.bufPrint(&buf, "{d:>7.1} us", .{@as(f64, @floatFromInt(ns)) / 1_000.0}) catch {};
    } else {
        _ = std.fmt.bufPrint(&buf, "{d:>7} ns", .{ns}) catch {};
    }
    return buf;
}

// ============================================================================
// Main
// ============================================================================

pub fn main() void {
    const stderr = std.Io.File.stderr().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &buf);
    var json = JsonWriter.init();

    // Parse optional max-tier argument
    var max_tier_idx: usize = tiers.len;
    const args = std.process.argsAlloc(std.heap.page_allocator) catch return;
    if (args.len > 1) {
        for (tiers, 0..) |t, i| {
            if (std.mem.eql(u8, args[1], t.name)) {
                max_tier_idx = i + 1;
                break;
            }
        }
    }

    // JSON header
    json.write("{\n");
    json.print("  \"version\": 1,\n", .{});

    // Timestamp
    const ts = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    json.print("  \"timestamp\": \"{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z\",\n", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });

    json.print("  \"git_commit\": \"unknown\",\n", .{});
    json.print("  \"system\": {{ \"os\": \"{s}\", \"arch\": \"{s}\" }},\n", .{
        @tagName(@import("builtin").os.tag),
        @tagName(@import("builtin").cpu.arch),
    });
    json.print("  \"spice_enabled\": {s},\n", .{
        if (build_options.enable_spice) "true" else "false",
    });
    json.write("  \"tiers\": [\n");

    stderr.print("\n  CLI Scale Benchmark\n", .{}) catch {};
    stderr.print("  ===================\n\n", .{}) catch {};
    stderr.print("  {s:<8} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{
        "Tier", "Parse", "Help", "Bash", "Zsh", "Fish", "PS", "Leven", "Parallel",
    }) catch {};
    stderr.print("  -------- ------------ ------------ ------------ ------------ ------------ ------------ ------------ ------------\n", .{}) catch {};

    for (tiers[0..max_tier_idx], 0..) |tier, ti| {
        const cmd = buildCommandTree(tier);
        const total_flags = tier.root_flags + tier.subcmd_count * tier.flags_per_subcmd;

        // Run benchmarks
        const parse_ns = runMulti(benchParse, .{ &cmd, tier.parse_iterations });
        const help_ns = runMulti(benchHelpGen, .{ &cmd, tier.help_iterations });
        const bash_ns = runMulti(benchCompletion, .{ cli.completion.bash, &cmd, tier.completion_iterations });
        const zsh_ns = runMulti(benchCompletion, .{ cli.completion.zsh, &cmd, tier.completion_iterations });
        const fish_ns = runMulti(benchCompletion, .{ cli.completion.fish, &cmd, tier.completion_iterations });
        const ps_ns = runMulti(benchCompletion, .{ cli.completion.powershell, &cmd, tier.completion_iterations });
        const lev_ns = runMulti(benchLevenshtein, .{tier.parse_iterations});
        const par_ns = runMulti(benchParallelForEach, .{tier.parse_iterations});

        const parse_ops = if (parse_ns > 0) 1_000_000_000 / parse_ns else 0;

        // Human-readable summary (stderr)
        stderr.print("  {s:<8} {s} {s} {s} {s} {s} {s} {s} {s}\n", .{
            tier.name,
            formatNs(parse_ns),
            formatNs(help_ns),
            formatNs(bash_ns),
            formatNs(zsh_ns),
            formatNs(fish_ns),
            formatNs(ps_ns),
            formatNs(lev_ns),
            formatNs(par_ns),
        }) catch {};

        // JSON tier
        if (ti > 0) json.write(",\n");
        json.write("    {\n");
        json.print("      \"name\": \"{s}\",\n", .{tier.name});
        json.print("      \"subcmd_count\": {d},\n", .{tier.subcmd_count});
        json.print("      \"total_flags\": {d},\n", .{total_flags});
        json.print("      \"parse_ns\": {d},\n", .{parse_ns});
        json.print("      \"parse_ops_sec\": {d},\n", .{parse_ops});
        json.print("      \"help_gen_ns\": {d},\n", .{help_ns});
        json.print("      \"bash_completion_ns\": {d},\n", .{bash_ns});
        json.print("      \"zsh_completion_ns\": {d},\n", .{zsh_ns});
        json.print("      \"fish_completion_ns\": {d},\n", .{fish_ns});
        json.print("      \"ps_completion_ns\": {d},\n", .{ps_ns});
        json.print("      \"levenshtein_ns\": {d},\n", .{lev_ns});
        json.print("      \"parallel_foreach_ns\": {d},\n", .{par_ns});
        json.write("      \"skipped\": false\n");
        json.write("    }");
    }

    json.write("\n  ]\n}\n");

    stderr.print("\n  Spice: {s}\n\n", .{
        if (build_options.enable_spice) "enabled" else "disabled",
    }) catch {};
}
