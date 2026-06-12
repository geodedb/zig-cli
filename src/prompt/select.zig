// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Selection Prompts
//!
//! Single-select and multi-select list prompts, split out of prompt.zig
//! (the module root re-exports `select` and `multiSelect`, so the public
//! API is unchanged). Shares the line-reading helpers and `PromptError`
//! with prompt.zig.

const std = @import("std");

const prompt = @import("../prompt.zig");
const PromptError = prompt.PromptError;
const globalIo = prompt.globalIo;
const readLineInto = prompt.readLineInto;

/// Select one option from a list
pub fn select(message: []const u8, options: []const []const u8) PromptError!usize {
    const io = globalIo();
    const stdin_file = std.Io.File.stdin();
    const stdout_file = std.Io.File.stdout();

    // Check if interactive
    const is_tty = stdin_file.isTty(io) catch false;
    if (!is_tty) {
        return PromptError.NotInteractive;
    }

    var rbuf: [256]u8 = undefined;
    var reader_state = stdin_file.reader(io, &rbuf);

    var wbuf: [4096]u8 = undefined;
    var writer_state = stdout_file.writer(io, &wbuf);
    defer writer_state.interface.flush() catch {};

    return selectInternal(&reader_state.interface, &writer_state.interface, message, options);
}

/// Internal select implementation that accepts std.Io reader/writer for testability.
fn selectInternal(reader: *std.Io.Reader, writer: *std.Io.Writer, message: []const u8, options: []const []const u8) PromptError!usize {
    if (options.len == 0) {
        return PromptError.InvalidInput;
    }

    while (true) {
        // Print prompt and options
        writer.print("{s}\n", .{message}) catch return PromptError.ReadError;
        for (options, 0..) |opt, i| {
            writer.print("  {d}. {s}\n", .{ i + 1, opt }) catch return PromptError.ReadError;
        }
        writer.print("Enter choice [1-{d}]: ", .{options.len}) catch return PromptError.ReadError;
        writer.flush() catch return PromptError.ReadError;

        // Read response
        var buffer: [64]u8 = undefined;
        const line_opt = try readLineInto(reader, &buffer);
        if (line_opt == null) {
            return PromptError.Cancelled;
        }
        const line = line_opt.?;

        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Parse number
        const choice = std.fmt.parseInt(usize, trimmed, 10) catch {
            writer.print("Please enter a number between 1 and {d}.\n", .{options.len}) catch {};
            writer.flush() catch {};
            continue;
        };

        if (choice >= 1 and choice <= options.len) {
            return choice - 1;
        }

        writer.print("Please enter a number between 1 and {d}.\n", .{options.len}) catch {};
        writer.flush() catch {};
    }
}

/// Select multiple options from a list
pub fn multiSelect(message: []const u8, options: []const []const u8, allocator: std.mem.Allocator) PromptError![]usize {
    const io = globalIo();
    const stdin_file = std.Io.File.stdin();
    const stdout_file = std.Io.File.stdout();

    // Check if interactive
    const is_tty = stdin_file.isTty(io) catch false;
    if (!is_tty) {
        return PromptError.NotInteractive;
    }

    var rbuf: [1024]u8 = undefined;
    var reader_state = stdin_file.reader(io, &rbuf);

    var wbuf: [4096]u8 = undefined;
    var writer_state = stdout_file.writer(io, &wbuf);
    defer writer_state.interface.flush() catch {};

    return multiSelectInternal(&reader_state.interface, &writer_state.interface, message, options, allocator);
}

