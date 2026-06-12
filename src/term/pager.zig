// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Pager Module
//!
//! Pipes long output through a pager (like `less`) when appropriate.

const std = @import("std");
const builtin = @import("builtin");
const tty = @import("tty.zig");

/// Pager configuration
pub const PagerConfig = struct {
    /// Minimum lines to trigger pager
    min_lines: u16 = 0,
    /// Environment variable for pager command
    pager_env: []const u8 = "PAGER",
    /// Default pager command
    default_pager: []const u8 = "less -FIRX",
    /// Force pager even if not TTY
    force: bool = false,
};

/// Write content directly to stdout. Used as fallback when pager is unavailable.
fn writeDirect(stdout: std.Io.File, io: std.Io, content: []const u8) error{WriteFailed}!void {
    var wbuf: [4096]u8 = undefined;
    var fw = stdout.writer(io, &wbuf);
    fw.interface.writeAll(content) catch return error.WriteFailed;
    fw.interface.flush() catch return error.WriteFailed;
}

/// Write content through a pager if appropriate
pub fn writeIfTty(content: []const u8, config: PagerConfig) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const stdout = std.Io.File.stdout();

    // Check if we should use pager
    const is_tty = stdout.isTty(io) catch false;
    if (!config.force and !is_tty) {
        // Not a TTY, write directly
        return writeDirect(stdout, io, content);
    }

    // Count lines
    var line_count: usize = 0;
    for (content) |c| {
        if (c == '\n') line_count += 1;
    }

    // Get terminal height
    const term_info = tty.getInfo();

    // If content fits in terminal OR is below the min_lines threshold, write directly
    if (line_count < term_info.height or line_count < config.min_lines) {
        return writeDirect(stdout, io, content);
    }

    if (builtin.os.tag == .windows) {
        // Windows: fall back to direct output
        return writeDirect(stdout, io, content);
    }

    // Try to use pager
    const env_mod = @import("env.zig");
    const pager_cmd = env_mod.getEnvValueRuntime(config.pager_env) orelse config.default_pager;

    // Split pager command on whitespace into argv array (direct exec, no shell).
    // LIMITATION: This simple tokenizer does not handle quoted arguments.
    // Values like `PAGER='less -R "long arg"'` will be split incorrectly.
    // The pager command should only use simple space-separated arguments
    // (e.g., `less -FIRX`). At most 8 argv tokens are supported.
    var argv_buf: [8][]const u8 = undefined;
    var argv_len: usize = 0;
    var iter = std.mem.tokenizeAny(u8, pager_cmd, " \t");
    while (iter.next()) |token| {
        if (argv_len >= argv_buf.len) break;
        argv_buf[argv_len] = token;
        argv_len += 1;
    }
    if (argv_len == 0) {
        return writeDirect(stdout, io, content);
    }

    // Spawn pager process directly
    var child = std.process.Child.init(argv_buf[0..argv_len], std.heap.page_allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch {
        // Pager could not be started: emit directly instead of losing output.
        return writeDirect(stdout, io, content);
    };

    // Write content to pager stdin
    var write_failed = false;
    if (child.stdin) |stdin| {
        var wbuf: [4096]u8 = undefined;
        var fw = stdin.writer(io, &wbuf);
        fw.interface.writeAll(content) catch {
            write_failed = true;
        };
        if (!write_failed) fw.interface.flush() catch {
            write_failed = true;
        };
        stdin.close(io);
    }

    // Wait for pager to finish
    const term_result = child.wait(io) catch {
        if (write_failed) return writeDirect(stdout, io, content);
        return;
    };

    // If the pager could not consume the content (exec of an invalid PAGER
    // fails after fork -> nonzero exit; or our stdin write failed), re-emit
    // directly. A mid-stream pager crash may duplicate partial output; losing
    // the content entirely is worse.
    const pager_failed = switch (term_result) {
        .exited => |code| code != 0,
        else => true,
    };
    if (write_failed or pager_failed) {
        return writeDirect(stdout, io, content);
    }
}

/// Create a pager writer that buffers output
pub const PagerWriter = struct {
    buffer: std.Io.Writer.Allocating,
    allocator: std.mem.Allocator,
    config: PagerConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: PagerConfig) Self {
        return .{
            .buffer = .init(allocator),
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn writer(self: *Self) *std.Io.Writer {
        return &self.buffer.writer;
    }

    pub fn items(self: *Self) []u8 {
        return self.buffer.written();
    }

    pub fn flush(self: *Self) !void {
        try writeIfTty(self.buffer.written(), self.config);
        self.buffer.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PagerWriter initialization" {
    var pw = PagerWriter.init(std.testing.allocator, .{});
    defer pw.deinit();

    const w = pw.writer();
    try w.print("Hello, World!\n", .{});

    try std.testing.expect(pw.items().len > 0);
}

test "pager: PagerConfig default values" {
    const config = PagerConfig{};

    try std.testing.expectEqual(@as(u16, 0), config.min_lines);
    try std.testing.expectEqualStrings("PAGER", config.pager_env);
    try std.testing.expectEqualStrings("less -FIRX", config.default_pager);
    try std.testing.expectEqual(false, config.force);
}

test "pager: PagerConfig custom values" {
    const config = PagerConfig{
        .min_lines = 50,
        .pager_env = "MY_PAGER",
        .default_pager = "more",
        .force = true,
    };

    try std.testing.expectEqual(@as(u16, 50), config.min_lines);
    try std.testing.expectEqualStrings("MY_PAGER", config.pager_env);
    try std.testing.expectEqualStrings("more", config.default_pager);
    try std.testing.expectEqual(true, config.force);
}

test "pager: PagerWriter write multiple lines" {
    var pw = PagerWriter.init(std.testing.allocator, .{});
    defer pw.deinit();

    const w = pw.writer();
    try w.print("Line 1\n", .{});
    try w.print("Line 2\n", .{});
    try w.print("Line 3\n", .{});

    const output = pw.items();
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Line 3") != null);
}

test "pager: PagerWriter buffer grows" {
    var pw = PagerWriter.init(std.testing.allocator, .{});
    defer pw.deinit();

    const w = pw.writer();

    // Write a large amount of data
    for (0..100) |i| {
        try w.print("Line {d}: This is some content to fill the buffer\n", .{i});
    }

    try std.testing.expect(pw.items().len > 1000);
}

test "pager: PagerWriter deinit cleans up" {
    var pw = PagerWriter.init(std.testing.allocator, .{});

    const w = pw.writer();
    try w.print("Some content\n", .{});

    pw.deinit();
    // If we reach here without memory leaks, the test passes
}

test "pager: PagerWriter writer returns valid writer" {
    var pw = PagerWriter.init(std.testing.allocator, .{});
    defer pw.deinit();

    const w = pw.writer();

    // Test writing formatted output
    try w.print("{s}: {d}\n", .{ "count", 42 });

    const output = pw.items();
    try std.testing.expectEqualStrings("count: 42\n", output);
}

test "pager: PagerWriter handles empty writes" {
    var pw = PagerWriter.init(std.testing.allocator, .{});
    defer pw.deinit();

    const w = pw.writer();
    try w.print("", .{});

    try std.testing.expectEqual(@as(usize, 0), pw.items().len);
}

test "pager: PagerWriter preserves content order" {
    var pw = PagerWriter.init(std.testing.allocator, .{});
    defer pw.deinit();

    const w = pw.writer();
    try w.print("first", .{});
    try w.print("second", .{});
    try w.print("third", .{});

    try std.testing.expectEqualStrings("firstsecondthird", pw.items());
}
