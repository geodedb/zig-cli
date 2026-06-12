// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # TTY Module
//!
//! Terminal detection and capabilities.

const std = @import("std");
const builtin = @import("builtin");
const env = @import("env.zig");

/// Terminal information for stdout.
///
/// Returned by `getInfo()`. `width`/`height` default to 80×24 when stdout
/// is not a TTY or when the terminal size query fails. `color_supported` is
/// false for dumb terminals and when the NO_COLOR env var is set.
pub const TermInfo = struct {
    /// Whether stdout is a TTY
    is_tty: bool,
    /// Terminal width (columns)
    width: u16,
    /// Terminal height (rows)
    height: u16,
    /// Terminal type (from TERM env)
    term_type: ?[]const u8,
    /// Whether color is supported
    color_supported: bool,
    /// Whether unicode is supported
    unicode_supported: bool,
};

inline fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Get terminal information for stdout.
///
/// Always succeeds; falls back to 80×24 when stdout is not a TTY or when
/// the terminal size query fails. `color_supported` is false for dumb
/// terminals and when NO_COLOR is set. Never returns null.
pub fn getInfo() TermInfo {
    const stdout = std.Io.File.stdout();
    const is_tty = stdout.isTty(io()) catch false;

    var width: u16 = 80;
    var height: u16 = 24;

    if (is_tty) {
        if (getTermSize()) |size| {
            width = size.cols;
            height = size.rows;
        }
    }

    const term_type = env.getEnvValue("TERM");
    const color_supported = is_tty and !isDumb(term_type) and !hasNoColor();

    return .{
        .is_tty = is_tty,
        .width = width,
        .height = height,
        .term_type = term_type,
        .color_supported = color_supported,
        .unicode_supported = is_tty and !isDumb(term_type),
    };
}

/// Terminal dimensions in columns and rows.
///
/// Returned by `getTermSize()`. Returns `null` when the terminal size
/// cannot be queried (non-TTY stdout, unsupported platform, ioctl failure).
pub const TermSize = struct {
    cols: u16,
    rows: u16,
};

/// Get the current terminal size.
///
/// Returns `null` when stdout is not a TTY, when the ioctl/API call fails,
/// or when the reported dimensions are zero or negative (invalid console state).
pub fn getTermSize() ?TermSize {
    if (builtin.os.tag == .windows) {
        return getTermSizeWindows();
    } else {
        return getTermSizePosix();
    }
}

fn getTermSizePosix() ?TermSize {
    var ws: std.posix.winsize = undefined;
    if (std.posix.system.ioctl(std.Io.File.stdout().handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0) {
        return .{
            .cols = ws.col,
            .rows = ws.row,
        };
    }
    return null;
}

// Minimal extern bindings for kernel32 that Zig 0.16 no longer re-exports
// (SMALL_RECT, GetModuleHandleW, and the console info struct). Declared
// locally so the Windows path keeps compiling without relying on stdlib
// shims that come and go.
const WIN_SMALL_RECT = extern struct {
    Left: i16,
    Top: i16,
    Right: i16,
    Bottom: i16,
};

extern "kernel32" fn GetConsoleScreenBufferInfo(
    hConsoleOutput: std.os.windows.HANDLE,
    lpConsoleScreenBufferInfo: *anyopaque,
) callconv(.winapi) std.os.windows.BOOL;

extern "kernel32" fn GetStdHandle(
    nStdHandle: std.os.windows.DWORD,
) callconv(.winapi) std.os.windows.HANDLE;

fn getTermSizeWindows() ?TermSize {
    if (builtin.os.tag != .windows) {
        return null;
    }

    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: windows.COORD,
        dwCursorPosition: windows.COORD,
        wAttributes: windows.WORD,
        srWindow: WIN_SMALL_RECT,
        dwMaximumWindowSize: windows.COORD,
    };

    var csbi: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    _ = kernel32;
    // STD_OUTPUT_HANDLE = (DWORD)-11 (Win32 header constant).
    const STD_OUTPUT_HANDLE: windows.DWORD = @bitCast(@as(i32, -11));
    const stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);

    if (stdout_handle == windows.INVALID_HANDLE_VALUE) {
        return null;
    }

    if (GetConsoleScreenBufferInfo(stdout_handle, &csbi) == .FALSE) {
        return null;
    }

    // Calculate visible window size as i32 to avoid intCast panic on
    // negative or overflowing values from invalid console state.
    const width_i32 = @as(i32, csbi.srWindow.Right) - @as(i32, csbi.srWindow.Left) + 1;
    const height_i32 = @as(i32, csbi.srWindow.Bottom) - @as(i32, csbi.srWindow.Top) + 1;

    if (width_i32 <= 0 or height_i32 <= 0) {
        return null;
    }

    return .{
        .cols = @intCast(width_i32),
        .rows = @intCast(height_i32),
    };
}

/// Check if TERM is dumb
fn isDumb(term: ?[]const u8) bool {
    if (term) |t| {
        return std.mem.eql(u8, t, "dumb");
    }
    return false;
}

/// Check if NO_COLOR is set
fn hasNoColor() bool {
    return env.envVarExists("NO_COLOR");
}

/// Returns true when stdout is connected to a terminal, false otherwise
/// (piped, redirected, or when the check itself fails).
pub fn isStdoutTty() bool {
    return std.Io.File.stdout().isTty(io()) catch false;
}

/// Returns true when stderr is connected to a terminal, false otherwise
/// (piped, redirected, or when the check itself fails).
pub fn isStderrTty() bool {
    return std.Io.File.stderr().isTty(io()) catch false;
}

/// Returns true when stdin is connected to a terminal, false otherwise
/// (piped, redirected, or when the check itself fails).
pub fn isStdinTty() bool {
    return std.Io.File.stdin().isTty(io()) catch false;
}

// ============================================================================
// Tests
// ============================================================================

test "getInfo returns valid struct" {
    const info = getInfo();
    try std.testing.expect(info.width > 0);
    try std.testing.expect(info.height > 0);
}

test "isDumb detection" {
    try std.testing.expect(isDumb("dumb"));
    try std.testing.expect(!isDumb("xterm-256color"));
    try std.testing.expect(!isDumb(null));
}
