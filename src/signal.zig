// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Signal Handling Module
//!
//! Cross-platform signal handling for graceful shutdown and interrupt handling.
//!
//! ## Design: Flag-and-Poll Pattern
//!
//! Signal handlers only set atomic flags. Cleanup callbacks run in normal
//! execution context via `pollSignals()`, which makes them safe to perform
//! any operation (allocate memory, acquire locks, do I/O, etc.).
//!
//! ## Thread Safety
//!
//! All public functions are thread-safe. Signal state uses atomic operations
//! with acquire/release ordering. Callback registration is mutex-protected.
//!
//! ## Usage
//!
//! ```zig
//! const signal = @import("cli").signal;
//!
//! pub fn main() !void {
//!     signal.install(.{}) catch {};
//!     signal.onCleanup(myCleanupFn);
//!
//!     while (!signal.shouldShutdown()) {
//!         // Do work...
//!     }
//!
//!     // Run cleanup callbacks in normal context
//!     _ = signal.pollSignals();
//! }
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Signal types we handle
pub const Signal = enum {
    /// SIGINT (Ctrl+C)
    interrupt,
    /// SIGTERM
    terminate,
    /// SIGHUP
    hangup,
    /// SIGQUIT
    quit,
};

/// Signal handler configuration
pub const Config = struct {
    /// Handle SIGINT (Ctrl+C)
    handle_interrupt: bool = true,
    /// Handle SIGTERM
    handle_terminate: bool = true,
    /// Handle SIGHUP
    handle_hangup: bool = false,
    /// Handle SIGQUIT
    handle_quit: bool = false,
};

/// Cleanup callback function type.
///
/// Cleanup callbacks are invoked from normal execution context via
/// `pollSignals()`, NOT from the signal handler itself. This means
/// callbacks are free to perform any operation (allocate memory,
/// acquire locks, perform buffered I/O, etc.).
///
/// The signal handler only sets atomic flags; `pollSignals()` checks
/// those flags and runs callbacks safely outside signal context.
///
/// Call `pollSignals()` periodically from your main loop or after
/// checking `shouldShutdown()` to execute registered callbacks.
pub const CleanupFn = *const fn () void;

/// Global state for signal handling
var interrupted: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var terminated: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
/// Set by signal handlers to indicate callbacks should be run via pollSignals().
var signal_pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var cleanup_callbacks: [16]?CleanupFn = .{null} ** 16;
var callback_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var mutex: Mutex = .{};

inline fn io_() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

const Mutex = struct {
    inner: std.Io.Mutex = .init,

    fn lock(self: *Mutex) void {
        self.inner.lockUncancelable(io_());
    }

    fn unlock(self: *Mutex) void {
        self.inner.unlock(io_());
    }
};
/// Atomic flags for Windows console control handler (thread-safe).
/// These replace a plain `Config` struct to avoid data races between
/// the main thread (install) and the handler thread (windowsCtrlHandler).
var win_handle_interrupt: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var win_handle_terminate: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Check if an interrupt signal was received (SIGINT)
pub fn wasInterrupted() bool {
    return interrupted.load(.acquire);
}

/// Check if a termination signal was received (SIGTERM)
pub fn wasTerminated() bool {
    return terminated.load(.acquire);
}

/// Check if any shutdown signal was received
pub fn shouldShutdown() bool {
    return wasInterrupted() or wasTerminated();
}

/// Poll for pending signals and run cleanup callbacks in normal context.
///
/// This is the safe way to execute cleanup callbacks. The signal handler
/// only sets atomic flags; this function checks those flags and runs
/// callbacks outside signal context where any operation is safe.
///
/// Call this periodically from your main loop:
/// ```zig
/// while (!signal.shouldShutdown()) {
///     // Do work...
///     signal.pollSignals();
/// }
/// signal.pollSignals(); // Run final cleanup
/// ```
///
/// Returns true if callbacks were executed, false if no signal was pending.
pub fn pollSignals() bool {
    if (!signal_pending.load(.acquire)) return false;

    // Clear the pending flag before running callbacks.
    // If another signal arrives during callback execution,
    // signal_pending will be set again.
    signal_pending.store(false, .release);
    runCleanupCallbacks();
    return true;
}

