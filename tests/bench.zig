// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Benchmarks
//!
//! Performance benchmarks for the zig-cli library.
//! Run with: `zig build bench` or `make bench`

const std = @import("std");
const cli = @import("cli");
const util = @import("util");

const ITERATIONS = 10_000;
const WARMUP = 100;
const RUNS = 3;

/// Minimal monotonic-clock timer shim (Zig 0.16 removed `std.time.Timer`).
const Timer = struct {
    start_ns: u128,

    fn start() !Timer {
        return .{ .start_ns = nowNs() };
    }

    fn read(t: Timer) u64 {
        const elapsed = nowNs() - t.start_ns;
        return @intCast(elapsed);
    }

    fn nowNs() u128 {
        const io = std.Io.Threaded.global_single_threaded.io();
        const ts = std.Io.Clock.now(.awake, io);
        return @intCast(ts.nanoseconds);
    }
};

/// Allocator wrapper that counts allocations, frees, and total bytes allocated.
/// Wraps any backing allocator and forwards all operations while tracking stats.
const CountingAllocator = struct {
    backing: std.mem.Allocator,
    alloc_count: usize = 0,
    free_count: usize = 0,
    total_bytes: usize = 0,

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn allocFn(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawAlloc(n, alignment, ret_addr);
        if (result != null) {
            self.alloc_count += 1;
            self.total_bytes += n;
        }
        return result;
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawResize(buf, alignment, new_len, ret_addr);
        if (result) {
            if (new_len > buf.len) {
                self.total_bytes += new_len - buf.len;
            }
        }
        return result;
    }

    fn remapFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawRemap(buf, alignment, new_len, ret_addr);
        if (result != null) {
            if (new_len > buf.len) {
                self.total_bytes += new_len - buf.len;
            }
        }
        return result;
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.free_count += 1;
        self.backing.rawFree(buf, alignment, ret_addr);
    }

    fn reset(self: *CountingAllocator) void {
        self.alloc_count = 0;
        self.free_count = 0;
        self.total_bytes = 0;
    }
};

/// Result of a benchmark run, including timing and allocation stats.
const BenchResult = struct {
    total_ns: u64,
    alloc_count: usize,
    free_count: usize,
    total_bytes: usize,
};