/// Internal multiSelect implementation that accepts std.Io reader/writer for testability.
fn multiSelectInternal(reader: *std.Io.Reader, writer: *std.Io.Writer, message: []const u8, options: []const []const u8, allocator: std.mem.Allocator) PromptError![]usize {
    if (options.len == 0) {
        return PromptError.InvalidInput;
    }

    while (true) {
        // Print prompt and options
        writer.print("{s}\n", .{message}) catch return PromptError.ReadError;
        for (options, 0..) |opt, i| {
            writer.print("  {d}. {s}\n", .{ i + 1, opt }) catch return PromptError.ReadError;
        }
        writer.print("Enter choices (comma-separated, e.g., 1,3,4): ", .{}) catch return PromptError.ReadError;
        writer.flush() catch return PromptError.ReadError;

        // Read response
        var buffer: [256]u8 = undefined;
        const line_opt = try readLineInto(reader, &buffer);
        if (line_opt == null) {
            return PromptError.Cancelled;
        }
        const line = line_opt.?;

        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Parse selections
        var selections: std.ArrayList(usize) = .empty;
        errdefer selections.deinit(allocator);

        var valid = true;
        var iter = std.mem.splitSequence(u8, trimmed, ",");
        while (iter.next()) |part| {
            const num_str = std.mem.trim(u8, part, " \t");
            if (num_str.len == 0) continue;

            const choice = std.fmt.parseInt(usize, num_str, 10) catch {
                valid = false;
                break;
            };

            if (choice < 1 or choice > options.len) {
                valid = false;
                break;
            }

            selections.append(allocator, choice - 1) catch return PromptError.OutOfMemory;
        }

        if (!valid or selections.items.len == 0) {
            selections.deinit(allocator);
            writer.print("Please enter valid numbers between 1 and {d}.\n", .{options.len}) catch {};
            writer.flush() catch {};
            continue;
        }

        return selections.toOwnedSlice(allocator) catch return PromptError.OutOfMemory;
    }
}

// ============================================================================
// Tests
// ============================================================================

// --- selectInternal tests ---

test "select: valid 1-based index" {
    var reader = std.Io.Reader.fixed("2\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try selectInternal(&reader, &writer, "Pick:", options);
    try std.testing.expectEqual(@as(usize, 1), result); // 0-based index
}

test "select: out-of-range retries then accepts" {
    // "5" is out of range, then "1" is valid
    var reader = std.Io.Reader.fixed("5\n1\n");
    var writer_buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try selectInternal(&reader, &writer, "Pick:", options);
    try std.testing.expectEqual(@as(usize, 0), result);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Please enter a number between 1 and 3.") != null);
}

test "select: non-numeric retries then accepts" {
    // "abc" is non-numeric, then "3" is valid
    var reader = std.Io.Reader.fixed("abc\n3\n");
    var writer_buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try selectInternal(&reader, &writer, "Pick:", options);
    try std.testing.expectEqual(@as(usize, 2), result);
}

test "select: empty options returns InvalidInput" {
    var reader = std.Io.Reader.fixed("1\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options: []const []const u8 = &.{};
    const result = selectInternal(&reader, &writer, "Pick:", options);
    try std.testing.expectError(PromptError.InvalidInput, result);
}

test "select: EOF returns Cancelled" {
    var reader = std.Io.Reader.fixed("");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta" };
    const result = selectInternal(&reader, &writer, "Pick:", options);
    try std.testing.expectError(PromptError.Cancelled, result);
}

// --- multiSelectInternal tests ---

test "multiSelect: comma-separated parsing" {
    var reader = std.Io.Reader.fixed("1,3\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try multiSelectInternal(&reader, &writer, "Pick:", options, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(usize, 0), result[0]); // 1 -> 0-based
    try std.testing.expectEqual(@as(usize, 2), result[1]); // 3 -> 2-based
}

test "multiSelect: out-of-range retries then accepts" {
    // "1,5" has out-of-range 5, retries; then "2" is valid
    var reader = std.Io.Reader.fixed("1,5\n2\n");
    var writer_buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try multiSelectInternal(&reader, &writer, "Pick:", options, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 1), result[0]);
}

test "multiSelect: single selection" {
    var reader = std.Io.Reader.fixed("2\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try multiSelectInternal(&reader, &writer, "Pick:", options, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 1), result[0]);
}

test "multiSelect: empty options returns InvalidInput" {
    var reader = std.Io.Reader.fixed("1\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options: []const []const u8 = &.{};
    const result = multiSelectInternal(&reader, &writer, "Pick:", options, std.testing.allocator);
    try std.testing.expectError(PromptError.InvalidInput, result);
}

test "multiSelect: EOF returns Cancelled" {
    var reader = std.Io.Reader.fixed("");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta" };
    const result = multiSelectInternal(&reader, &writer, "Pick:", options, std.testing.allocator);
    try std.testing.expectError(PromptError.Cancelled, result);
}
