// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Parallel Module
//!
//! Optional spice-based parallelism for CLI operations.
//!
//! When built with `-Dspice=true` (the default), provides heartbeat-scheduled
//! fork/join parallelism via the spice thread pool. When spice is disabled,
//! all operations fall back to sequential execution transparently.
//!
//! ## Thread Safety
//!
//! The parallel module is thread-safe. The underlying spice thread pool manages
//! all synchronization internally. Results are collected into caller-owned slices.
//!
//! ## Usage
//!
//! ```zig
//! const parallel = @import("parallel");
//!
//! // Initialize the thread pool (once, at program start)
//! parallel.initPool(.{});
//! defer parallel.deinitPool();
//!
//! // Process items in parallel
//! var results: [8]u64 = undefined;
//! parallel.forEach(u64, &items, &results, computeItem);
//! ```

const std = @import("std");
const build_options = @import("build_options");

const spice_enabled = build_options.enable_spice;
const spice = if (spice_enabled) @import("spice") else struct {};

/// Thread pool configuration.
pub const PoolConfig = struct {
    /// Number of background worker threads. null = auto-detect from CPU count.
    worker_count: ?usize = null,
    /// Heartbeat interval in nanoseconds.
    heartbeat_interval: usize = 100 * std.time.ns_per_us,
};

/// Whether spice-based parallelism is available at compile time.
pub const is_enabled = spice_enabled;

// ---------------------------------------------------------------------------
// Thread pool lifecycle
// ---------------------------------------------------------------------------

var pool: if (spice_enabled) spice.ThreadPool else void = if (spice_enabled)
    spice.ThreadPool.init(std.heap.page_allocator)
else {};
var pool_started: bool = false;

/// Initialize and start the thread pool.
/// Call once at program startup. No-op if spice is disabled.
pub fn initPool(config: PoolConfig) void {
    if (!spice_enabled) return;

    if (pool_started) return;

    pool.start(.{
        .background_worker_count = config.worker_count,
        .heartbeat_interval = config.heartbeat_interval,
    });
    pool_started = true;
}

/// Shut down the thread pool and release resources.
/// Call once at program exit. No-op if spice is disabled.
pub fn deinitPool() void {
    if (!spice_enabled) return;

    if (!pool_started) return;

    pool.deinit();
    pool_started = false;
    pool = spice.ThreadPool.init(std.heap.page_allocator);
}

// ---------------------------------------------------------------------------
// Parallel forEach
// ---------------------------------------------------------------------------

/// Minimum number of items before parallel dispatch is worthwhile.
/// Below this threshold, sequential execution is used.
pub const min_parallel_items = 4;

/// Process items in parallel using spice fork/join.
///
/// Calls `func(task, item)` for each item, storing results in `results`.
/// Falls back to sequential execution when spice is disabled or when
/// there are fewer than `min_parallel_items` items.
///
/// The `func` signature must be: `fn (*spice.Task, T) R` when spice is
/// enabled, or `fn (*void, T) R` when disabled (the task pointer is unused
/// in sequential mode).
pub fn forEach(
    comptime T: type,
    comptime R: type,
    items: []const T,
    results: []R,
    comptime func: anytype,
) void {
    std.debug.assert(results.len >= items.len);

    if (!spice_enabled or !pool_started or items.len < min_parallel_items) {
        sequentialForEach(T, R, items, results, func);
        return;
    }

    if (spice_enabled) {
        spiceForEach(T, R, items, results, func);
    }
}

fn sequentialForEach(
    comptime T: type,
    comptime R: type,
    items: []const T,
    results: []R,
    comptime func: anytype,
) void {
    for (items, 0..) |item, i| {
        results[i] = func(item);
    }
}

