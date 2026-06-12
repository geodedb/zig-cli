// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Progress Module
//!
//! Progress indicators (spinners, bars) for long-running operations.
//! Only shows progress when stdout is a TTY.
//!
//! ## Thread Safety
//!
//! `ProgressBar` is thread-safe: multiple threads may call `update()` or
//! `increment()` concurrently. The current value uses atomic operations and
//! render output is mutex-protected. `Progress` (spinner) is NOT thread-safe
//! and should only be used from a single thread.

const std = @import("std");
const tty = @import("tty.zig");
const sanitize = @import("sanitize");

inline fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Direct-write stderr helper: writes `data` via an ephemeral buffered writer.
fn stderrWriteAll(data: []const u8) void {
    var wbuf: [4096]u8 = undefined;
    var fw = std.Io.File.stderr().writer(io(), &wbuf);
    fw.interface.writeAll(data) catch {};
    fw.interface.flush() catch {};
}

fn stderrPrint(comptime fmt: []const u8, args: anytype) !void {
    var wbuf: [4096]u8 = undefined;
    var fw = std.Io.File.stderr().writer(io(), &wbuf);
    try fw.interface.print(fmt, args);
    try fw.interface.flush();
}

/// Spinner characters
pub const SpinnerStyle = enum {
    dots,
    line,
    arrow,
    pulse,

    pub fn frames(self: SpinnerStyle) []const []const u8 {
        return switch (self) {
            .dots => &.{ ".", "..", "...", ".." },
            .line => &.{ "-", "\\", "|", "/" },
            .arrow => &.{ ">", ">>", ">>>", ">>" },
            .pulse => &.{ ".", "o", "O", "o" },
        };
    }
};

/// Progress indicator
pub const Progress = struct {
    enabled: bool,
    message: []const u8,
    spinner_style: SpinnerStyle,
    frame_index: usize,

    const Self = @This();

    /// Start a new progress indicator
    pub fn start(message: []const u8) Self {
        const is_tty = tty.isStderrTty();

        var self = Self{
            .enabled = is_tty,
            .message = message,
            .spinner_style = .dots,
            .frame_index = 0,
        };

        if (self.enabled) {
            // NP-031: hide-cursor + first frame batched into one write
            self.renderWithPrefix("\x1b[?25l") catch {};
        }

        return self;
    }

    /// Start with TTY check from context
    pub fn startIfTty(is_tty: bool, message: []const u8) Self {
        var self = Self{
            .enabled = is_tty,
            .message = message,
            .spinner_style = .dots,
            .frame_index = 0,
        };

        if (self.enabled) {
            // NP-031: hide-cursor + first frame batched into one write
            self.renderWithPrefix("\x1b[?25l") catch {};
        }

        return self;
    }

    /// Update progress message
    pub fn update(self: *Self, message: []const u8) void {
        self.message = message;
        if (self.enabled) {
            self.render() catch {};
        }
    }

    /// Tick the spinner
    pub fn tick(self: *Self) void {
        if (!self.enabled) return;

        const frames = self.spinner_style.frames();
        self.frame_index = (self.frame_index + 1) % frames.len;
        self.render() catch {};
    }

    /// Stop the progress indicator
    pub fn stop(self: *Self) void {
        if (!self.enabled) return;

        // Clear line and show cursor
        stderrPrint("\r\x1b[K\x1b[?25h", .{}) catch {};
    }

    /// Stop with a completion message. The message is control-filtered so
    /// caller data cannot inject ANSI/OSC escape sequences (NS-056 / CWE-150).
    pub fn stopWithMessage(self: *Self, message: []const u8) void {
        var mbuf: [256]u8 = undefined;
        var mw = std.Io.Writer.fixed(&mbuf);
        // Truncation of >256-byte messages is acceptable for a single line.
        sanitize.writeControlFiltered(&mw, message) catch {};
        if (self.enabled) {
            // Clear line, show message, show cursor
            stderrPrint("\r\x1b[K{s}\n\x1b[?25h", .{mw.buffered()}) catch {};
        } else {
            stderrPrint("{s}\n", .{mw.buffered()}) catch {};
        }
    }

    fn render(self: *Self) !void {
        return self.renderWithPrefix("");
    }

    /// Render the spinner line; `prefix` is emitted in the same single write
    /// (used to batch the hide-cursor sequence with the first render).
    /// `prefix` bypasses sanitization: callers must pass only trusted,
    /// compile-time-constant ANSI sequences.
    fn renderWithPrefix(self: *Self, prefix: []const u8) !void {
        const frames = self.spinner_style.frames();
        const frame = frames[self.frame_index];

        // Control-filter the message so caller data cannot inject ANSI/OSC
        // escape sequences (NS-056 / CWE-150).
        var mbuf: [256]u8 = undefined;
        var mw = std.Io.Writer.fixed(&mbuf);
        // Truncation of >256-byte messages is acceptable for a single
        // spinner line.
        sanitize.writeControlFiltered(&mw, self.message) catch {};

        // Clear line and write progress
        try stderrPrint("{s}\r\x1b[K{s} {s}", .{ prefix, frame, mw.buffered() });
    }
};