/// Register a cleanup callback to be invoked when a signal is received.
/// Returns error if max callbacks reached (limit: 16).
///
/// Callbacks run in NORMAL execution context from `pollSignals()`, NOT
/// inside a signal handler. They may freely allocate memory, acquire
/// locks, and perform buffered I/O. See `CleanupFn` for details.
pub fn onCleanup(callback: CleanupFn) !void {
    mutex.lock();
    defer mutex.unlock();

    const count = callback_count.load(.acquire);
    if (count >= cleanup_callbacks.len) {
        return error.TooManyCallbacks;
    }

    cleanup_callbacks[count] = callback;
    callback_count.store(count + 1, .release);
}

/// Clear the interrupted flag (useful for testing or restart scenarios)
pub fn clearInterrupted() void {
    interrupted.store(false, .release);
}

/// Clear the terminated flag
pub fn clearTerminated() void {
    terminated.store(false, .release);
}

/// Install signal handlers
pub fn install(config: Config) !void {
    if (builtin.os.tag == .windows) {
        try installWindows(config);
    } else {
        try installPosix(config);
    }
}

/// Uninstall signal handlers and restore defaults
pub fn uninstall() void {
    if (builtin.os.tag == .windows) {
        uninstallWindows();
    } else {
        uninstallPosix();
    }
}

// ============================================================================
// POSIX Implementation
// ============================================================================