fn spiceForEach(
    comptime T: type,
    comptime R: type,
    items: []const T,
    results: []R,
    comptime func: anytype,
) void {
    if (!spice_enabled) return;

    const Ctx = struct {
        items_ptr: []const T,
        results_ptr: []R,

        fn compute(task: *spice.Task, ctx: @This()) void {
            forEachRecursive(T, R, task, ctx.items_ptr, ctx.results_ptr, func);
        }
    };

    pool.call(void, Ctx.compute, Ctx{
        .items_ptr = items,
        .results_ptr = results,
    });
}

fn forEachRecursive(
    comptime T: type,
    comptime R: type,
    task: *spice.Task,
    items: []const T,
    results: []R,
    comptime func: anytype,
) void {
    if (!spice_enabled) return;

    if (items.len <= 1) {
        if (items.len == 1) {
            results[0] = func(items[0]);
        }
        return;
    }

    const mid = items.len / 2;

    const Ctx = struct {
        items_half: []const T,
        results_half: []R,

        fn compute(t: *spice.Task, ctx: @This()) void {
            forEachRecursive(T, R, t, ctx.items_half, ctx.results_half, func);
        }
    };

    // Fork the right half to potentially run on another thread
    var future = spice.Future(Ctx, void).init();
    future.fork(task, Ctx.compute, Ctx{
        .items_half = items[mid..],
        .results_half = results[mid..],
    });

    // Process the left half on this thread
    forEachRecursive(T, R, task, items[0..mid], results[0..mid], func);

    // Join the right half
    _ = future.tryJoin(task);
}

// ---------------------------------------------------------------------------
// Parallel map (convenience wrapper)
// ---------------------------------------------------------------------------

/// Map a function over a slice in parallel, returning results in a new slice.
/// Caller owns the returned memory.
pub fn map(
    comptime T: type,
    comptime R: type,
    allocator: std.mem.Allocator,
    items: []const T,
    comptime func: anytype,
) ![]R {
    const results = try allocator.alloc(R, items.len);
    forEach(T, R, items, results, func);
    return results;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "parallel: forEach sequential fallback" {
    const items = [_]u32{ 1, 2, 3 };
    var results: [3]u64 = undefined;

    forEach(u32, u64, &items, &results, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x) * 2;
        }
    }.compute);

    try std.testing.expectEqual(@as(u64, 2), results[0]);
    try std.testing.expectEqual(@as(u64, 4), results[1]);
    try std.testing.expectEqual(@as(u64, 6), results[2]);
}

test "parallel: forEach with enough items for parallel" {
    // This tests the parallel path if spice is enabled,
    // or falls back to sequential otherwise.
    const items = [_]u32{ 10, 20, 30, 40, 50 };
    var results: [5]u64 = undefined;

    if (spice_enabled) {
        initPool(.{ .worker_count = 2 });
        defer deinitPool();
    }

    forEach(u32, u64, &items, &results, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x) + 1;
        }
    }.compute);

    try std.testing.expectEqual(@as(u64, 11), results[0]);
    try std.testing.expectEqual(@as(u64, 21), results[1]);
    try std.testing.expectEqual(@as(u64, 31), results[2]);
    try std.testing.expectEqual(@as(u64, 41), results[3]);
    try std.testing.expectEqual(@as(u64, 51), results[4]);
}

test "parallel: forEach empty slice" {
    var results: [0]u64 = .{};
    forEach(u32, u64, &.{}, &results, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x);
        }
    }.compute);
}

test "parallel: forEach single item" {
    const items = [_]u32{42};
    var results: [1]u64 = undefined;

    forEach(u32, u64, &items, &results, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x) * 3;
        }
    }.compute);

    try std.testing.expectEqual(@as(u64, 126), results[0]);
}

test "parallel: is_enabled matches build option" {
    try std.testing.expectEqual(spice_enabled, is_enabled);
}

test "parallel: map allocates and computes" {
    const items = [_]u32{ 1, 2, 3 };
    const results = try map(u32, u64, std.testing.allocator, &items, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x) * 10;
        }
    }.compute);
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(u64, 10), results[0]);
    try std.testing.expectEqual(@as(u64, 20), results[1]);
    try std.testing.expectEqual(@as(u64, 30), results[2]);
}