/// Benchmark: parser.parse with flags and subcommands
fn benchParse(_: std.mem.Allocator) !BenchResult {
    const sub = cli.Command{
        .name = "get",
        .summary = "Get a value",
        .flags = &.{
            cli.FlagSpec{ .name = "key", .short = 'k', .help = "Key name", .ftype = .string },
        },
    };

    const root = cli.Command{
        .name = "app",
        .summary = "Benchmark app",
        .subcommands = &.{&sub},
        .flags = &.{
            cli.FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
            cli.FlagSpec{ .name = "config", .short = 'c', .help = "Config file", .ftype = .string },
        },
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase: prime caches and arena, discard results
    for (0..WARMUP) |_| {
        var p = cli.Parser.init(alloc, &root, "1.0.0", "");
        var result = try p.parse(&.{ "app", "-v", "get", "--key", "mykey" });
        result.deinit(alloc);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();

    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..ITERATIONS) |_| {
        counter.reset();
        var p = cli.Parser.init(alloc, &root, "1.0.0", "");
        var result = try p.parse(&.{ "app", "-v", "get", "--key", "mykey" });
        result.deinit(alloc);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: help generation (text format)
fn benchHelpGeneration(_: std.mem.Allocator) !BenchResult {
    const sub1 = cli.Command{ .name = "get", .summary = "Get a value" };
    const sub2 = cli.Command{ .name = "set", .summary = "Set a value" };
    const sub3 = cli.Command{ .name = "delete", .summary = "Delete a value" };

    const root = cli.Command{
        .name = "app",
        .summary = "A benchmark application",
        .long_help = "This is a longer help text for the benchmark application.",
        .examples = &.{ "app get --key foo", "app set --key foo --value bar" },
        .subcommands = &.{ &sub1, &sub2, &sub3 },
        .flags = &.{
            cli.FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose output", .ftype = .bool },
            cli.FlagSpec{ .name = "config", .short = 'c', .help = "Config file path", .ftype = .string },
            cli.FlagSpec{ .name = "format", .help = "Output format", .ftype = .string, .completions = &.{ "json", "yaml", "table" } },
        },
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    var ctx = cli.Context.init(alloc);
    defer ctx.deinit();

    // Redirect to discard writer to avoid output
    const io_inst = std.Io.Threaded.global_single_threaded.io();
    const devnull = try std.Io.Dir.cwd().openFile(io_inst, "/dev/null", .{ .mode = .write_only });
    defer devnull.close(io_inst);
    ctx.stdout = .{ .file = devnull };

    // Warm-up phase
    for (0..WARMUP) |_| {
        cli.printHelp(&root, &ctx);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..ITERATIONS) |_| {
        counter.reset();
        cli.printHelp(&root, &ctx);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Create a standard command tree for completion benchmarks.
fn completionBenchCommand() cli.Command {
    const sub1 = cli.Command{ .name = "get", .summary = "Get a value" };
    const sub2 = cli.Command{ .name = "set", .summary = "Set a value" };

    return cli.Command{
        .name = "app",
        .summary = "A benchmark application",
        .subcommands = &.{ &sub1, &sub2 },
        .flags = &.{
            cli.FlagSpec{ .name = "verbose", .short = 'v', .help = "Verbose", .ftype = .bool },
        },
    };
}

/// Benchmark: bash completion generation
fn benchBashCompletion(_: std.mem.Allocator) !BenchResult {
    const root = completionBenchCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase
    for (0..WARMUP) |_| {
        const script = try cli.completion.bash.generate(&root, alloc);
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..ITERATIONS) |_| {
        counter.reset();
        const script = try cli.completion.bash.generate(&root, alloc);
        alloc.free(script);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: zsh completion generation
fn benchZshCompletion(_: std.mem.Allocator) !BenchResult {
    const root = completionBenchCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase
    for (0..WARMUP) |_| {
        const script = try cli.completion.zsh.generate(&root, alloc);
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..ITERATIONS) |_| {
        counter.reset();
        const script = try cli.completion.zsh.generate(&root, alloc);
        alloc.free(script);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: fish completion generation
fn benchFishCompletion(_: std.mem.Allocator) !BenchResult {
    const root = completionBenchCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase
    for (0..WARMUP) |_| {
        const script = try cli.completion.fish.generate(&root, alloc);
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..ITERATIONS) |_| {
        counter.reset();
        const script = try cli.completion.fish.generate(&root, alloc);
        alloc.free(script);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: powershell completion generation
fn benchPowerShellCompletion(_: std.mem.Allocator) !BenchResult {
    const root = completionBenchCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase
    for (0..WARMUP) |_| {
        const script = try cli.completion.powershell.generate(&root, alloc);
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..ITERATIONS) |_| {
        counter.reset();
        const script = try cli.completion.powershell.generate(&root, alloc);
        alloc.free(script);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

// ============================================================================
// Medium-Scale Benchmarks (20+ subcommands, 50+ flags)
// ============================================================================

/// Build a medium-scale command tree at comptime for realistic CLI benchmarks.
/// Returns a root command with 24 subcommands, each carrying 3 flags, plus
/// 8 root-level flags -- totaling 80 flags across the tree.
fn mediumScaleCommand() cli.Command {
    // 8 root-level flags covering all common flag types
    const root_flags = &[_]cli.FlagSpec{
        .{ .name = "verbose", .short = 'v', .help = "Verbose output", .ftype = .bool },
        .{ .name = "quiet", .short = 'q', .help = "Quiet mode", .ftype = .bool },
        .{ .name = "config", .short = 'c', .help = "Config file path", .ftype = .string },
        .{ .name = "output", .short = 'o', .help = "Output file", .ftype = .path },
        .{ .name = "format", .short = 'f', .help = "Output format", .ftype = .string, .completions = &.{ "json", "yaml", "toml", "table", "csv" } },
        .{ .name = "timeout", .short = 't', .help = "Request timeout", .ftype = .int },
        .{ .name = "retries", .short = 'r', .help = "Number of retries", .ftype = .int },
        .{ .name = "dry-run", .short = 'n', .help = "Dry run mode", .ftype = .bool },
    };

    // 24 subcommands, each with 3 flags
    const sub_01 = cli.Command{ .name = "create", .summary = "Create a resource", .flags = &.{
        .{ .name = "name", .help = "Resource name", .ftype = .string, .required = true },
        .{ .name = "type", .help = "Resource type", .ftype = .string, .completions = &.{ "vm", "disk", "network" } },
        .{ .name = "region", .help = "Target region", .ftype = .string },
    } };
    const sub_02 = cli.Command{ .name = "delete", .summary = "Delete a resource", .flags = &.{
        .{ .name = "force", .help = "Force deletion", .ftype = .bool },
        .{ .name = "cascade", .help = "Cascade delete", .ftype = .bool },
        .{ .name = "grace-period", .help = "Grace period seconds", .ftype = .int },
    } };
    const sub_03 = cli.Command{ .name = "get", .summary = "Get resource details", .flags = &.{
        .{ .name = "id", .help = "Resource ID", .ftype = .string },
        .{ .name = "fields", .help = "Fields to display", .ftype = .string_array },
        .{ .name = "wide", .help = "Wide output", .ftype = .bool },
    } };
    const sub_04 = cli.Command{ .name = "list", .summary = "List resources", .flags = &.{
        .{ .name = "limit", .help = "Max results", .ftype = .int },
        .{ .name = "offset", .help = "Result offset", .ftype = .int },
        .{ .name = "filter", .help = "Filter expression", .ftype = .string },
    } };
    const sub_05 = cli.Command{ .name = "update", .summary = "Update a resource", .flags = &.{
        .{ .name = "id", .help = "Resource ID", .ftype = .string, .required = true },
        .{ .name = "patch", .help = "Patch file", .ftype = .path },
        .{ .name = "merge", .help = "Merge strategy", .ftype = .string },
    } };
    const sub_06 = cli.Command{ .name = "describe", .summary = "Describe a resource", .flags = &.{
        .{ .name = "id", .help = "Resource ID", .ftype = .string },
        .{ .name = "show-events", .help = "Show events", .ftype = .bool },
        .{ .name = "show-labels", .help = "Show labels", .ftype = .bool },
    } };
    const sub_07 = cli.Command{ .name = "apply", .summary = "Apply configuration", .flags = &.{
        .{ .name = "file", .help = "Config file", .ftype = .path, .required = true },
        .{ .name = "namespace", .help = "Target namespace", .ftype = .string },
        .{ .name = "prune", .help = "Prune resources", .ftype = .bool },
    } };
    const sub_08 = cli.Command{ .name = "deploy", .summary = "Deploy application", .flags = &.{
        .{ .name = "image", .help = "Container image", .ftype = .string, .required = true },
        .{ .name = "replicas", .help = "Number of replicas", .ftype = .int },
        .{ .name = "port", .help = "Service port", .ftype = .int },
    } };
    const sub_09 = cli.Command{ .name = "rollback", .summary = "Rollback deployment", .flags = &.{
        .{ .name = "revision", .help = "Target revision", .ftype = .int },
        .{ .name = "undo", .help = "Undo last rollout", .ftype = .bool },
        .{ .name = "timeout", .help = "Rollback timeout", .ftype = .int },
    } };
    const sub_10 = cli.Command{ .name = "scale", .summary = "Scale a deployment", .flags = &.{
        .{ .name = "replicas", .help = "Desired replicas", .ftype = .int, .required = true },
        .{ .name = "min", .help = "Min replicas", .ftype = .int },
        .{ .name = "max", .help = "Max replicas", .ftype = .int },
    } };
    const sub_11 = cli.Command{ .name = "logs", .summary = "View logs", .flags = &.{
        .{ .name = "follow", .help = "Follow log output", .ftype = .bool },
        .{ .name = "tail", .help = "Lines from end", .ftype = .int },
        .{ .name = "since", .help = "Since timestamp", .ftype = .string },
    } };
    const sub_12 = cli.Command{ .name = "exec", .summary = "Execute in container", .flags = &.{
        .{ .name = "stdin", .help = "Pass stdin", .ftype = .bool },
        .{ .name = "tty", .help = "Allocate TTY", .ftype = .bool },
        .{ .name = "container", .help = "Container name", .ftype = .string },
    } };
    const sub_13 = cli.Command{ .name = "port-forward", .summary = "Forward ports", .flags = &.{
        .{ .name = "local", .help = "Local port", .ftype = .int, .required = true },
        .{ .name = "remote", .help = "Remote port", .ftype = .int, .required = true },
        .{ .name = "address", .help = "Listen address", .ftype = .string },
    } };
    const sub_14 = cli.Command{ .name = "cp", .summary = "Copy files", .flags = &.{
        .{ .name = "recursive", .help = "Copy recursively", .ftype = .bool },
        .{ .name = "no-preserve", .help = "Skip permissions", .ftype = .bool },
        .{ .name = "container", .help = "Container name", .ftype = .string },
    } };
    const sub_15 = cli.Command{ .name = "auth", .summary = "Authentication", .flags = &.{
        .{ .name = "provider", .help = "Auth provider", .ftype = .string, .completions = &.{ "oidc", "saml", "ldap" } },
        .{ .name = "token-file", .help = "Token file", .ftype = .path },
        .{ .name = "refresh", .help = "Force refresh", .ftype = .bool },
    } };
    const sub_16 = cli.Command{ .name = "config-cmd", .summary = "Manage configuration", .flags = &.{
        .{ .name = "set", .help = "Set key=value", .ftype = .string },
        .{ .name = "unset", .help = "Unset a key", .ftype = .string },
        .{ .name = "view", .help = "View config", .ftype = .bool },
    } };
    const sub_17 = cli.Command{ .name = "plugin", .summary = "Manage plugins", .flags = &.{
        .{ .name = "install", .help = "Install a plugin", .ftype = .string },
        .{ .name = "remove", .help = "Remove a plugin", .ftype = .string },
        .{ .name = "list-all", .help = "List all plugins", .ftype = .bool },
    } };
    const sub_18 = cli.Command{ .name = "version-cmd", .summary = "Show version info", .flags = &.{
        .{ .name = "short", .help = "Short version", .ftype = .bool },
        .{ .name = "build", .help = "Show build info", .ftype = .bool },
        .{ .name = "check", .help = "Check for updates", .ftype = .bool },
    } };
    const sub_19 = cli.Command{ .name = "status", .summary = "Show status", .flags = &.{
        .{ .name = "watch", .help = "Watch for changes", .ftype = .bool },
        .{ .name = "interval", .help = "Refresh interval", .ftype = .int },
        .{ .name = "all-namespaces", .help = "All namespaces", .ftype = .bool },
    } };
    const sub_20 = cli.Command{ .name = "diff", .summary = "Show differences", .flags = &.{
        .{ .name = "context", .help = "Context lines", .ftype = .int },
        .{ .name = "color-diff", .help = "Colorize diff", .ftype = .bool },
        .{ .name = "stat", .help = "Show stat only", .ftype = .bool },
    } };
    const sub_21 = cli.Command{ .name = "export", .summary = "Export resources", .flags = &.{
        .{ .name = "format", .help = "Export format", .ftype = .string, .completions = &.{ "json", "yaml", "csv" } },
        .{ .name = "output", .help = "Output path", .ftype = .path },
        .{ .name = "all", .help = "Export all", .ftype = .bool },
    } };
    const sub_22 = cli.Command{ .name = "import", .summary = "Import resources", .flags = &.{
        .{ .name = "file", .help = "Import file", .ftype = .path, .required = true },
        .{ .name = "overwrite", .help = "Overwrite existing", .ftype = .bool },
        .{ .name = "validate-only", .help = "Validate without importing", .ftype = .bool },
    } };
    const sub_23 = cli.Command{ .name = "migrate", .summary = "Run migrations", .flags = &.{
        .{ .name = "target", .help = "Target version", .ftype = .string },
        .{ .name = "rollback-step", .help = "Rollback steps", .ftype = .int },
        .{ .name = "seed", .help = "Run seeds after", .ftype = .bool },
    } };
    const sub_24 = cli.Command{ .name = "top", .summary = "Display resource usage", .flags = &.{
        .{ .name = "sort-by", .help = "Sort column", .ftype = .string, .completions = &.{ "cpu", "memory", "name" } },
        .{ .name = "no-headers", .help = "Hide headers", .ftype = .bool },
        .{ .name = "containers", .help = "Show containers", .ftype = .bool },
    } };

    return cli.Command{
        .name = "myctl",
        .summary = "A medium-scale CLI application for benchmarking",
        .long_help = "This is a benchmark command tree with 24 subcommands and 80 flags " ++
            "designed to exercise the parser, help generator, and completion generators " ++
            "at a realistic CLI scale.",
        .examples = &.{
            "myctl create --name myvm --type vm --region us-east",
            "myctl deploy --image myapp:latest --replicas 3",
            "myctl logs --follow --tail 100",
        },
        .subcommands = &.{
            &sub_01, &sub_02, &sub_03, &sub_04, &sub_05, &sub_06,
            &sub_07, &sub_08, &sub_09, &sub_10, &sub_11, &sub_12,
            &sub_13, &sub_14, &sub_15, &sub_16, &sub_17, &sub_18,
            &sub_19, &sub_20, &sub_21, &sub_22, &sub_23, &sub_24,
        },
        .flags = root_flags,
    };
}

const MEDIUM_ITERATIONS = 1_000;

/// Benchmark: parser.parse with medium-scale command tree (24 subcmds, 80 flags)
fn benchParseMedium(_: std.mem.Allocator) !BenchResult {
    const root = mediumScaleCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase
    for (0..WARMUP) |_| {
        var p = cli.Parser.init(alloc, &root, "2.0.0", "");
        var result = try p.parse(&.{ "myctl", "-v", "--format", "json", "deploy", "--image", "myapp:latest", "--replicas", "3" });
        result.deinit(alloc);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();

    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..MEDIUM_ITERATIONS) |_| {
        counter.reset();
        var p = cli.Parser.init(alloc, &root, "2.0.0", "");
        var result = try p.parse(&.{ "myctl", "-v", "--format", "json", "deploy", "--image", "myapp:latest", "--replicas", "3" });
        result.deinit(alloc);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: help generation with medium-scale command tree
fn benchHelpMedium(_: std.mem.Allocator) !BenchResult {
    const root = mediumScaleCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    var ctx = cli.Context.init(alloc);
    defer ctx.deinit();

    const io_inst2 = std.Io.Threaded.global_single_threaded.io();
    const devnull = try std.Io.Dir.cwd().openFile(io_inst2, "/dev/null", .{ .mode = .write_only });
    defer devnull.close(io_inst2);
    ctx.stdout = .{ .file = devnull };

    // Warm-up phase
    for (0..WARMUP) |_| {
        cli.printHelp(&root, &ctx);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..MEDIUM_ITERATIONS) |_| {
        counter.reset();
        cli.printHelp(&root, &ctx);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: bash completion generation with medium-scale command tree
fn benchBashCompletionMedium(_: std.mem.Allocator) !BenchResult {
    const root = mediumScaleCommand();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var counter = CountingAllocator{ .backing = arena.allocator() };
    const alloc = counter.allocator();

    // Warm-up phase
    for (0..WARMUP) |_| {
        const script = try cli.completion.bash.generate(&root, alloc);
        alloc.free(script);
        _ = arena.reset(.retain_capacity);
    }
    counter.reset();

    var timer = try Timer.start();
    var total_allocs: usize = 0;
    var total_frees: usize = 0;
    var total_bytes: usize = 0;

    for (0..MEDIUM_ITERATIONS) |_| {
        counter.reset();
        const script = try cli.completion.bash.generate(&root, alloc);
        alloc.free(script);
        total_allocs += counter.alloc_count;
        total_frees += counter.free_count;
        total_bytes += counter.total_bytes;
        _ = arena.reset(.retain_capacity);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = total_allocs,
        .free_count = total_frees,
        .total_bytes = total_bytes,
    };
}

/// Benchmark: Levenshtein distance (typo suggestion)
fn benchLevenshtein() !BenchResult {
    const choices = &[_][]const u8{
        "status", "start",   "stop",     "serve",    "search", "sync",
        "deploy", "destroy", "describe", "download", "debug",
    };

    // Warm-up phase
    for (0..WARMUP) |_| {
        _ = util.suggestClosest("staus", choices, 3);
        _ = util.suggestClosest("delpoy", choices, 3);
        _ = util.suggestClosest("serch", choices, 3);
    }

    var timer = try Timer.start();

    for (0..ITERATIONS * 10) |_| {
        _ = util.suggestClosest("staus", choices, 3);
        _ = util.suggestClosest("delpoy", choices, 3);
        _ = util.suggestClosest("serch", choices, 3);
    }

    return .{
        .total_ns = timer.read(),
        .alloc_count = 0,
        .free_count = 0,
        .total_bytes = 0,
    };
}

fn formatNs(ns: u64) struct { value: f64, unit: []const u8 } {
    if (ns >= 1_000_000_000) return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0, .unit = "s" };
    if (ns >= 1_000_000) return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000_000.0, .unit = "ms" };
    if (ns >= 1_000) return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000.0, .unit = "us" };
    return .{ .value = @as(f64, @floatFromInt(ns)), .unit = "ns" };
}

fn formatBytes(bytes: usize) struct { value: f64, unit: []const u8 } {
    const b: f64 = @floatFromInt(bytes);
    if (bytes >= 1_048_576) return .{ .value = b / 1_048_576.0, .unit = "MiB" };
    if (bytes >= 1_024) return .{ .value = b / 1_024.0, .unit = "KiB" };
    return .{ .value = b, .unit = "B" };
}

/// Run a benchmark function multiple times (RUNS) and return the median result.
/// This reduces variance from scheduling jitter, thermal throttling, and other
/// transient system effects.
fn runMulti(
    comptime benchFn: anytype,
    allocator: std.mem.Allocator,
    comptime has_alloc_param: bool,
) !BenchResult {
    var results: [RUNS]BenchResult = undefined;
    for (0..RUNS) |i| {
        results[i] = if (has_alloc_param)
            try benchFn(allocator)
        else
            try benchFn();
    }

    // Sort by total_ns to find median
    std.mem.sort(BenchResult, &results, {}, struct {
        fn lt(_: void, a: BenchResult, b: BenchResult) bool {
            return a.total_ns < b.total_ns;
        }
    }.lt);

    return results[RUNS / 2]; // median
}

fn printResult(name: []const u8, bench: BenchResult, iterations: u64) void {
    const per_op_ns = bench.total_ns / iterations;
    const total = formatNs(bench.total_ns);
    const per_op = formatNs(per_op_ns);
    const bytes = formatBytes(bench.total_bytes);
    const allocs_per_op = if (iterations > 0)
        @as(f64, @floatFromInt(bench.alloc_count)) / @as(f64, @floatFromInt(iterations))
    else
        0.0;

    std.debug.print("  {s:<30} {d:>8.2} {s:<3}  ({d:>8.2} {s}/op, {d} iterations)\n", .{
        name,
        total.value,
        total.unit,
        per_op.value,
        per_op.unit,
        iterations,
    });
    std.debug.print("  {s:<30} {d:>8} allocs  {d:>8} frees  {d:>8.2} {s} total  ({d:.1} allocs/op)\n", .{
        "",
        bench.alloc_count,
        bench.free_count,
        bytes.value,
        bytes.unit,
        allocs_per_op,
    });
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nzig-cli benchmarks ({d} iterations, {d} runs, median reported)\n", .{ ITERATIONS, RUNS });
    std.debug.print("{s}\n", .{"=" ** 80});

    const parse_result = try runMulti(benchParse, allocator, true);
    printResult("Parser.parse (flags+subcmd)", parse_result, ITERATIONS);

    const help_result = try runMulti(benchHelpGeneration, allocator, true);
    printResult("Help generation (text)", help_result, ITERATIONS);

    const bash_result = try runMulti(benchBashCompletion, allocator, true);
    printResult("Bash completion generation", bash_result, ITERATIONS);

    const zsh_result = try runMulti(benchZshCompletion, allocator, true);
    printResult("Zsh completion generation", zsh_result, ITERATIONS);

    const fish_result = try runMulti(benchFishCompletion, allocator, true);
    printResult("Fish completion generation", fish_result, ITERATIONS);

    const ps_result = try runMulti(benchPowerShellCompletion, allocator, true);
    printResult("PowerShell completion generation", ps_result, ITERATIONS);

    const lev_result = try runMulti(benchLevenshtein, allocator, false);
    printResult("Levenshtein distance", lev_result, ITERATIONS * 10 * 3);

    std.debug.print("\n  --- Medium Scale (24 subcmds, 80 flags) ---\n\n", .{});

    const parse_medium = try runMulti(benchParseMedium, allocator, true);
    printResult("Parser.parse (medium)", parse_medium, MEDIUM_ITERATIONS);

    const help_medium = try runMulti(benchHelpMedium, allocator, true);
    printResult("Help generation (medium)", help_medium, MEDIUM_ITERATIONS);

    const bash_medium = try runMulti(benchBashCompletionMedium, allocator, true);
    printResult("Bash completion (medium)", bash_medium, MEDIUM_ITERATIONS);

    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  Done.\n\n", .{});
}
