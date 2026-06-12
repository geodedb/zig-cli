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

/// Maximum worker threads the thread-pool library accepts. thread_pool 0.2.4
/// hard-caps `max_threads` at 64 (its non-empty-workers steal bitmap is a
/// single u64) and `Config.validate()` rejects `max_threads > 64` with
/// `error.TooManyWorkers`. The library is not exported as a named constant, so
/// it is mirrored here; an explicit `worker_count` above this would make
/// `ThreadPool.init` fail. The auto path (`max_threads = 0`) is clamped to <=64
/// inside the library's `normalized()`, so only the explicit path needs us to
/// clamp. Keep in sync with the vendored dep if it ever lifts the cap.
const MAX_WORKERS: usize = 64;

/// Clamp an explicit worker count to the thread-pool maximum.
///
/// `null` (auto-detect) passes through as 0 — the library auto-clamps the
/// detected CPU count to `MAX_WORKERS` itself. An explicit count above the cap
/// is clamped down so `ThreadPool.init` cannot fail with `error.TooManyWorkers`
/// (8-1). The clamped value is what `pool_workers` records, so chunking math
/// reflects the real worker count rather than the caller's request.
fn clampWorkerCount(worker_count: ?usize) usize {
    const requested = worker_count orelse 0;
    return @min(requested, MAX_WORKERS);
}

/// Initialize and start the thread pool.
/// Call once at program startup. No-op if thread-pool is disabled.
pub fn initPool(config: PoolConfig) void {
    if (!tp_enabled) return;

    if (pool_started.load(.acquire)) return;

    // Clamp the explicit worker count to the library cap so an over-large
    // `--jobs N` (or getCpuCount() on >64-thread hardware) does not abort the
    // process via thread_pool's `error.TooManyWorkers` (8-1). worker_count=0
    // (auto) stays 0; the library clamps the detected CPU count itself.
    const max: usize = clampWorkerCount(config.worker_count);
    // The remaining `catch @panic` covers a genuine init failure (OOM). initPool
    // returns void and is documented as "call once at startup", so aborting on
    // an out-of-memory pool allocation is acceptable: the program cannot make
    // progress without its worker pool.
    pool = tp.ThreadPool.init(std.heap.page_allocator, .{
        .max_threads = max,
    }) catch @panic("thread-pool: init failed");
    // Record the CLAMPED worker count, not the requested one, so chunking math
    // (computeNumChunks) is consistent with the pool that actually spawned. On
    // the auto path the library clamps the detected CPU count to MAX_WORKERS, so
    // clamp the locally-detected count too to stay in agreement on >64-thread
    // hardware.
    pool_workers = if (max > 0) max else @min(std.Thread.getCpuCount() catch 1, MAX_WORKERS);
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

/// Half-open item-index range `[start, end)`.
const TailRange = struct { start: usize, end: usize };

/// Item-index range covered by the chunks `submitBatch` did NOT accept (8-2).
///
/// Chunks are carved as contiguous `chunk_size`-wide spans over the items, so
/// chunk `c` owns items `[c*chunk_size, min((c+1)*chunk_size, items_len))`. When
/// only `submitted` of `n_chunks` were enqueued, the tail chunks
/// `[submitted, n_chunks)` cover items `[submitted*chunk_size, items_len)` and
/// must be executed inline by the caller — their result slices are disjoint from
/// the submitted chunks, so there is no race with the in-flight tasks.
///
/// `start` is clamped to `items_len` so a (pathological) `submitted` larger than
/// `n_chunks` can never produce `start > end`.
fn tailItemRange(n_chunks: usize, chunk_size: usize, submitted: usize, items_len: usize) TailRange {
    _ = n_chunks; // shape documented above; the tail is bounded by items_len.
    const start = @min(submitted * chunk_size, items_len);
    return .{ .start = start, .end = items_len };
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

    const result = pool.submitBatch(tasks[0..n_chunks], .{ .wait_group = &wg }) catch {
        // submitBatch only returns an error when NOTHING was enqueued (the very
        // first task hit QueueFull / TaskPoolExhausted / a shutdown). The
        // wait-group counter is therefore zero, so wg.wait() is a no-op; run
        // everything sequentially. (A partial enqueue returns a non-error
        // SubmitBatchResult — handled below, not here.)
        wg.wait();
        sequentialForEach(T, R, items, results, func);
        return;
    };

    // 8-2: with the default `.return_error` backpressure, a queue-full
    // mid-batch returns a SUCCESSFUL SubmitBatchResult whose `submitted` count
    // is below n_chunks. The submitted chunks are already running into their
    // result slices; the unsubmitted tail chunks were silently dropped. Run the
    // tail inline NOW (its item range is disjoint from every submitted chunk, so
    // it does not race the in-flight tasks), then wait for the submitted ones.
    if (result.submitted < n_chunks) {
        const tail = tailItemRange(n_chunks, chunk_size, result.submitted, items.len);
        sequentialForEach(
            T,
            R,
            items[tail.start..tail.end],
            results[tail.start..tail.end],
            func,
        );
    }

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

test "clampWorkerCount: explicit >MAX clamps, auto/in-range pass through" {
    // 8-1: thread_pool validate() rejects max_threads > MAX_WORKERS with
    // error.TooManyWorkers; the explicit path must clamp before init.
    try std.testing.expectEqual(@as(usize, 0), clampWorkerCount(null)); // auto stays 0 (lib clamps)
    try std.testing.expectEqual(@as(usize, 4), clampWorkerCount(4)); // in-range unchanged
    try std.testing.expectEqual(MAX_WORKERS, clampWorkerCount(MAX_WORKERS)); // exactly at cap
    try std.testing.expectEqual(MAX_WORKERS, clampWorkerCount(100)); // explicit >cap clamps
    try std.testing.expectEqual(MAX_WORKERS, clampWorkerCount(10_000));
}

test "parallel: initPool with worker_count over thread-pool cap does not panic" {
    // 8-1: initPool(.{ .worker_count = 100 }) previously @panic'd because
    // thread_pool's validate() rejects max_threads > 64. Clamping keeps init
    // alive; a subsequent forEach over >= min_parallel_items must be correct.
    if (!tp_enabled) return;

    initPool(.{ .worker_count = 100 });
    defer deinitPool();

    // pool_workers reflects the CLAMPED value, not the requested 100.
    try std.testing.expectEqual(MAX_WORKERS, pool_workers);

    const items = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var results: [8]u64 = undefined;
    forEach(u32, u64, &items, &results, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x) * 2;
        }
    }.compute);

    for (items, 0..) |item, i| {
        try std.testing.expectEqual(@as(u64, item) * 2, results[i]);
    }
}

