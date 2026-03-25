// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Interactive Prompts Module
//!
//! Utilities for interactive CLI input with support for:
//! - Text input with validation
//! - Password input (hidden characters)
//! - Yes/No confirmation
//! - Single-select from list
//! - Multi-select from list
//!
//! ## API Note
//!
//! The `allocator` parameter position is inconsistent across functions:
//! - `input(message, config, allocator)` -- allocator last
//! - `password(message, allocator)` -- allocator second
//! - `multiSelect(message, options, allocator)` -- allocator last
//! - `confirm(message, default)` / `select(message, options)` -- no allocator
//!
//! This inconsistency is a known issue. A future major version may
//! standardise to `allocator` as the first parameter (Zig convention).
//!
//! ## Usage
//!
//! ```zig
//! const prompt = @import("cli").prompt;
//!
//! // Simple input
//! const name = try prompt.input("Enter your name: ", .{});
//!
//! // Password (hidden)
//! const password = try prompt.password("Password: ");
//!
//! // Confirmation with default
//! if (try prompt.confirm("Continue?", true)) {
//!     // proceed
//! }
//!
//! // Select from options
//! const choice = try prompt.select("Choose:", &.{"Option A", "Option B", "Option C"});
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Error types for prompt operations
pub const PromptError = error{
    /// Input was cancelled (Ctrl+C or EOF)
    Cancelled,
    /// Non-interactive terminal (stdin not a TTY)
    NotInteractive,
    /// Read error from stdin
    ReadError,
    /// Invalid input
    InvalidInput,
    /// Out of memory
    OutOfMemory,
};

/// Configuration for text input
pub const InputConfig = struct {
    /// Default value if user presses Enter without input
    default: ?[]const u8 = null,
    /// Validator function - return true if valid
    validator: ?*const fn ([]const u8) bool = null,
    /// Error message for invalid input
    validation_error: []const u8 = "Invalid input",
    /// Maximum input length
    max_length: usize = 1024,
    /// Allow empty input
    allow_empty: bool = true,
};

/// Read a line of text input from the user
pub fn input(message: []const u8, config: InputConfig, allocator: std.mem.Allocator) PromptError![]const u8 {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Check if interactive
    if (!stdin.isTty()) {
        return PromptError.NotInteractive;
    }

    return inputInternal(stdin.reader(), stdout.writer(), message, config, allocator);
}

/// Internal input implementation that accepts generic reader/writer for testability.
fn inputInternal(reader: anytype, writer: anytype, message: []const u8, config: InputConfig, allocator: std.mem.Allocator) PromptError![]const u8 {
    while (true) {
        // Print prompt
        writer.print("{s}", .{message}) catch return PromptError.ReadError;
        if (config.default) |def| {
            writer.print(" [{s}]", .{def}) catch return PromptError.ReadError;
        }
        writer.print(": ", .{}) catch return PromptError.ReadError;

        // Read line with allocator-backed buffer.
        // Use at least 1024 bytes (the original default), but grow up to
        // max_length + 1 for prompts that allow longer input. Cap at 65536.
        const buf_size = @min(@max(config.max_length + 1, 1024), 65536);
        const buffer = allocator.alloc(u8, buf_size) catch return PromptError.OutOfMemory;
        defer allocator.free(buffer);
        const line = reader.readUntilDelimiterOrEof(buffer, '\n') catch {
            return PromptError.ReadError;
        };

        if (line == null) {
            // EOF
            return PromptError.Cancelled;
        }

        const trimmed = std.mem.trim(u8, line.?, " \t\r");

        // Handle empty input
        if (trimmed.len == 0) {
            if (config.default) |def| {
                return allocator.dupe(u8, def) catch return PromptError.OutOfMemory;
            }
            if (!config.allow_empty) {
                writer.print("Input cannot be empty. Please try again.\n", .{}) catch {};
                continue;
            }
            return allocator.dupe(u8, "") catch return PromptError.OutOfMemory;
        }

        // Check length
        if (trimmed.len > config.max_length) {
            writer.print("Input too long (max {d} characters). Please try again.\n", .{config.max_length}) catch {};
            continue;
        }

        // Validate
        if (config.validator) |validate| {
            if (!validate(trimmed)) {
                writer.print("{s}. Please try again.\n", .{config.validation_error}) catch {};
                continue;
            }
        }

        return allocator.dupe(u8, trimmed) catch return PromptError.OutOfMemory;
    }
}

