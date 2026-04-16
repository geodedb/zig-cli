// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Benchmark Comparison Tool
//!
//! Compares two JSON benchmark result files and detects regressions.
//!
//! ## Usage
//!
//! ```sh
//! zig build compare-bench -- benchmarks/results/baseline.json /tmp/current.json
//! zig build compare-bench -- benchmarks/results/baseline.json /tmp/current.json 15
//! ```
//!
//! Exit codes:
//! - 0: All metrics within threshold (PASS)
//! - 1: At least one regression detected (FAIL)
//! - 2: Argument or file parsing error

const std = @import("std");

const MetricKind = enum {
    higher_is_better, // throughput: regression if current << baseline
    lower_is_better, // latency: regression if current >> baseline
};

const Metric = struct {
    name: []const u8,
    kind: MetricKind,
};

const metrics = [_]Metric{
    .{ .name = "parse_ns", .kind = .lower_is_better },
    .{ .name = "parse_ops_sec", .kind = .higher_is_better },
    .{ .name = "help_gen_ns", .kind = .lower_is_better },
    .{ .name = "bash_completion_ns", .kind = .lower_is_better },
    .{ .name = "zsh_completion_ns", .kind = .lower_is_better },
    .{ .name = "fish_completion_ns", .kind = .lower_is_better },
    .{ .name = "ps_completion_ns", .kind = .lower_is_better },
    .{ .name = "levenshtein_ns", .kind = .lower_is_better },
    .{ .name = "parallel_foreach_ns", .kind = .lower_is_better },
};

fn isRegression(delta_pct: f64, kind: MetricKind, threshold: f64) bool {
    return switch (kind) {
        .higher_is_better => delta_pct < -threshold,
        .lower_is_better => delta_pct > threshold,
    };
}

const JsonTier = struct {
    name: []const u8,
    values: [metrics.len]?f64,
};

fn parseTiers(allocator: std.mem.Allocator, json_bytes: []const u8) ![]JsonTier {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const tiers_val = root.get("tiers") orelse return error.MissingTiers;
    const tiers_arr = tiers_val.array;

    var result = try allocator.alloc(JsonTier, tiers_arr.items.len);
    for (tiers_arr.items, 0..) |tier_val, ti| {
        const tier_obj = tier_val.object;
        const name_val = tier_obj.get("name") orelse return error.MissingName;
        result[ti].name = switch (name_val) {
            .string => |s| try allocator.dupe(u8, s),
            else => return error.BadName,
        };

        for (metrics, 0..) |m, mi| {
            if (tier_obj.get(m.name)) |v| {
                result[ti].values[mi] = switch (v) {
                    .integer => |i| @floatFromInt(i),
                    .float => |f| f,
                    else => null,
                };
            } else {
                result[ti].values[mi] = null;
            }
        }
    }
    return result;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        const stderr = std.Io.File.stderr().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0);
        try stderr.print("Usage: compare-bench <baseline.json> <current.json> [threshold]\n", .{});
        try stderr.print("  Default threshold: 20 percent\n", .{});
        std.process.exit(2);
    }

    const baseline_path = args[1];
    const current_path = args[2];
    const threshold: f64 = if (args.len > 3) blk: {
        break :blk std.fmt.parseFloat(f64, args[3]) catch 20.0;
    } else 20.0;

    // Read files
    const baseline_bytes = std.fs.cwd().readFileAlloc(allocator, baseline_path, 10 * 1024 * 1024) catch |err| {
        std.Io.File.stderr().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0).print("Error reading baseline: {s}: {}\n", .{ baseline_path, err }) catch {};
        std.process.exit(2);
    };
    defer allocator.free(baseline_bytes);

    const current_bytes = std.fs.cwd().readFileAlloc(allocator, current_path, 10 * 1024 * 1024) catch |err| {
        std.Io.File.stderr().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0).print("Error reading current: {s}: {}\n", .{ current_path, err }) catch {};
        std.process.exit(2);
    };
    defer allocator.free(current_bytes);

    // Parse
    const baseline_tiers = parseTiers(allocator, baseline_bytes) catch |err| {
        std.Io.File.stderr().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0).print("Error parsing baseline JSON: {}\n", .{err}) catch {};
        std.process.exit(2);
    };
    const current_tiers = parseTiers(allocator, current_bytes) catch |err| {
        std.Io.File.stderr().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0).print("Error parsing current JSON: {}\n", .{err}) catch {};
        std.process.exit(2);
    };

    // Compare
    const stdout = std.Io.File.stdout().writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0);
    try stdout.print("\n  Benchmark Comparison (threshold: {d:.0})\n", .{threshold});
    try stdout.print("  =======================================\n\n", .{});
    try stdout.print("  {s:<8} {s:<24} {s:>14} {s:>14} {s:>8} {s:>6}\n", .{
        "Tier", "Metric", "Baseline", "Current", "Delta", "Status",
    });
    try stdout.print("  {s:-<8} {s:-<24} {s:->14} {s:->14} {s:->8} {s:->6}\n", .{
        "", "", "", "", "", "",
    });

    var any_fail = false;

    const tier_count = @min(baseline_tiers.len, current_tiers.len);
    for (0..tier_count) |ti| {
        const bt = baseline_tiers[ti];
        const ct = current_tiers[ti];

        for (metrics, 0..) |m, mi| {
            const bv = bt.values[mi] orelse continue;
            const cv = ct.values[mi] orelse continue;

            if (bv == 0) continue;

            const delta_pct = (cv - bv) / bv * 100.0;
            const is_fail = isRegression(delta_pct, m.kind, threshold);
            if (is_fail) any_fail = true;

            const status: []const u8 = if (is_fail) "FAIL" else "PASS";

            var delta_buf: [12]u8 = undefined;
            const delta_str = std.fmt.bufPrint(&delta_buf, "{d:.1}", .{delta_pct}) catch "?";
            try stdout.print("  {s:<8} {s:<24} {d:>14.1} {d:>14.1} {s:>8}  {s:>6}\n", .{
                bt.name, m.name, bv, cv, delta_str, status,
            });
        }
    }

    try stdout.print("\n", .{});

    if (any_fail) {
        try stdout.print("  RESULT: FAIL - regression(s) detected\n\n", .{});
        std.process.exit(1);
    } else {
        try stdout.print("  RESULT: PASS - all metrics within threshold\n\n", .{});
        std.process.exit(0);
    }
}