test "parallel: initPool with null worker_count still works" {
    // 8-1 regression guard: auto-detect path (worker_count = null) must keep
    // working — it relies on the library auto-clamping the CPU count to <= 64.
    if (!tp_enabled) return;

    initPool(.{ .worker_count = null });
    defer deinitPool();

    const items = [_]u32{ 10, 20, 30, 40, 50, 60 };
    var results: [6]u64 = undefined;
    forEach(u32, u64, &items, &results, struct {
        fn compute(x: u32) u64 {
            return @as(u64, x) + 1;
        }
    }.compute);

    for (items, 0..) |item, i| {
        try std.testing.expectEqual(@as(u64, item) + 1, results[i]);
    }
}

test "tailItemRange: unsubmitted chunk tail maps to correct item indices" {
    // 8-2: when submitBatch enqueues only `submitted` of `n_chunks`, the
    // tail chunks [submitted, n_chunks) cover item indices
    // [submitted*chunk_size, items_len). Pure range math, unit-testable
    // without saturating the real queue.

    // 8 items, 4 chunks of 2; 2 submitted -> tail covers items [4, 8).
    try std.testing.expectEqual(
        TailRange{ .start = 4, .end = 8 },
        tailItemRange(4, 2, 2, 8),
    );
    // Fully submitted -> empty tail (start == end == items_len).
    try std.testing.expectEqual(
        TailRange{ .start = 8, .end = 8 },
        tailItemRange(4, 2, 4, 8),
    );
    // Nothing submitted -> whole range is the tail.
    try std.testing.expectEqual(
        TailRange{ .start = 0, .end = 8 },
        tailItemRange(4, 2, 0, 8),
    );
    // Ragged last chunk: 7 items, 4 chunks, chunk_size 2; 3 submitted ->
    // tail starts at 6, ends at 7 (the short final chunk).
    try std.testing.expectEqual(
        TailRange{ .start = 6, .end = 7 },
        tailItemRange(4, 2, 3, 7),
    );
    // Clamp guard: a submitted count that would push start past items_len
    // (cannot happen in practice, but the math must not produce start > end).
    try std.testing.expectEqual(
        TailRange{ .start = 7, .end = 7 },
        tailItemRange(4, 2, 5, 7),
    );
}