/// Read a password without echoing characters.
///
/// The returned slice is heap-allocated. Callers SHOULD zero the slice
/// before freeing to prevent password data from persisting in memory:
///
///     const pw = try prompt.password("Password: ", allocator);
///     defer {
///         @memset(pw, 0);
///         allocator.free(pw);
///     }
pub fn password(message: []const u8, allocator: std.mem.Allocator) PromptError![]const u8 {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Check if interactive
    if (!stdin.isTty()) {
        return PromptError.NotInteractive;
    }

    // Print prompt
    stdout.writer().print("{s}", .{message}) catch return PromptError.ReadError;

    // Disable echo
    if (comptime builtin.os.tag == .windows) {
        // Windows: manipulate console mode to suppress echo
        const windows = std.os.windows;
        const handle = stdin.handle;
        var original_mode: windows.DWORD = undefined;
        if (windows.kernel32.GetConsoleMode(handle, &original_mode) != 0) {
            // Clear ENABLE_ECHO_INPUT (0x0004) to suppress echo
            const new_mode = original_mode & ~@as(windows.DWORD, 0x0004);
            _ = windows.kernel32.SetConsoleMode(handle, new_mode);
            defer {
                _ = windows.kernel32.SetConsoleMode(handle, original_mode);
                stdout.writer().print("\n", .{}) catch {};
            }
            return passwordInternal(stdin.reader(), allocator);
        } else {
            // GetConsoleMode failed -- fall back to simple read
            return inputSimple(stdin, allocator);
        }
    } else {
        var termios = std.posix.tcgetattr(stdin.handle) catch return PromptError.ReadError;
        const original = termios;

        // Disable ECHO
        termios.lflag.ECHO = false;
        std.posix.tcsetattr(stdin.handle, .FLUSH, termios) catch return PromptError.ReadError;

        defer {
            // Restore original settings
            std.posix.tcsetattr(stdin.handle, .FLUSH, original) catch {};
            stdout.writer().print("\n", .{}) catch {};
        }

        return passwordInternal(stdin.reader(), allocator);
    }
}

/// Internal password implementation that accepts a generic reader for testability.
/// Reads a single line and returns a heap-allocated trimmed copy.
fn passwordInternal(reader: anytype, allocator: std.mem.Allocator) PromptError![]const u8 {
    var buffer: [1024]u8 = undefined;
    defer @memset(&buffer, 0);
    const line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch {
        return PromptError.ReadError;
    };

    if (line == null) {
        return PromptError.Cancelled;
    }

    return allocator.dupe(u8, std.mem.trim(u8, line.?, " \t\r")) catch return PromptError.OutOfMemory;
}

/// Simple line input fallback (used for password on Windows).
/// The returned slice is heap-allocated; callers should zero it before
/// freeing if it may contain sensitive data.
fn inputSimple(stdin: std.fs.File, allocator: std.mem.Allocator) PromptError![]const u8 {
    var buffer: [1024]u8 = undefined;
    defer @memset(&buffer, 0);
    const line = stdin.reader().readUntilDelimiterOrEof(&buffer, '\n') catch {
        return PromptError.ReadError;
    };

    if (line == null) {
        return PromptError.Cancelled;
    }

    const stdout = std.io.getStdOut();
    stdout.writer().print("\n", .{}) catch {};

    return allocator.dupe(u8, std.mem.trim(u8, line.?, " \t\r")) catch return PromptError.OutOfMemory;
}

/// Ask for yes/no confirmation
pub fn confirm(message: []const u8, default: bool) PromptError!bool {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Check if interactive
    if (!stdin.isTty()) {
        return PromptError.NotInteractive;
    }

    return confirmInternal(stdin.reader(), stdout.writer(), message, default);
}

