// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Text Module
//!
//! Text formatting and manipulation utilities.

const std = @import("std");
const mem = std.mem;

/// Wrap text to a given width
pub fn wordWrap(text: []const u8, width: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len <= width) return text;

    var result: std.ArrayList(u8) = .empty;
    result.ensureTotalCapacity(allocator, text.len) catch {};
    var line_start: usize = 0;
    var last_space: ?usize = null;

    for (text, 0..) |c, i| {
        if (c == ' ') {
            last_space = i;
        }

        if (i - line_start >= width) {
            if (last_space) |space| {
                if (space > line_start) {
                    try result.appendSlice(allocator, text[line_start..space]);
                    try result.append(allocator, '\n');
                    line_start = space + 1;
                    last_space = null;
                    continue;
                }
            }
            // No space found, break at width
            try result.appendSlice(allocator, text[line_start..i]);
            try result.append(allocator, '\n');
            line_start = i;
        }
    }

    // Append remaining text
    if (line_start < text.len) {
        try result.appendSlice(allocator, text[line_start..]);
    }

    return result.toOwnedSlice(allocator);
}

/// Indent text by a given number of spaces
pub fn indent(text: []const u8, spaces: usize, allocator: std.mem.Allocator) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    var lines = mem.splitScalar(u8, text, '\n');

    var first = true;
    while (lines.next()) |line| {
        if (!first) try result.append(allocator, '\n');
        first = false;

        try result.appendNTimes(allocator, ' ', spaces);
        try result.appendSlice(allocator, line);
    }

    return result.toOwnedSlice(allocator);
}

/// Pad string to a minimum width
pub fn padRight(text: []const u8, width: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len >= width) return text;

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, text);
    try result.appendNTimes(allocator, ' ', width - text.len);

    return result.toOwnedSlice(allocator);
}

/// Pad string on the left
pub fn padLeft(text: []const u8, width: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len >= width) return text;

    var result: std.ArrayList(u8) = .empty;
    try result.appendNTimes(allocator, ' ', width - text.len);
    try result.appendSlice(allocator, text);

    return result.toOwnedSlice(allocator);
}

/// Center text in a given width
pub fn center(text: []const u8, width: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len >= width) return text;

    var result: std.ArrayList(u8) = .empty;
    const left_pad = (width - text.len) / 2;
    const right_pad = width - text.len - left_pad;

    try result.appendNTimes(allocator, ' ', left_pad);
    try result.appendSlice(allocator, text);
    try result.appendNTimes(allocator, ' ', right_pad);

    return result.toOwnedSlice(allocator);
}

/// Truncate text with ellipsis
pub fn truncate(text: []const u8, max_len: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len <= max_len) return text;
    if (max_len <= 3) return text[0..max_len];

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, text[0 .. max_len - 3]);
    try result.appendSlice(allocator, "...");

    return result.toOwnedSlice(allocator);
}

/// Convert to uppercase
pub fn toUpper(text: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var result = try allocator.alloc(u8, text.len);
    for (text, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// Convert to lowercase
pub fn toLower(text: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var result = try allocator.alloc(u8, text.len);
    for (text, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

/// Split on any whitespace
pub fn splitWhitespace(text: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    var words: std.ArrayList([]const u8) = .empty;
    var start: ?usize = null;

    for (text, 0..) |c, i| {
        if (std.ascii.isWhitespace(c)) {
            if (start) |s| {
                try words.append(allocator, text[s..i]);
                start = null;
            }
        } else {
            if (start == null) {
                start = i;
            }
        }
    }

    // Handle last word
    if (start) |s| {
        try words.append(allocator, text[s..]);
    }

    return words.toOwnedSlice(allocator);
}

/// Write `text` to `w`, removing bytes that can alter terminal state:
/// C0 controls (0x00-0x08, 0x0B-0x1F), DEL (0x7F). Newline (0x0A) and
/// tab (0x09) are preserved. Removing ESC (0x1B) neutralizes ANSI/OSC
/// escape sequences (CWE-150); the remaining printable bytes are kept.
pub fn writeControlFiltered(w: anytype, text: []const u8) !void {
    var start: usize = 0;
    for (text, 0..) |c, idx| {
        const is_control = (c < 0x20 and c != '\n' and c != '\t') or c == 0x7f;
        if (is_control) {
            if (idx > start) try w.writeAll(text[start..idx]);
            start = idx + 1;
        }
    }
    if (start < text.len) try w.writeAll(text[start..]);
}

/// Allocating variant of `writeControlFiltered`. Caller owns the result.
pub fn stripControlChars(text: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    var start: usize = 0;
    for (text, 0..) |c, idx| {
        const is_control = (c < 0x20 and c != '\n' and c != '\t') or c == 0x7f;
        if (is_control) {
            if (idx > start) try result.appendSlice(allocator, text[start..idx]);
            start = idx + 1;
        }
    }
    if (start < text.len) try result.appendSlice(allocator, text[start..]);
    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "padRight" {
    const padded = try padRight("hello", 10, std.testing.allocator);
    defer std.testing.allocator.free(padded);

    try std.testing.expectEqual(@as(usize, 10), padded.len);
    try std.testing.expect(mem.startsWith(u8, padded, "hello"));
}

test "truncate" {
    const truncated = try truncate("hello world", 8, std.testing.allocator);
    defer std.testing.allocator.free(truncated);

    try std.testing.expectEqualStrings("hello...", truncated);
}

test "toUpper" {
    const upper = try toUpper("hello", std.testing.allocator);
    defer std.testing.allocator.free(upper);

    try std.testing.expectEqualStrings("HELLO", upper);
}

test "writeControlFiltered strips ESC and C0 controls, keeps \\n and \\t" {
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "a\x1b[2Jb\x07c\nd\te\x7ff");
    try std.testing.expectEqualStrings("a[2Jbc\nd\tef", w.buffered());
}

test "writeControlFiltered passes plain text through unchanged" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "hello world");
    try std.testing.expectEqualStrings("hello world", w.buffered());
}

test "stripControlChars allocating variant" {
    const out = try stripControlChars("x\x1b]0;evil\x07y", std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("x]0;evily", out);
}