fn installPosix(config: Config) !void {
    const handler = std.posix.Sigaction{
        .handler = .{ .handler = posixSignalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    if (config.handle_interrupt) {
        std.posix.sigaction(std.posix.SIG.INT, &handler, null);
    }
    if (config.handle_terminate) {
        std.posix.sigaction(std.posix.SIG.TERM, &handler, null);
    }
    if (config.handle_hangup) {
        std.posix.sigaction(std.posix.SIG.HUP, &handler, null);
    }
    if (config.handle_quit) {
        std.posix.sigaction(std.posix.SIG.QUIT, &handler, null);
    }
}

fn uninstallPosix() void {
    const default_handler = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.INT, &default_handler, null);
    std.posix.sigaction(std.posix.SIG.TERM, &default_handler, null);
    std.posix.sigaction(std.posix.SIG.HUP, &default_handler, null);
    std.posix.sigaction(std.posix.SIG.QUIT, &default_handler, null);
}

const SigType = @TypeOf(std.posix.SIG.INT);

fn posixSignalHandler(sig: SigType) callconv(.c) void {
    if (sig == std.posix.SIG.INT) {
        interrupted.store(true, .release);
    } else if (sig == std.posix.SIG.TERM) {
        terminated.store(true, .release);
    } else if (sig == std.posix.SIG.HUP or sig == std.posix.SIG.QUIT) {
        terminated.store(true, .release);
    }

    // Flag that callbacks need to run; pollSignals() will invoke them
    // in normal execution context where any operation is safe.
    signal_pending.store(true, .release);
}

// ============================================================================
// Windows Implementation
// ============================================================================

// Zig 0.16 removed GetModuleHandleW from std.os.windows.kernel32; declare
// SetConsoleCtrlHandler as a direct extern instead of resolving it at runtime.
extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: ?*const fn (std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL,
    Add: std.os.windows.BOOL,
) callconv(.winapi) std.os.windows.BOOL;

fn installWindows(config: Config) !void {
    if (builtin.os.tag != .windows) {
        return;
    }

    // Nothing to handle — skip registration entirely
    if (!config.handle_interrupt and !config.handle_terminate) {
        return;
    }

    // Store config atomically so the handler thread can read safely
    win_handle_interrupt.store(config.handle_interrupt, .release);
    win_handle_terminate.store(config.handle_terminate, .release);

    if (SetConsoleCtrlHandler(windowsCtrlHandler, .TRUE) == .FALSE) {
        return error.SetHandlerFailed;
    }
}

fn uninstallWindows() void {
    if (builtin.os.tag != .windows) {
        return;
    }

    _ = SetConsoleCtrlHandler(windowsCtrlHandler, .FALSE);
}

fn windowsCtrlHandler(ctrl_type: std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL {
    const CTRL_C_EVENT: std.os.windows.DWORD = 0;
    const CTRL_BREAK_EVENT: std.os.windows.DWORD = 1;
    const CTRL_CLOSE_EVENT: std.os.windows.DWORD = 2;

    switch (ctrl_type) {
        CTRL_C_EVENT, CTRL_BREAK_EVENT => {
            if (!win_handle_interrupt.load(.acquire)) return .FALSE;
            interrupted.store(true, .release);
            signal_pending.store(true, .release);
            return .TRUE; // TRUE - handled
        },
        CTRL_CLOSE_EVENT => {
            if (!win_handle_terminate.load(.acquire)) return .FALSE;
            terminated.store(true, .release);
            signal_pending.store(true, .release);
            return .TRUE; // TRUE - handled
        },
        else => return .FALSE, // FALSE - not handled
    }
}

// ============================================================================
// Shared Helpers
// ============================================================================

fn runCleanupCallbacks() void {
    // Called from pollSignals() in normal execution context (not signal handler).
    // Safe to perform any operation. No locking needed for the read since
    // callback_count is atomic and the array is append-only.
    const count = callback_count.load(.acquire);
    for (cleanup_callbacks[0..count]) |maybe_cb| {
        if (maybe_cb) |cb| {
            cb();
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "initial state is not interrupted" {
    clearInterrupted();
    clearTerminated();
    try std.testing.expect(!wasInterrupted());
    try std.testing.expect(!wasTerminated());
    try std.testing.expect(!shouldShutdown());
}

test "install and uninstall handlers" {
    if (builtin.os.tag == .windows) {
        // Skip on Windows in test environment
        return;
    }

    try install(.{});
    uninstall();
}

test "register cleanup callback" {
    // Reset state for test
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;

    const cb = struct {
        fn callback() void {
            // Placeholder - actual test would verify this was called
        }
    }.callback;

    try onCleanup(cb);
    try std.testing.expectEqual(@as(usize, 1), callback_count.load(.acquire));
}

test "Config default values" {
    const config = Config{};
    try std.testing.expect(config.handle_interrupt);
    try std.testing.expect(config.handle_terminate);
    try std.testing.expect(!config.handle_hangup);
    try std.testing.expect(!config.handle_quit);
}

test "Config custom values" {
    const config = Config{
        .handle_interrupt = false,
        .handle_terminate = false,
        .handle_hangup = true,
        .handle_quit = true,
    };
    try std.testing.expect(!config.handle_interrupt);
    try std.testing.expect(!config.handle_terminate);
    try std.testing.expect(config.handle_hangup);
    try std.testing.expect(config.handle_quit);
}

test "Windows atomic config flags" {
    win_handle_interrupt.store(true, .release);
    win_handle_terminate.store(false, .release);
    try std.testing.expect(win_handle_interrupt.load(.acquire));
    try std.testing.expect(!win_handle_terminate.load(.acquire));

    win_handle_interrupt.store(false, .release);
    win_handle_terminate.store(false, .release);
}

test "install with no-op config does not error" {
    if (comptime builtin.os.tag == .windows) {
        try install(.{
            .handle_interrupt = false,
            .handle_terminate = false,
        });
    } else {
        try install(.{
            .handle_interrupt = false,
            .handle_terminate = false,
        });
        uninstall();
    }
}

test "runCleanupCallbacks with no callbacks is safe" {
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;
    runCleanupCallbacks();
}

test "max callbacks limit" {
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;

    const cb = struct {
        fn callback() void {}
    }.callback;

    for (0..16) |_| {
        try onCleanup(cb);
    }

    const result = onCleanup(cb);
    try std.testing.expectError(error.TooManyCallbacks, result);

    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;
}

test "pollSignals returns false when no signal pending" {
    signal_pending.store(false, .release);
    try std.testing.expect(!pollSignals());
}

test "pollSignals runs callbacks when signal pending" {
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;
    signal_pending.store(false, .release);

    const cb = struct {
        fn callback() void {}
    }.callback;

    try onCleanup(cb);

    signal_pending.store(true, .release);
    try std.testing.expect(pollSignals());

    try std.testing.expect(!signal_pending.load(.acquire));
    try std.testing.expect(!pollSignals());
}

test "pollSignals clears pending flag" {
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;

    signal_pending.store(true, .release);
    _ = pollSignals();
    try std.testing.expect(!signal_pending.load(.acquire));
}