/// Internal confirm implementation that accepts generic reader/writer for testability.
fn confirmInternal(reader: anytype, writer: anytype, message: []const u8, default: bool) PromptError!bool {
    while (true) {
        // Print prompt with default indicator
        if (default) {
            writer.print("{s} [Y/n]: ", .{message}) catch return PromptError.ReadError;
        } else {
            writer.print("{s} [y/N]: ", .{message}) catch return PromptError.ReadError;
        }

        // Read response
        var buffer: [64]u8 = undefined;
        const line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch {
            return PromptError.ReadError;
        };

        if (line == null) {
            return PromptError.Cancelled;
        }

        const trimmed = std.mem.trim(u8, line.?, " \t\r");

        // Handle empty input (use default)
        if (trimmed.len == 0) {
            return default;
        }

        // Parse response
        if (trimmed.len == 1) {
            const c = std.ascii.toLower(trimmed[0]);
            if (c == 'y') return true;
            if (c == 'n') return false;
        }

        // Check for full words
        const lower = std.ascii.lowerString(&buffer, trimmed);
        if (std.mem.eql(u8, lower, "yes")) return true;
        if (std.mem.eql(u8, lower, "no")) return false;

        writer.print("Please enter 'y' or 'n'.\n", .{}) catch {};
    }
}

/// Select one option from a list
pub fn select(message: []const u8, options: []const []const u8) PromptError!usize {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Check if interactive
    if (!stdin.isTty()) {
        return PromptError.NotInteractive;
    }

    return selectInternal(stdin.reader(), stdout.writer(), message, options);
}

/// Internal select implementation that accepts generic reader/writer for testability.
fn selectInternal(reader: anytype, writer: anytype, message: []const u8, options: []const []const u8) PromptError!usize {
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

        // Read response
        var buffer: [64]u8 = undefined;
        const line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch {
            return PromptError.ReadError;
        };

        if (line == null) {
            return PromptError.Cancelled;
        }

        const trimmed = std.mem.trim(u8, line.?, " \t\r");

        // Parse number
        const choice = std.fmt.parseInt(usize, trimmed, 10) catch {
            writer.print("Please enter a number between 1 and {d}.\n", .{options.len}) catch {};
            continue;
        };

        if (choice >= 1 and choice <= options.len) {
            return choice - 1;
        }

        writer.print("Please enter a number between 1 and {d}.\n", .{options.len}) catch {};
    }
}

/// Select multiple options from a list
pub fn multiSelect(message: []const u8, options: []const []const u8, allocator: std.mem.Allocator) PromptError![]usize {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Check if interactive
    if (!stdin.isTty()) {
        return PromptError.NotInteractive;
    }

    return multiSelectInternal(stdin.reader(), stdout.writer(), message, options, allocator);
}

/// Internal multiSelect implementation that accepts generic reader/writer for testability.
fn multiSelectInternal(reader: anytype, writer: anytype, message: []const u8, options: []const []const u8, allocator: std.mem.Allocator) PromptError![]usize {
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

        // Read response
        var buffer: [256]u8 = undefined;
        const line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch {
            return PromptError.ReadError;
        };

        if (line == null) {
            return PromptError.Cancelled;
        }

        const trimmed = std.mem.trim(u8, line.?, " \t\r");

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
            continue;
        }

        return selections.toOwnedSlice(allocator) catch return PromptError.OutOfMemory;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "InputConfig defaults" {
    const config = InputConfig{};
    try std.testing.expect(config.default == null);
    try std.testing.expect(config.validator == null);
    try std.testing.expectEqual(@as(usize, 1024), config.max_length);
    try std.testing.expect(config.allow_empty);
}

test "PromptError is error type" {
    // Just verify the error type compiles correctly
    const err: PromptError = PromptError.NotInteractive;
    try std.testing.expectEqual(PromptError.NotInteractive, err);
}

// --- inputInternal tests ---

