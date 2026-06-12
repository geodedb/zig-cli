// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Sanitize Module
//!
//! Terminal control-byte sanitizer — the single source of truth for the
//! control-byte filtering policy (NS-056 / CWE-150).
//!
//! This is a first-class named module (wired in `build.zig` like
//! `build_options` and `thread_pool`) rather than a plain `src/` file
//! because a Zig source file may belong to only one module: file-importing
//! a shared sanitizer from `cli`, `term`, and `util` breaks builds that
//! link those modules together (integration tests, demo, benches) with
//! "file exists in multiple modules". A named module may be imported from
//! any number of modules, which removes the need for the predicate-identical
//! mirrors that previously lived in `src/cli/help.zig` and
//! `src/term/sanitize.zig`.
//!
//! Import as `@import("sanitize")` — never by file path.

const std = @import("std");

/// Returns true for bytes that must be stripped to protect terminal state:
/// C0 controls (0x00–0x1F) except newline (0x0A) and tab (0x09), plus
/// DEL (0x7F). CR (0x0D) is intentionally stripped because it moves the
/// cursor to the start of the current line and can cause output to be
/// overwritten in terminals.
///
/// Exposed publicly so consumers and tests can verify the policy directly
/// (e.g. the exhaustive 0x00–0xFF policy test below).
pub inline fn isTerminalControl(c: u8) bool {
    return (c < 0x20 and c != '\n' and c != '\t') or c == 0x7f;
}

/// Write `text` to `w`, removing bytes that can alter terminal state:
/// C0 controls (0x00–0x1F) except newline (0x0A) and tab (0x09), plus
/// DEL (0x7F). CR (0x0D) is stripped because it overwrites terminal output
/// lines. Removing ESC (0x1B) neutralizes ANSI/OSC escape sequences
/// (CWE-150); the remaining printable bytes are kept.
pub fn writeControlFiltered(w: anytype, text: []const u8) !void {
    var start: usize = 0;
    for (text, 0..) |c, idx| {
        if (isTerminalControl(c)) {
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
        if (isTerminalControl(c)) {
            if (idx > start) try result.appendSlice(allocator, text[start..idx]);
            start = idx + 1;
        }
    }
    if (start < text.len) try result.appendSlice(allocator, text[start..]);
    return result.toOwnedSlice(allocator);
}

/// Largest index <= max_len that does not split a UTF-8 sequence (NS-062).
/// Backs off over continuation bytes (0b10xxxxxx). Invalid UTF-8 input
/// degrades gracefully (worst case backs off up to 3 bytes).
pub fn utf8FloorIndex(text: []const u8, max_len: usize) usize {
    if (max_len >= text.len) return text.len;
    var idx = max_len;
    while (idx > 0 and (text[idx] & 0xC0) == 0x80) idx -= 1;
    return idx;
}

// ============================================================================
// Tests
// ============================================================================

test "sanitize: predicate matches control-byte policy exhaustively" {
    // Policy: strip < 0x20 except \n and \t; strip 0x7f; keep everything else.
    var c: u16 = 0;
    while (c <= 0xff) : (c += 1) {
        const b: u8 = @intCast(c);
        const expected = (b < 0x20 and b != '\n' and b != '\t') or b == 0x7f;
        try std.testing.expectEqual(expected, isTerminalControl(b));
    }
}

test "writeControlFiltered strips ESC and C0 controls, keeps \\n and \\t" {
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "a\x1b[2Jb\x07c\nd\te\x7ff\rg");
    try std.testing.expectEqualStrings("a[2Jbc\nd\tefg", w.buffered());
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

test "writeControlFiltered empty input" {
    var buf: [16]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "");
    try std.testing.expectEqualStrings("", w.buffered());
}

test "stripControlChars empty input" {
    const out = try stripControlChars("", std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "writeControlFiltered all-control input" {
    var buf: [16]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "\x01\x02\x03");
    try std.testing.expectEqualStrings("", w.buffered());
}

test "stripControlChars all-control input" {
    const out = try stripControlChars("\x01\x02\x03", std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "utf8FloorIndex backs off continuation bytes" {
    try std.testing.expectEqual(@as(usize, 2), utf8FloorIndex("ab\xc3\xa9", 3)); // é split → back to 2
    try std.testing.expectEqual(@as(usize, 4), utf8FloorIndex("ab\xc3\xa9", 4)); // exact boundary ok
    try std.testing.expectEqual(@as(usize, 3), utf8FloorIndex("abc", 3));
    try std.testing.expectEqual(@as(usize, 0), utf8FloorIndex("\xc3\xa9", 1));
}

test "utf8FloorIndex never splits a 4-byte emoji sequence" {
    // "a" + U+1F600 (😀, 4 bytes: F0 9F 98 80) = 5 bytes total.
    const s = "a\xf0\x9f\x98\x80";
    try std.testing.expectEqual(@as(usize, 1), utf8FloorIndex(s, 2)); // mid-emoji → back to 1
    try std.testing.expectEqual(@as(usize, 1), utf8FloorIndex(s, 3)); // mid-emoji → back to 1
    try std.testing.expectEqual(@as(usize, 1), utf8FloorIndex(s, 4)); // mid-emoji → back to 1
    try std.testing.expectEqual(@as(usize, 5), utf8FloorIndex(s, 5)); // exact boundary ok
    // Every floor index must land on a valid UTF-8 boundary.
    var max: usize = 0;
    while (max <= s.len) : (max += 1) {
        const idx = utf8FloorIndex(s, max);
        try std.testing.expect(std.unicode.utf8ValidateSlice(s[0..idx]));
    }
}
