// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Text Module
//!
//! Text formatting and manipulation utilities.

const std = @import("std");
const mem = std.mem;

const sanitize = @import("sanitize");

/// Re-exports from the `sanitize` module (single source of truth) —
/// kept here because `util.text.stripControlChars` is the documented
/// public path (see SECURITY.md).
pub const writeControlFiltered = sanitize.writeControlFiltered;
pub const stripControlChars = sanitize.stripControlChars;
pub const utf8FloorIndex = sanitize.utf8FloorIndex;

/// Wrap text to a given width.
/// Ownership: returns a borrowed slice of `text` when `text.len <= width`;
/// otherwise returns an owned allocation the caller must free. Do not
/// unconditionally `free` the result — only free when wrapping occurred.
/// (Same contract as `truncate`.)
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
            // No space found, break at width; reset last_space for state symmetry
            try result.appendSlice(allocator, text[line_start..i]);
            try result.append(allocator, '\n');
            line_start = i;
            last_space = null;
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

/// Pad string to a minimum width.
/// Ownership: returns a borrowed slice of `text` when `text.len >= width`;
/// otherwise returns an owned allocation the caller must free. Only free the
/// result when padding occurred. (Same contract as `truncate`.)
pub fn padRight(text: []const u8, width: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len >= width) return text;

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, text);
    try result.appendNTimes(allocator, ' ', width - text.len);

    return result.toOwnedSlice(allocator);
}

/// Pad string on the left.
/// Ownership: returns a borrowed slice of `text` when `text.len >= width`;
/// otherwise returns an owned allocation the caller must free. Only free the
/// result when padding occurred. (Same contract as `truncate`.)
pub fn padLeft(text: []const u8, width: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len >= width) return text;

    var result: std.ArrayList(u8) = .empty;
    try result.appendNTimes(allocator, ' ', width - text.len);
    try result.appendSlice(allocator, text);

    return result.toOwnedSlice(allocator);
}

/// Center text in a given width.
/// Ownership: returns a borrowed slice of `text` when `text.len >= width`;
/// otherwise returns an owned allocation the caller must free. Only free the
/// result when centering occurred. (Same contract as `truncate`.)
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

/// Truncate text with ellipsis. Never splits a multibyte UTF-8 codepoint.
/// Returns a borrowed slice when text.len <= max_len or max_len <= 3;
/// otherwise returns an owned allocation (caller must free).
pub fn truncate(text: []const u8, max_len: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len <= max_len) return text;
    if (max_len <= 3) return text[0..utf8FloorIndex(text, max_len)];

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, text[0..utf8FloorIndex(text, max_len - 3)]);
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

// ============================================================================
// Tests
// ============================================================================

test "truncate does not split multibyte UTF-8 sequences" {
    const out = try truncate("héllo wörld", 5, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.unicode.utf8ValidateSlice(out));
}

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

test "wordWrap no-space break resets state" {
    // 10 'a's force two hard breaks (at i=4 and i=8), then " bb" wraps using
    // the space. Expected: "aaaa\naaaa\naa\nbb"
    const out = try wordWrap("aaaaaaaaaa bb", 4, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("aaaa\naaaa\naa\nbb", out);
}
