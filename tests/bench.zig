// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Benchmarks
//!
//! Performance benchmarks for the zig-cli library: the harness (timing,
//! allocation counting, formatting, multi-run median) and the entry point.
//! The benchmark case functions live in bench_cases.zig.
//! Run with: `zig build bench` or `make bench`

const std = @import("std");

const cases = @import("bench_cases.zig");

pub const ITERATIONS = 10_000;
pub const WARMUP = 100;
const RUNS = 3;

/// Minimal monotonic-clock timer shim (Zig 0.16 removed `std.time.Timer`).
pub const Timer = struct {
    start_ns: u128,

    pub fn start() !Timer {
        return .{ .start_ns = nowNs() };
    }

    pub fn read(t: Timer) u64 {
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
pub const CountingAllocator = struct {
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

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
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

    pub fn reset(self: *CountingAllocator) void {
        self.alloc_count = 0;
        self.free_count = 0;
        self.total_bytes = 0;
    }
};

/// Result of a benchmark run, including timing and allocation stats.
pub const BenchResult = struct {
    total_ns: u64,
    alloc_count: usize,
    free_count: usize,
    total_bytes: usize,
};

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

    const parse_result = try runMulti(cases.benchParse, allocator, true);
    printResult("Parser.parse (flags+subcmd)", parse_result, ITERATIONS);

    const help_result = try runMulti(cases.benchHelpGeneration, allocator, true);
    printResult("Help generation (text)", help_result, ITERATIONS);

    const bash_result = try runMulti(cases.benchBashCompletion, allocator, true);
    printResult("Bash completion generation", bash_result, ITERATIONS);

    const zsh_result = try runMulti(cases.benchZshCompletion, allocator, true);
    printResult("Zsh completion generation", zsh_result, ITERATIONS);

    const fish_result = try runMulti(cases.benchFishCompletion, allocator, true);
    printResult("Fish completion generation", fish_result, ITERATIONS);

    const ps_result = try runMulti(cases.benchPowerShellCompletion, allocator, true);
    printResult("PowerShell completion generation", ps_result, ITERATIONS);

    const lev_result = try runMulti(cases.benchLevenshtein, allocator, false);
    printResult("Levenshtein distance", lev_result, ITERATIONS * 10 * 3);

    std.debug.print("\n  --- Medium Scale (24 subcmds, 80 flags) ---\n\n", .{});

    const parse_medium = try runMulti(cases.benchParseMedium, allocator, true);
    printResult("Parser.parse (medium)", parse_medium, cases.MEDIUM_ITERATIONS);

    const help_medium = try runMulti(cases.benchHelpMedium, allocator, true);
    printResult("Help generation (medium)", help_medium, cases.MEDIUM_ITERATIONS);

    const bash_medium = try runMulti(cases.benchBashCompletionMedium, allocator, true);
    printResult("Bash completion (medium)", bash_medium, cases.MEDIUM_ITERATIONS);

    std.debug.print("{s}\n", .{"=" ** 80});
    std.debug.print("  Done.\n\n", .{});
}
