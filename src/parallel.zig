// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Parallel Module
//!
//! Optional thread-pool-based parallelism for CLI operations.
//!
//! When built with `-Dthread-pool=true` (the default), provides flat-chunk
//! parallelism via the thread-pool library. When disabled, all operations
//! fall back to sequential execution transparently.
//!
//! ## Thread Safety
//!
//! The parallel module is thread-safe. The underlying thread pool manages
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
//! parallel.forEach(u32, u64, &items, &results, computeItem);
//! ```
//!
//! ## Batch Processing in Commands
//!
//! ```zig
//! const parallel = @import("parallel");
//! const progress = @import("term").progress;
//!
//! fn batchProcess(ctx: *cli.Context) !void {
//!     const files = ctx.positionalArgs();
//!     parallel.initPool(.{});
//!     defer parallel.deinitPool();
//!
//!     var bar = progress.ProgressBar.init(files.len, "Processing");
//!     const results = try parallel.map(
//!         []const u8, bool, ctx.allocator, files, processFile,
//!     );
//!     defer ctx.allocator.free(results);
//!     bar.finish();
//! }
//! ```

const std = @import("std");

const tp_enabled = true;
const tp = if (tp_enabled) @import("thread_pool") else struct {};

/// Thread pool configuration.
pub const PoolConfig = struct {
    /// Number of background worker threads. null = auto-detect from CPU count.
    worker_count: ?usize = null,
    /// (unused; kept for API compatibility)
    heartbeat_interval: usize = 100 * std.time.ns_per_us,
};

/// Whether thread-pool-based parallelism is available at compile time.
pub const is_enabled = tp_enabled;

// ---------------------------------------------------------------------------
// Thread pool lifecycle
// ---------------------------------------------------------------------------

var pool: if (tp_enabled) tp.ThreadPool else void = undefined;
var pool_started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var pool_workers: usize = 1;

/// Initialize and start the thread pool.
/// Call once at program startup. No-op if thread-pool is disabled.
pub fn initPool(config: PoolConfig) void {
    if (!tp_enabled) return;

    if (pool_started.load(.acquire)) return;

    const max: usize = config.worker_count orelse 0;
    pool = tp.ThreadPool.init(std.heap.page_allocator, .{
        .max_threads = max,
    }) catch @panic("thread-pool: init failed");
    pool_workers = if (max > 0) max else (std.Thread.getCpuCount() catch 1);
    pool_started.store(true, .release);
}

/// Shut down the thread pool and release resources.
/// Call once at program exit. No-op if thread-pool is disabled.
pub fn deinitPool() void {
    if (!tp_enabled) return;

    if (!pool_started.load(.acquire)) return;
    pool.deinit();
    pool_started.store(false, .release);
}

// ---------------------------------------------------------------------------
// Parallel forEach
// ---------------------------------------------------------------------------

/// Minimum number of items before parallel dispatch is worthwhile.
/// Below this threshold, sequential execution is used.
pub const min_parallel_items = 4;

/// Maximum number of chunks to split work into.
const MAX_CHUNKS = 64;

/// Process items in parallel using flat chunking + submitBatch + WaitGroup.
///
/// Calls `func(item)` for each item, storing results in `results`.
/// Falls back to sequential execution when thread-pool is disabled or when
/// there are fewer than `min_parallel_items` items.
pub fn forEach(
    comptime T: type,
    comptime R: type,
    items: []const T,
    results: []R,
    comptime func: anytype,
) void {
    std.debug.assert(results.len >= items.len);

    if (!tp_enabled or !pool_started.load(.acquire) or items.len < min_parallel_items) {
        sequentialForEach(T, R, items, results, func);
        return;
    }

    tpForEach(T, R, items, results, func);
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

/// Number of chunks for forEach: ~2 chunks per worker for load balancing,
/// never more than the item count or MAX_CHUNKS, never zero (NP-030).
fn computeNumChunks(item_count: usize, workers: usize) usize {
    const by_workers = @max(workers, 1) * 2;
    return @max(@min(item_count, MAX_CHUNKS, by_workers), 1);
}

fn tpForEach(
    comptime T: type,
    comptime R: type,
    items: []const T,
    results: []R,
    comptime func: anytype,
) void {
    if (!tp_enabled) return;

    const num_chunks = computeNumChunks(items.len, pool_workers);
    const chunk_size = (items.len + num_chunks - 1) / num_chunks;

    const ChunkContext = struct {
        items_ptr: []const T,
        results_ptr: []R,
        start: usize,
        end: usize,

        fn run(ctx_ptr: *anyopaque, _: *tp.TaskContext) void {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            for (self.start..self.end) |i| {
                self.results_ptr[i] = func(self.items_ptr[i]);
            }
        }
    };

    var ctxs: [MAX_CHUNKS]ChunkContext = undefined;
    var tasks: [MAX_CHUNKS]tp.BatchTask = undefined;
    var wg: tp.WaitGroup = .{};

    var n_chunks: usize = 0;
    var start: usize = 0;
    while (start < items.len) : (start += chunk_size) {
        const end = @min(start + chunk_size, items.len);
        ctxs[n_chunks] = ChunkContext{
            .items_ptr = items,
            .results_ptr = results,
            .start = start,
            .end = end,
        };
        tasks[n_chunks] = tp.BatchTask{
            .task_fn = ChunkContext.run,
            .ctx = &ctxs[n_chunks],
        };
        n_chunks += 1;
    }

    _ = pool.submitBatch(tasks[0..n_chunks], .{ .wait_group = &wg }) catch {
        // submitBatch with .return_error backpressure can partially enqueue
        // tasks before returning an error (enqueuePush calls wait_group.add(1)
        // before tryPush, and only calls wait_group.done() on QueueFull, not
        // on successfully-queued tasks).  Those accepted tasks are already
        // writing into results[].  Wait for them to drain before falling back
        // sequentially, otherwise both paths race on overlapping indices.
        wg.wait();
        sequentialForEach(T, R, items, results, func);
        return;
    };

    wg.wait();
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
    const items = [_]u32{ 10, 20, 30, 40, 50 };
    var results: [5]u64 = undefined;

    if (tp_enabled) {
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
    try std.testing.expectEqual(tp_enabled, is_enabled);
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

test "chunk count bounded by workers, items, and MAX_CHUNKS" {
    try std.testing.expectEqual(@as(usize, 2), computeNumChunks(8, 1)); // 1 worker * 2
    try std.testing.expectEqual(@as(usize, 8), computeNumChunks(64, 4)); // 4 workers * 2
    try std.testing.expectEqual(@as(usize, 16), computeNumChunks(16, 32)); // never more chunks than items
    try std.testing.expectEqual(@as(usize, 64), computeNumChunks(10_000, 64)); // MAX_CHUNKS cap
    try std.testing.expectEqual(@as(usize, 1), computeNumChunks(1, 0)); // degenerate: never zero
}
