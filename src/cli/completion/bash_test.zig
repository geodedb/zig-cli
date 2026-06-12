// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Public-API tests for the bash completion generator: the escaper family
//! (escapeBashDoubleQuote, escapeBashCasePattern, escapeBashSingleQuote)
//! and the N-03/N-04 hardening of the registration line and header
//! comments. Tests for the private sanitizeBashIdentifier helper live in
//! bash.zig itself.

const std = @import("std");

const bash = @import("bash.zig");
const generate = bash.generate;
const escapeBashDoubleQuote = bash.escapeBashDoubleQuote;
const escapeBashCasePattern = bash.escapeBashCasePattern;
const escapeBashSingleQuote = bash.escapeBashSingleQuote;

const command = @import("../command.zig");
const Command = command.Command;

// ============================================================================
// escapeBashDoubleQuote
// ============================================================================

test "bash: escapeBashDoubleQuote no special chars" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "hello");
    // Fast path: no allocation, returns same pointer
    try std.testing.expectEqualStrings("hello", result);
}

test "bash: escapeBashDoubleQuote with dollar sign" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "val$ue");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("val\\$ue", result);
}

test "bash: escapeBashDoubleQuote with backtick" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "run`cmd`");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("run\\`cmd\\`", result);
}

test "bash: escapeBashDoubleQuote with double quote" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "say\"hi\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("say\\\"hi\\\"", result);
}

test "bash: escapeBashDoubleQuote with backslash" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "path\\to");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("path\\\\to", result);
}

test "bash: escapeBashDoubleQuote with bang" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "hello!");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello\\!", result);
}

test "bash: escapeBashDoubleQuote empty string" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "");
    try std.testing.expectEqualStrings("", result);
}

test "bash: escapeBashDoubleQuote strips NUL bytes" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "hel\x00lo");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "bash: escapeBashDoubleQuote strips newlines" {
    const result = try escapeBashDoubleQuote(std.testing.allocator, "line1\nline2\rline3");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("line1line2line3", result);
}

// ============================================================================
// escapeBashCasePattern
// ============================================================================

test "bash: escapeBashCasePattern no special chars" {
    const result = try escapeBashCasePattern(std.testing.allocator, "hello");
    try std.testing.expectEqualStrings("hello", result);
}

test "bash: escapeBashCasePattern with glob star" {
    const result = try escapeBashCasePattern(std.testing.allocator, "file*");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("file\\*", result);
}

test "bash: escapeBashCasePattern with question mark" {
    const result = try escapeBashCasePattern(std.testing.allocator, "file?name");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("file\\?name", result);
}

test "bash: escapeBashCasePattern with brackets" {
    const result = try escapeBashCasePattern(std.testing.allocator, "[abc]");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\\[abc\\]", result);
}

test "bash: escapeBashCasePattern empty string" {
    const result = try escapeBashCasePattern(std.testing.allocator, "");
    try std.testing.expectEqualStrings("", result);
}

// ============================================================================
// escapeBashSingleQuote (N-03)
// ============================================================================

test "bash: escapeBashSingleQuote no special chars" {
    const result = try escapeBashSingleQuote(std.testing.allocator, "my-app");
    // Fast path: no allocation, returns same pointer
    try std.testing.expectEqualStrings("my-app", result);
}

test "bash: escapeBashSingleQuote with single quote" {
    const result = try escapeBashSingleQuote(std.testing.allocator, "a'b");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("a'\\''b", result);
}

test "bash: escapeBashSingleQuote strips NUL and newlines" {
    const result = try escapeBashSingleQuote(std.testing.allocator, "a\x00b\nc\rd");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("abcd", result);
}

// ============================================================================
// Registration line hardening (N-03 / CWE-78)
// ============================================================================

test "bash: registration target with single quote is escaped (N-03)" {
    const cmd = Command{
        .name = "a'b",
        .summary = "Hostile name",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // Function id is sanitized; the command word is single-quoted with the
    // embedded quote escaped bash-style ('\'').
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _a_b 'a'\\''b'") != null);
    // The raw breakout form must not appear.
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _a_b a'b") == null);
}

test "bash: registration target with metacharacters stays inside quotes (N-03)" {
    const cmd = Command{
        .name = "a b;c",
        .summary = "Hostile name",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // No bare `;` or unquoted space in the complete line: the whole name is
    // one single-quoted word.
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _a_b_c 'a b;c'") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F _a_b_c a b;c") == null);
}

// ============================================================================
// Header comment hardening (N-04 / CWE-116)
// ============================================================================

test "bash: header comment strips newline from command name (N-04)" {
    const cmd = Command{
        .name = "a\necho injected",
        .summary = "Hostile name",
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    // The name must not be able to terminate the `#` comment and inject a
    // live script line.
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |line| {
        try std.testing.expect(!std.mem.startsWith(u8, line, "echo injected"));
    }
    try std.testing.expect(std.mem.indexOf(u8, script, "# Bash completion for aecho injected") != null);
}

// ============================================================================
// Short-flag byte guard (R2-02 / CWE-150)
// ============================================================================

test "bash: non-printable short flag byte is not emitted (R2-02)" {
    const cmd = Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            command.FlagSpec{
                .name = "evil",
                .short = 0x1b, // ESC — a non-printable byte
                .help = "should not emit ESC",
                .ftype = .string,
            },
        },
    };

    const script = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(script);

    try std.testing.expect(std.mem.indexOfScalar(u8, script, 0x1b) == null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--evil") != null);
}

test "bash: hostile subcommand name cannot break out of the commands list" {
    const sub = Command{
        .name = "a\"; echo PWNED #",
        .summary = "Hostile",
    };
    const cmd = Command{
        .name = "app",
        .summary = "App",
        .subcommands = &.{&sub},
    };

    const out = try bash.generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(out);

    // The raw breakout form must not appear: the double quote must be escaped
    // so the candidate list cannot terminate early and execute the payload.
    try std.testing.expect(std.mem.indexOf(u8, out, "local commands=\"a\"; echo PWNED") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "local commands=\"a\\\";") != null);
}
