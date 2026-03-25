// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Filesystem Module
//!
//! Filesystem utilities with security-conscious design.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;

/// File operation errors
pub const FsError = error{
    NotFound,
    PermissionDenied,
    IoError,
    PathTooLong,
    InvalidPath,
};

/// Check if a path exists
pub fn exists(path: []const u8) bool {
    fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if path is a directory
pub fn isDirectory(path: []const u8) bool {
    const stat = fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Check if path is a regular file
pub fn isFile(path: []const u8) bool {
    const stat = fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Read file contents with size limit
pub fn readFile(path: []const u8, allocator: std.mem.Allocator, max_size: usize) FsError![]const u8 {
    const file = fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => FsError.NotFound,
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
    defer file.close();

    return file.readToEndAlloc(allocator, max_size) catch FsError.IoError;
}

/// Write file atomically (write to temp with random suffix, then rename).
///
/// Security: temp file is created with mode 0o600 (owner read/write only).
/// Data integrity: fsync is called before close to ensure data reaches disk
/// before the rename makes it visible.
pub fn writeFileAtomic(path: []const u8, content: []const u8) FsError!void {
    const dir = fs.cwd();

    // Create temp file with random suffix to avoid collisions
    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_path = std.fmt.bufPrint(&tmp_buf, "{s}.{x:0>8}", .{ path, std.crypto.random.int(u32) }) catch return FsError.PathTooLong;

    // Write to temp file with restrictive permissions (0o600)
    const temp_file = dir.createFile(temp_path, .{ .mode = 0o600 }) catch |err| {
        return switch (err) {
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
    errdefer {
        // Clean up temp file on failure
        temp_file.close();
        dir.deleteFile(temp_path) catch {};
    }

    temp_file.writeAll(content) catch return FsError.IoError;

    // Ensure data is flushed to disk before rename
    temp_file.sync() catch return FsError.IoError;
    temp_file.close();

    // Rename temp to target; clean up temp on failure
    dir.rename(temp_path, path) catch {
        dir.deleteFile(temp_path) catch {};
        return FsError.IoError;
    };
}

/// Ensure a directory exists, creating it if necessary
pub fn ensureDir(path: []const u8) FsError!void {
    fs.cwd().makePath(path) catch |err| {
        return switch (err) {
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
}

/// Get absolute path
pub fn absolutePath(relative: []const u8, allocator: std.mem.Allocator) FsError![]const u8 {
    return fs.cwd().realpathAlloc(allocator, relative) catch FsError.NotFound;
}

/// Redact path for error messages (hide sensitive parts)
pub fn redactPath(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Check for sensitive paths
    const sensitive_patterns: []const []const u8 = &.{
        "/etc/shadow",
        "/etc/passwd",
        ".ssh/",
        ".gnupg/",
        ".aws/",
        "credentials",
        "secrets",
        ".env",
    };

    for (sensitive_patterns) |pattern| {
        if (mem.indexOf(u8, path, pattern) != null) {
            return try std.fmt.allocPrint(allocator, "[REDACTED]/{s}", .{pattern});
        }
    }

    // Return an owned copy so callers can always free the result
    return try allocator.dupe(u8, path);
}

/// Check if a path is safe to read (not in sensitive locations)
pub fn isSafePath(path: []const u8) bool {
    // Block path traversal attempts
    if (containsPathTraversal(path)) {
        return false;
    }

    const unsafe_prefixes: []const []const u8 = &.{
        "/etc/shadow",
        "/etc/sudoers",
        "/etc/passwd",
        "/etc/gshadow",
        "/proc/self/",
    };

    for (unsafe_prefixes) |prefix| {
        if (mem.startsWith(u8, path, prefix)) {
            return false;
        }
    }

    // Check for ~/.ssh/ pattern (tilde or any absolute home path containing .ssh/)
    if (mem.indexOf(u8, path, ".ssh/") != null) {
        return false;
    }

    return true;
}

/// Check if a path contains ".." traversal segments
fn containsPathTraversal(path: []const u8) bool {
    // Check for standalone ".." or "../" or "/.."
    var iter = mem.splitScalar(u8, path, '/');
    while (iter.next()) |segment| {
        if (mem.eql(u8, segment, "..")) {
            return true;
        }
    }
    return false;
}

/// Handle "-" as stdin.
/// When the caller receives `.stdin`, it should decide based on the
/// operation context whether to use stdin or stdout.
pub fn resolveStdio(path: []const u8) enum { stdin, path } {
    if (mem.eql(u8, path, "-")) {
        return .stdin;
    }
    return .path;
}

// ============================================================================
// Tests
// ============================================================================

test "exists" {
    // Current directory should exist
    try std.testing.expect(exists("."));
}

test "isDirectory" {
    try std.testing.expect(isDirectory("."));
}

test "isSafePath" {
    try std.testing.expect(isSafePath("/home/user/file.txt"));
    try std.testing.expect(!isSafePath("/etc/shadow"));
    try std.testing.expect(!isSafePath("/etc/sudoers"));
    try std.testing.expect(!isSafePath("/etc/passwd"));
    try std.testing.expect(!isSafePath("/etc/gshadow"));
    try std.testing.expect(!isSafePath("/proc/self/environ"));
    try std.testing.expect(!isSafePath("/home/user/.ssh/id_rsa"));
    try std.testing.expect(isSafePath("/home/user/documents/report.txt"));
}

test "isSafePath blocks path traversal" {
    try std.testing.expect(!isSafePath("/home/user/../etc/shadow"));
    try std.testing.expect(!isSafePath("../../etc/passwd"));
    try std.testing.expect(!isSafePath("/tmp/foo/../../etc/shadow"));
    try std.testing.expect(isSafePath("/home/user/normal/path"));
}

test "redactPath returns owned memory for both paths" {
    // Sensitive path
    const sensitive = try redactPath("/home/user/.ssh/id_rsa", std.testing.allocator);
    defer std.testing.allocator.free(sensitive);
    try std.testing.expect(std.mem.indexOf(u8, sensitive, "[REDACTED]") != null);

    // Non-sensitive path: must also be freeable
    const safe = try redactPath("/home/user/file.txt", std.testing.allocator);
    defer std.testing.allocator.free(safe);
    try std.testing.expectEqualStrings("/home/user/file.txt", safe);
}

test "resolveStdio" {
    try std.testing.expectEqual(@as(@TypeOf(resolveStdio("-")), .stdin), resolveStdio("-"));
    try std.testing.expectEqual(@as(@TypeOf(resolveStdio("file.txt")), .path), resolveStdio("file.txt"));
}
