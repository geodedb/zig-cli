// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Environment Variable Helpers
//!
//! Cross-platform, non-allocating environment variable access.
//! Used by tty.zig, color.zig, and pager.zig to avoid direct
//! std.posix.getenv calls (which fail to compile on Windows).

const std = @import("std");
const builtin = @import("builtin");

/// Check if an environment variable is set (cross-platform).
/// For boolean/existence checks only -- does not return the value.
/// On Windows, uses a stack-based allocator to avoid the 4 KB minimum
/// allocation overhead of page_allocator.
pub fn envVarExists(name: []const u8) bool {
    if (comptime builtin.os.tag == .windows) {
        var buf: [256]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        _ = std.process.getEnvVarOwned(fba.allocator(), name) catch return false;
        return true;
    }
    return std.posix.getenv(name) != null;
}

/// Get an environment variable value (cross-platform, non-allocating on POSIX).
/// On Windows, returns null since most POSIX-specific env vars (TERM, etc.)
/// are not meaningful there.
pub fn getEnvValue(comptime name: []const u8) ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return std.posix.getenv(name);
}

/// Get an environment variable value by runtime name (cross-platform, non-allocating on POSIX).
/// On Windows, returns null.
pub fn getEnvValueRuntime(name: []const u8) ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return std.posix.getenv(name);
}

// ============================================================================
// Tests
// ============================================================================

test "envVarExists returns bool" {
    // PATH is set on all POSIX systems
    if (comptime builtin.os.tag != .windows) {
        try std.testing.expect(envVarExists("PATH"));
    }
    try std.testing.expect(!envVarExists("ZIG_CLI_TEST_NONEXISTENT_VAR_12345"));
}

test "getEnvValue returns value or null" {
    if (comptime builtin.os.tag != .windows) {
        // TERM is usually set in test environments
        // but may not be, so just check it doesn't crash
        _ = getEnvValue("TERM");
    }
}
