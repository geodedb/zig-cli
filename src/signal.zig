// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Signal Handling Module
//!
//! Cross-platform signal handling for graceful shutdown and interrupt handling.
//!
//! ## Usage
//!
//! ```zig
//! const signal = @import("cli").signal;
//!
//! pub fn main() !void {
//!     // Install default handlers
//!     signal.install(.{}) catch {};
//!
//!     while (!signal.wasInterrupted()) {
//!         // Do work...
//!     }
//!
//!     // Or register a custom cleanup handler
//!     signal.onCleanup(myCleanupFn);
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
/// **IMPORTANT: Async-signal-safety requirement.**
/// Cleanup callbacks are invoked directly from the POSIX signal handler
/// (or the Windows console control handler). Callbacks MUST be
/// async-signal-safe: they may only call functions that are safe to use
/// inside a signal handler. In particular, callbacks MUST NOT:
///
/// - Allocate or free memory (no `allocator.alloc`, `allocator.free`)
/// - Acquire mutexes or other locks (risk of deadlock)
/// - Perform I/O through buffered streams (e.g., `std.debug.print`)
/// - Call any function not on the POSIX async-signal-safe list
///
/// Safe operations include: setting atomic flags, writing to a
/// pre-opened file descriptor via `std.posix.write`, and calling
/// `std.posix.exit`.
pub const CleanupFn = *const fn () void;

/// Global state for signal handling
var interrupted: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var terminated: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var cleanup_callbacks: [16]?CleanupFn = .{null} ** 16;
var callback_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var mutex: std.Thread.Mutex = .{};
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

/// Register a cleanup callback to be called on signal.
/// Returns error if max callbacks reached (limit: 16).
///
/// **WARNING:** The callback MUST be async-signal-safe. See `CleanupFn`
/// documentation for the full list of restrictions. Violating these
/// constraints leads to undefined behavior (deadlocks, corruption).
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

fn posixSignalHandler(sig: c_int) callconv(.c) void {
    switch (sig) {
        std.posix.SIG.INT => {
            interrupted.store(true, .release);
        },
        std.posix.SIG.TERM => {
            terminated.store(true, .release);
        },
        std.posix.SIG.HUP, std.posix.SIG.QUIT => {
            terminated.store(true, .release);
        },
        else => {},
    }

    // Run cleanup callbacks
    runCleanupCallbacks();
}

// ============================================================================
// Windows Implementation
// ============================================================================

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

    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    // SetConsoleCtrlHandler
    const k32_handle = kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("kernel32.dll")) orelse return error.FunctionNotFound;
    const SetConsoleCtrlHandler = @as(*const fn (
        ?*const fn (windows.DWORD) callconv(.winapi) windows.BOOL,
        windows.BOOL,
    ) callconv(.winapi) windows.BOOL, @ptrCast(@alignCast(
        kernel32.GetProcAddress(
            k32_handle,
            "SetConsoleCtrlHandler",
        ) orelse return error.FunctionNotFound,
    )));

    if (SetConsoleCtrlHandler(windowsCtrlHandler, 1) == 0) {
        return error.SetHandlerFailed;
    }
}

fn uninstallWindows() void {
    if (builtin.os.tag != .windows) {
        return;
    }

    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    const k32_handle = kernel32.GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("kernel32.dll")) orelse return;
    const SetConsoleCtrlHandler = @as(*const fn (
        ?*const fn (windows.DWORD) callconv(.winapi) windows.BOOL,
        windows.BOOL,
    ) callconv(.winapi) windows.BOOL, @ptrCast(@alignCast(
        kernel32.GetProcAddress(
            k32_handle,
            "SetConsoleCtrlHandler",
        ) orelse return,
    )));

    _ = SetConsoleCtrlHandler(windowsCtrlHandler, 0);
}

fn windowsCtrlHandler(ctrl_type: std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL {
    const CTRL_C_EVENT: std.os.windows.DWORD = 0;
    const CTRL_BREAK_EVENT: std.os.windows.DWORD = 1;
    const CTRL_CLOSE_EVENT: std.os.windows.DWORD = 2;

    switch (ctrl_type) {
        CTRL_C_EVENT, CTRL_BREAK_EVENT => {
            if (!win_handle_interrupt.load(.acquire)) return 0;
            interrupted.store(true, .release);
            runCleanupCallbacks();
            return 1; // TRUE - handled
        },
        CTRL_CLOSE_EVENT => {
            if (!win_handle_terminate.load(.acquire)) return 0;
            terminated.store(true, .release);
            runCleanupCallbacks();
            return 1; // TRUE - handled
        },
        else => return 0, // FALSE - not handled
    }
}

// ============================================================================
// Shared Helpers
// ============================================================================

fn runCleanupCallbacks() void {
    // Note: Called from signal handler context, must be async-signal-safe
    // We only read the array, no locking needed
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
    // Verify the default config enables interrupt and terminate handling
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
    // Test the atomic flags used by the Windows handler.
    // These are used cross-platform for the atomic store/load pattern.
    win_handle_interrupt.store(true, .release);
    win_handle_terminate.store(false, .release);
    try std.testing.expect(win_handle_interrupt.load(.acquire));
    try std.testing.expect(!win_handle_terminate.load(.acquire));

    // Reset to defaults
    win_handle_interrupt.store(false, .release);
    win_handle_terminate.store(false, .release);
}

test "install with no-op config does not error" {
    // An empty config (no signals to handle) should succeed on all platforms
    if (comptime builtin.os.tag == .windows) {
        // On Windows, install with no signals skips registration
        try install(.{
            .handle_interrupt = false,
            .handle_terminate = false,
        });
    } else {
        // On POSIX, install with no signals is a no-op
        try install(.{
            .handle_interrupt = false,
            .handle_terminate = false,
        });
        uninstall();
    }
}

test "runCleanupCallbacks with no callbacks is safe" {
    // Reset state
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;

    // Should not panic or crash
    runCleanupCallbacks();
}

test "max callbacks limit" {
    // Reset state
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;

    const cb = struct {
        fn callback() void {}
    }.callback;

    // Fill all 16 slots
    for (0..16) |_| {
        try onCleanup(cb);
    }

    // 17th should fail
    const result = onCleanup(cb);
    try std.testing.expectError(error.TooManyCallbacks, result);

    // Reset for other tests
    callback_count.store(0, .release);
    cleanup_callbacks = .{null} ** 16;
}
