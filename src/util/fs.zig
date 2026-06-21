// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Filesystem Module
//!
//! Filesystem utilities with security-conscious design.

const std = @import("std");
const mem = std.mem;

inline fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

inline fn cwd() std.Io.Dir {
    return std.Io.Dir.cwd();
}

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
    cwd().access(io(), path, .{}) catch return false;
    return true;
}

/// Check if path is a directory
pub fn isDirectory(path: []const u8) bool {
    const stat = cwd().statFile(io(), path, .{}) catch return false;
    return stat.kind == .directory;
}

/// Check if path is a regular file
pub fn isFile(path: []const u8) bool {
    const stat = cwd().statFile(io(), path, .{}) catch return false;
    return stat.kind == .file;
}

/// Read file contents with size limit
pub fn readFile(path: []const u8, allocator: std.mem.Allocator, max_size: usize) FsError![]const u8 {
    var file = cwd().openFile(io(), path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => FsError.NotFound,
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
    defer file.close(io());

    const sz = file.length(io()) catch return FsError.IoError;
    if (sz > max_size) return FsError.IoError;
    const buf = allocator.alloc(u8, @intCast(sz)) catch return FsError.IoError;
    errdefer allocator.free(buf);
    var reader = file.reader(io(), &.{});
    reader.interface.readSliceAll(buf) catch return FsError.IoError;
    return buf;
}

/// Write file atomically (write to temp with random suffix, then rename).
///
/// Security: temp file is created with mode 0o600 (owner read/write only).
/// Data integrity: fsync is called before close to ensure data reaches disk
/// before the rename makes it visible.
///
/// SECURITY NOTE: The temp file and rename are resolved via cwd-relative
/// paths on each call. Only target directories you control; a hostile
/// writable parent directory permits parent-dir TOCTOU swaps between
/// create and rename.
pub fn writeFileAtomic(path: []const u8, content: []const u8) FsError!void {
    const dir = cwd();

    // Create temp file with random suffix to avoid collisions
    var tmp_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var seed_bytes: [8]u8 = undefined;
    std.posix.getrandom(&seed_bytes) catch {
        // Fallback: use pointer address + path hash for uniqueness
        // fips-exempt: non-security — temp-file name uniqueness only (getrandom
        // fallback); no secret derived. Collision avoidance, not confidentiality.
        const seed_u64 = @as(u64, @intFromPtr(path.ptr)) ^ std.hash.Wyhash.hash(0, path);
        std.mem.writeInt(u64, &seed_bytes, seed_u64, .little);
    };
    // fips-exempt: non-security — random temp-file suffix to avoid collisions;
    // not a cryptographic secret.
    var prng = std.Random.DefaultPrng.init(std.mem.readInt(u64, &seed_bytes, .little));
    const temp_path = std.fmt.bufPrint(&tmp_buf, "{s}.{x:0>8}", .{ path, prng.random().int(u32) }) catch return FsError.PathTooLong;

    // Write to temp file with restrictive permissions (0o600)
    var temp_file = dir.createFile(io(), temp_path, .{ .permissions = .{ .readable = true, .writable = true, .mode = 0o600 } }) catch |err| {
        return switch (err) {
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
    errdefer {
        // Clean up temp file on failure
        temp_file.close(io());
        dir.deleteFile(io(), temp_path) catch {};
    }

    var wbuf: [4096]u8 = undefined;
    var fw = temp_file.writer(io(), &wbuf);
    fw.interface.writeAll(content) catch return FsError.IoError;
    fw.interface.flush() catch return FsError.IoError;

    // Ensure data is flushed to disk before rename
    temp_file.sync(io()) catch return FsError.IoError;
    temp_file.close(io());

    // Rename temp to target; clean up temp on failure
    dir.rename(temp_path, dir, path, io()) catch {
        dir.deleteFile(io(), temp_path) catch {};
        return FsError.IoError;
    };
}

/// Ensure a directory exists, creating it if necessary
pub fn ensureDir(path: []const u8) FsError!void {
    cwd().createDirPath(io(), path) catch |err| {
        return switch (err) {
            error.AccessDenied => FsError.PermissionDenied,
            else => FsError.IoError,
        };
    };
}

/// Get absolute path
pub fn absolutePath(relative: []const u8, allocator: std.mem.Allocator) FsError![]const u8 {
    const result = cwd().realPathFileAlloc(io(), relative, allocator) catch return FsError.NotFound;
    return result;
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

/// SECURITY NOTE: This is a best-effort DENYLIST of obviously sensitive
/// paths, NOT a security boundary. It performs no canonicalization and
/// does not resolve symlinks: `/etc//shadow`, traversal via cwd, or a
/// symlink to a sensitive file all PASS this check. Callers needing a
/// real guarantee must canonicalize (e.g. this module's `absolutePath`,
/// which wraps `Dir.realPathFileAlloc`) and validate the result against
/// an allowlisted root directory.
///
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
