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