test "input: valid input returned" {
    var reader_buf = std.io.fixedBufferStream("hello world\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try inputInternal(reader_buf.reader(), writer.writer(), "Name", .{}, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "input: empty with default returns default" {
    var reader_buf = std.io.fixedBufferStream("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try inputInternal(reader_buf.reader(), writer.writer(), "Name", .{ .default = "Alice" }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Alice", result);
}

test "input: empty with allow_empty=false retries then accepts" {
    // First line is empty (triggers retry), second line has valid input
    var reader_buf = std.io.fixedBufferStream("\ngood\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try inputInternal(reader_buf.reader(), writer.writer(), "Name", .{ .allow_empty = false }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("good", result);
    // Verify retry message was printed
    const output = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Input cannot be empty") != null);
}

test "input: max_length exceeded retries then accepts" {
    // First line is too long, second is within limit
    var reader_buf = std.io.fixedBufferStream("toolong\nok\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try inputInternal(reader_buf.reader(), writer.writer(), "Val", .{ .max_length = 3 }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("ok", result);
    const output = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Input too long") != null);
}

test "input: validator rejection retries then accepts" {
    const S = struct {
        fn noDigits(s: []const u8) bool {
            for (s) |c| {
                if (std.ascii.isDigit(c)) return false;
            }
            return true;
        }
    };

    // "abc123" fails validation, "abc" passes
    var reader_buf = std.io.fixedBufferStream("abc123\nabc\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try inputInternal(reader_buf.reader(), writer.writer(), "Name", .{
        .validator = &S.noDigits,
        .validation_error = "No digits allowed",
    }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("abc", result);
    const output = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "No digits allowed") != null);
}

test "input: EOF returns Cancelled" {
    // Empty stream (no newline) = EOF
    var reader_buf = std.io.fixedBufferStream("");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = inputInternal(reader_buf.reader(), writer.writer(), "Name", .{}, std.testing.allocator);
    try std.testing.expectError(PromptError.Cancelled, result);
}

test "input: empty with allow_empty=true returns empty string" {
    var reader_buf = std.io.fixedBufferStream("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try inputInternal(reader_buf.reader(), writer.writer(), "Name", .{ .allow_empty = true }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

// --- passwordInternal tests ---

test "password: valid input returned" {
    var reader_buf = std.io.fixedBufferStream("s3cret\n");

    const result = try passwordInternal(reader_buf.reader(), std.testing.allocator);
    defer {
        @memset(@constCast(result), 0);
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqualStrings("s3cret", result);
}

test "password: EOF returns Cancelled" {
    var reader_buf = std.io.fixedBufferStream("");

    const result = passwordInternal(reader_buf.reader(), std.testing.allocator);
    try std.testing.expectError(PromptError.Cancelled, result);
}

test "password: input is trimmed" {
    var reader_buf = std.io.fixedBufferStream("  mypass  \n");

    const result = try passwordInternal(reader_buf.reader(), std.testing.allocator);
    defer {
        @memset(@constCast(result), 0);
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqualStrings("mypass", result);
}

// --- confirmInternal tests ---

test "confirm: y returns true" {
    var reader_buf = std.io.fixedBufferStream("y\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", false);
    try std.testing.expect(result == true);
}

test "confirm: Y returns true" {
    var reader_buf = std.io.fixedBufferStream("Y\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", false);
    try std.testing.expect(result == true);
}

test "confirm: yes returns true" {
    var reader_buf = std.io.fixedBufferStream("yes\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", false);
    try std.testing.expect(result == true);
}

test "confirm: n returns false" {
    var reader_buf = std.io.fixedBufferStream("n\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", true);
    try std.testing.expect(result == false);
}

test "confirm: N returns false" {
    var reader_buf = std.io.fixedBufferStream("N\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", true);
    try std.testing.expect(result == false);
}

test "confirm: no returns false" {
    var reader_buf = std.io.fixedBufferStream("no\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", true);
    try std.testing.expect(result == false);
}

test "confirm: empty returns default true" {
    var reader_buf = std.io.fixedBufferStream("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", true);
    try std.testing.expect(result == true);
}

test "confirm: empty returns default false" {
    var reader_buf = std.io.fixedBufferStream("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", false);
    try std.testing.expect(result == false);
}

test "confirm: invalid input retries then accepts" {
    // "maybe" is invalid, then "y" is valid
    var reader_buf = std.io.fixedBufferStream("maybe\ny\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = try confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", false);
    try std.testing.expect(result == true);
    const output = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Please enter 'y' or 'n'.") != null);
}

test "confirm: EOF returns Cancelled" {
    var reader_buf = std.io.fixedBufferStream("");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const result = confirmInternal(reader_buf.reader(), writer.writer(), "Continue?", false);
    try std.testing.expectError(PromptError.Cancelled, result);
}

// --- selectInternal tests ---

test "select: valid 1-based index" {
    var reader_buf = std.io.fixedBufferStream("2\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try selectInternal(reader_buf.reader(), writer.writer(), "Pick:", options);
    try std.testing.expectEqual(@as(usize, 1), result); // 0-based index
}

test "select: out-of-range retries then accepts" {
    // "5" is out of range, then "1" is valid
    var reader_buf = std.io.fixedBufferStream("5\n1\n");
    var writer_buf: [8192]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try selectInternal(reader_buf.reader(), writer.writer(), "Pick:", options);
    try std.testing.expectEqual(@as(usize, 0), result);
    const output = writer.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Please enter a number between 1 and 3.") != null);
}

test "select: non-numeric retries then accepts" {
    // "abc" is non-numeric, then "3" is valid
    var reader_buf = std.io.fixedBufferStream("abc\n3\n");
    var writer_buf: [8192]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try selectInternal(reader_buf.reader(), writer.writer(), "Pick:", options);
    try std.testing.expectEqual(@as(usize, 2), result);
}

test "select: empty options returns InvalidInput" {
    var reader_buf = std.io.fixedBufferStream("1\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options: []const []const u8 = &.{};
    const result = selectInternal(reader_buf.reader(), writer.writer(), "Pick:", options);
    try std.testing.expectError(PromptError.InvalidInput, result);
}

test "select: EOF returns Cancelled" {
    var reader_buf = std.io.fixedBufferStream("");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta" };
    const result = selectInternal(reader_buf.reader(), writer.writer(), "Pick:", options);
    try std.testing.expectError(PromptError.Cancelled, result);
}

// --- multiSelectInternal tests ---

test "multiSelect: comma-separated parsing" {
    var reader_buf = std.io.fixedBufferStream("1,3\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try multiSelectInternal(reader_buf.reader(), writer.writer(), "Pick:", options, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(usize, 0), result[0]); // 1 -> 0-based
    try std.testing.expectEqual(@as(usize, 2), result[1]); // 3 -> 2-based
}

test "multiSelect: out-of-range retries then accepts" {
    // "1,5" has out-of-range 5, retries; then "2" is valid
    var reader_buf = std.io.fixedBufferStream("1,5\n2\n");
    var writer_buf: [8192]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try multiSelectInternal(reader_buf.reader(), writer.writer(), "Pick:", options, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 1), result[0]);
}

test "multiSelect: single selection" {
    var reader_buf = std.io.fixedBufferStream("2\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta", "Gamma" };
    const result = try multiSelectInternal(reader_buf.reader(), writer.writer(), "Pick:", options, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 1), result[0]);
}

test "multiSelect: empty options returns InvalidInput" {
    var reader_buf = std.io.fixedBufferStream("1\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options: []const []const u8 = &.{};
    const result = multiSelectInternal(reader_buf.reader(), writer.writer(), "Pick:", options, std.testing.allocator);
    try std.testing.expectError(PromptError.InvalidInput, result);
}

test "multiSelect: EOF returns Cancelled" {
    var reader_buf = std.io.fixedBufferStream("");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.io.fixedBufferStream(&writer_buf);

    const options = &[_][]const u8{ "Alpha", "Beta" };
    const result = multiSelectInternal(reader_buf.reader(), writer.writer(), "Pick:", options, std.testing.allocator);
    try std.testing.expectError(PromptError.Cancelled, result);
}
