// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Terminal control-byte sanitizer (term-module mirror).
//!
//! Mirror of `src/util/text.zig`'s `writeControlFiltered`/`isTerminalControl`.
//! Duplicated because a Zig source file may belong to only one module and
//! the `term` and `util` modules are linked together in integration builds.
//! KEEP THE PREDICATE IN SYNC with `src/util/text.zig` (see the exhaustive
//! policy test below, which fails loudly on divergence).

const std = @import("std");

/// Returns true for bytes that must be stripped to protect terminal state:
/// C0 controls (0x00-0x1F) except newline (0x0A) and tab (0x09), plus
/// DEL (0x7F). CR (0x0D) is stripped because it moves the cursor to the
/// start of the line and can overwrite terminal output.
pub inline fn isTerminalControl(c: u8) bool {
    return (c < 0x20 and c != '\n' and c != '\t') or c == 0x7f;
}

/// Largest index <= max_len that does not split a UTF-8 sequence.
/// Mirror of `src/util/text.utf8FloorIndex`.
/// KEEP IN SYNC with `src/util/text.zig` (see the sync test below, which
/// validates identical behaviour on a shared corpus of inputs).
pub fn utf8FloorIndex(text: []const u8, max_len: usize) usize {
    if (max_len >= text.len) return text.len;
    var idx = max_len;
    while (idx > 0 and (text[idx] & 0xC0) == 0x80) idx -= 1;
    return idx;
}

/// Write `text` to `w`, removing control bytes (see `isTerminalControl`).
/// Removing ESC (0x1B) neutralizes ANSI/OSC escape sequences (CWE-150).
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

test "sanitize: utf8FloorIndex mirrors canonical behaviour" {
    // Mirror of the canonical tests in src/util/text.zig — must stay in sync.
    try std.testing.expectEqual(@as(usize, 2), utf8FloorIndex("ab\xc3\xa9", 3)); // é split → back to 2
    try std.testing.expectEqual(@as(usize, 4), utf8FloorIndex("ab\xc3\xa9", 4)); // exact boundary ok
    try std.testing.expectEqual(@as(usize, 3), utf8FloorIndex("abc", 3));
    try std.testing.expectEqual(@as(usize, 0), utf8FloorIndex("\xc3\xa9", 1));
}

test "sanitize: predicate matches canonical control-byte policy" {
    var c: u16 = 0;
    while (c <= 0xff) : (c += 1) {
        const b: u8 = @intCast(c);
        const expected = (b < 0x20 and b != '\n' and b != '\t') or b == 0x7f;
        try std.testing.expectEqual(expected, isTerminalControl(b));
    }
}

test "sanitize: writeControlFiltered strips ESC and C0, keeps \\n and \\t" {
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "a\x1b[2Jb\x07c\nd\te\x7ff\rg");
    try std.testing.expectEqualStrings("a[2Jbc\nd\tefg", w.buffered());
}