/// Compute the bar width for a terminal of `term_width` columns.
/// Saturating: never underflows on narrow terminals; minimum 1 column.
fn barWidthForTerminal(term_width: u16) u16 {
    return @max(@min(term_width -| 20, 50), 1);
}

/// Thread-safe progress bar.
///
/// Multiple threads may call `update()` or `increment()` concurrently.
/// The current value is stored atomically and render output is
/// serialized with a mutex. The `total` and `message` fields are
/// set at init time and should not be modified after creation.
pub const ProgressBar = struct {
    total: usize,
    current: std.atomic.Value(usize),
    width: u16,
    enabled: bool,
    message: []const u8,
    render_mutex: RenderMutex,

    const Self = @This();

    const RenderMutex = struct {
        inner: std.Io.Mutex = .init,

        fn lock(self: *RenderMutex) void {
            self.inner.lockUncancelable(io());
        }
        fn unlock(self: *RenderMutex) void {
            self.inner.unlock(io());
        }
    };

    /// Create a new progress bar
    pub fn init(total: usize, message: []const u8) Self {
        const term_info = tty.getInfo();

        return .{
            .total = total,
            .current = std.atomic.Value(usize).init(0),
            .width = barWidthForTerminal(term_info.width),
            .enabled = term_info.is_tty,
            .message = message,
            .render_mutex = .{},
        };
    }

    /// Update progress (thread-safe)
    pub fn update(self: *Self, current: usize) void {
        const clamped = @min(current, self.total);
        self.current.store(clamped, .release);
        if (self.enabled) {
            self.render_mutex.lock();
            defer self.render_mutex.unlock();
            self.render() catch {};
        }
    }

    /// Increment by one (thread-safe)
    pub fn increment(self: *Self) void {
        const prev = self.current.fetchAdd(1, .acq_rel);
        const new_val = @min(prev + 1, self.total);
        self.current.store(new_val, .release);
        if (self.enabled) {
            self.render_mutex.lock();
            defer self.render_mutex.unlock();
            self.render() catch {};
        }
    }

    /// Complete the progress bar
    pub fn finish(self: *Self) void {
        self.current.store(self.total, .release);
        if (self.enabled) {
            self.render_mutex.lock();
            defer self.render_mutex.unlock();
            self.render() catch {};
            stderrPrint("\n", .{}) catch {};
        }
    }

    /// Read the current progress value (thread-safe)
    pub fn getCurrent(self: *const Self) usize {
        return self.current.load(.acquire);
    }

    /// Filled cell count for a bar of `width` showing `cur`/`total` progress.
    /// `cur` is clamped to `total` first: increment() advances `current` with an
    /// unsynchronized fetchAdd (outside render_mutex), so a concurrent reader can
    /// observe cur > total. Without the clamp the result could exceed `width` and
    /// the caller's `width - filled` would underflow (CWE-191) — a panic in safe
    /// builds, a near-infinite stderr write in ReleaseFast (CWE-362 DoS).
    fn barFilled(cur: usize, total: usize, width: u16) u16 {
        if (total == 0) return 0;
        const clamped = @min(cur, total);
        return @intCast((clamped * width) / total);
    }

    /// Percent complete (0..100), clamped against a concurrent over-`total`
    /// `cur` for the same reason as `barFilled`.
    fn barPercent(cur: usize, total: usize) usize {
        if (total == 0) return 0;
        return (@min(cur, total) * 100) / total;
    }

    fn render(self: *Self) !void {
        const cur = self.current.load(.acquire);

        const percent = barPercent(cur, self.total);

        const filled = barFilled(cur, self.total, self.width);

        // Saturating as defense-in-depth; barFilled already keeps filled <= width.
        const empty = self.width -| filled;

        // Control-filter the message so caller data cannot inject ANSI/OSC
        // escape sequences (NS-056 / CWE-150).
        var mbuf: [256]u8 = undefined;
        var mw = std.Io.Writer.fixed(&mbuf);
        // Truncation of >256-byte messages is acceptable for a single line.
        sanitize.writeControlFiltered(&mw, self.message) catch {};

        var wbuf: [4096]u8 = undefined;
        var fw = std.Io.File.stderr().writer(io(), &wbuf);
        const w = &fw.interface;

        try w.print("\r{s} [", .{mw.buffered()});

        try w.splatByteAll('=', filled);
        try w.splatByteAll(' ', empty);

        try w.print("] {d}%", .{percent});
        try w.flush();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Progress indicator creation" {
    var progress = Progress.startIfTty(false, "Loading...");
    progress.tick();
    progress.stop();
}

test "ProgressBar initialization" {
    const bar = ProgressBar.init(100, "Progress");
    try std.testing.expectEqual(@as(usize, 0), bar.getCurrent());
    try std.testing.expectEqual(@as(usize, 100), bar.total);
}

test "progress: SpinnerStyle dots frames" {
    const frames = SpinnerStyle.dots.frames();
    try std.testing.expectEqual(@as(usize, 4), frames.len);
    try std.testing.expectEqualStrings(".", frames[0]);
    try std.testing.expectEqualStrings("..", frames[1]);
    try std.testing.expectEqualStrings("...", frames[2]);
    try std.testing.expectEqualStrings("..", frames[3]);
}

test "progress: SpinnerStyle line frames" {
    const frames = SpinnerStyle.line.frames();
    try std.testing.expectEqual(@as(usize, 4), frames.len);
    try std.testing.expectEqualStrings("-", frames[0]);
    try std.testing.expectEqualStrings("\\", frames[1]);
    try std.testing.expectEqualStrings("|", frames[2]);
    try std.testing.expectEqualStrings("/", frames[3]);
}

test "progress: SpinnerStyle arrow frames" {
    const frames = SpinnerStyle.arrow.frames();
    try std.testing.expectEqual(@as(usize, 4), frames.len);
    try std.testing.expectEqualStrings(">", frames[0]);
    try std.testing.expectEqualStrings(">>", frames[1]);
    try std.testing.expectEqualStrings(">>>", frames[2]);
    try std.testing.expectEqualStrings(">>", frames[3]);
}

test "progress: SpinnerStyle pulse frames" {
    const frames = SpinnerStyle.pulse.frames();
    try std.testing.expectEqual(@as(usize, 4), frames.len);
    try std.testing.expectEqualStrings(".", frames[0]);
    try std.testing.expectEqualStrings("o", frames[1]);
    try std.testing.expectEqualStrings("O", frames[2]);
    try std.testing.expectEqualStrings("o", frames[3]);
}

test "progress: Progress disabled when not TTY" {
    var progress = Progress.startIfTty(false, "Loading...");
    try std.testing.expectEqual(false, progress.enabled);
    progress.stop();
}

test "progress: Progress message update" {
    var progress = Progress.startIfTty(false, "Initial");
    try std.testing.expectEqualStrings("Initial", progress.message);

    progress.update("Updated");
    try std.testing.expectEqualStrings("Updated", progress.message);
    progress.stop();
}

test "progress: Progress tick when disabled does not crash" {
    var progress = Progress.startIfTty(false, "Loading...");
    // When disabled, tick returns early without modifying frame_index
    progress.tick();
    progress.tick();
    progress.stop();
    // Just verify it doesn't crash
}

test "progress: Progress frame_index starts at zero" {
    var progress = Progress.startIfTty(false, "Loading...");
    try std.testing.expectEqual(@as(usize, 0), progress.frame_index);
    progress.stop();
}

test "progress: Progress default spinner style" {
    var progress = Progress.startIfTty(false, "Loading...");
    try std.testing.expectEqual(SpinnerStyle.dots, progress.spinner_style);
    progress.stop();
}

test "progress: ProgressBar update within bounds" {
    var bar = ProgressBar.init(100, "Progress");
    bar.enabled = false; // Disable TTY output for test

    bar.update(50);
    try std.testing.expectEqual(@as(usize, 50), bar.getCurrent());

    bar.update(100);
    try std.testing.expectEqual(@as(usize, 100), bar.getCurrent());
}

test "progress: ProgressBar update clamps to total" {
    var bar = ProgressBar.init(100, "Progress");
    bar.enabled = false;

    bar.update(150); // Over the total
    try std.testing.expectEqual(@as(usize, 100), bar.getCurrent());
}

test "progress: ProgressBar increment" {
    var bar = ProgressBar.init(100, "Progress");
    bar.enabled = false;

    try std.testing.expectEqual(@as(usize, 0), bar.getCurrent());

    bar.increment();
    try std.testing.expectEqual(@as(usize, 1), bar.getCurrent());

    bar.increment();
    try std.testing.expectEqual(@as(usize, 2), bar.getCurrent());
}

test "progress: bar cell math clamps a concurrent over-total current (no underflow)" {
    // increment() can advance current past total outside the render mutex; the
    // bar math must clamp so width - filled cannot underflow (CWE-191/362).
    const width: u16 = 50;

    // Normal cases.
    try std.testing.expectEqual(@as(u16, 0), ProgressBar.barFilled(0, 100, width));
    try std.testing.expectEqual(@as(u16, 25), ProgressBar.barFilled(50, 100, width));
    try std.testing.expectEqual(@as(u16, 50), ProgressBar.barFilled(100, 100, width));

    // Over-total (the race): filled is clamped to width, so empty = width -| filled = 0.
    const filled_over = ProgressBar.barFilled(102, 100, width);
    try std.testing.expectEqual(@as(u16, 50), filled_over);
    try std.testing.expectEqual(@as(u16, 0), width -| filled_over);
    try std.testing.expectEqual(@as(usize, 100), ProgressBar.barPercent(102, 100));

    // total == 0 degenerate.
    try std.testing.expectEqual(@as(u16, 0), ProgressBar.barFilled(5, 0, width));
    try std.testing.expectEqual(@as(usize, 0), ProgressBar.barPercent(5, 0));
}

test "progress: ProgressBar finish sets to total" {
    var bar = ProgressBar.init(100, "Progress");
    bar.enabled = false;

    bar.update(50);
    bar.finish();

    try std.testing.expectEqual(@as(usize, 100), bar.getCurrent());
}

test "progress: ProgressBar zero total" {
    var bar = ProgressBar.init(0, "Empty");
    bar.enabled = false;

    // Should not crash with zero total
    bar.update(0);
    bar.increment();
    bar.finish();

    try std.testing.expectEqual(@as(usize, 0), bar.getCurrent());
}

test "progress: ProgressBar message" {
    const bar = ProgressBar.init(100, "Downloading");
    try std.testing.expectEqualStrings("Downloading", bar.message);
}

test "progress: Progress stopWithMessage when disabled" {
    var progress = Progress.startIfTty(false, "Loading...");
    // Should not crash when disabled
    progress.stopWithMessage("Done!");
}

test "progress: ProgressBar width computation does not underflow on narrow terminals" {
    try std.testing.expectEqual(@as(u16, 1), barWidthForTerminal(10));
    try std.testing.expectEqual(@as(u16, 1), barWidthForTerminal(0));
    try std.testing.expectEqual(@as(u16, 50), barWidthForTerminal(200));
    try std.testing.expectEqual(@as(u16, 20), barWidthForTerminal(40));
}
