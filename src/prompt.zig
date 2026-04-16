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

inline fn globalIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

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

/// Read a single line (up to '\n', exclusive) into a newly-allocated slice.
/// Consumes the trailing '\n' if present. Returns null on EOF with no data buffered.
fn readLineAlloc(reader: *std.Io.Reader, allocator: std.mem.Allocator) PromptError!?[]u8 {
    const slice = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return null,
        error.StreamTooLong => return PromptError.ReadError,
        error.ReadFailed => return PromptError.ReadError,
    };
    const out = allocator.dupe(u8, slice) catch return PromptError.OutOfMemory;
    // takeDelimiterExclusive leaves the delimiter in the buffer; discard it.
    _ = reader.takeByte() catch {};
    return out;
}

/// Read a single line into `buf`. Consumes the trailing '\n' if present.
/// Returns the slice of `buf` that was filled, or null on EOF.
fn readLineInto(reader: *std.Io.Reader, buf: []u8) PromptError!?[]u8 {
    const slice = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return null,
        error.StreamTooLong => return PromptError.ReadError,
        error.ReadFailed => return PromptError.ReadError,
    };
    if (slice.len > buf.len) return PromptError.ReadError;
    @memcpy(buf[0..slice.len], slice);
    const len = slice.len;
    // takeDelimiterExclusive leaves the delimiter in the buffer; discard it.
    _ = reader.takeByte() catch {};
    return buf[0..len];
}

/// Read a line of text input from the user
pub fn input(message: []const u8, config: InputConfig, allocator: std.mem.Allocator) PromptError![]const u8 {
    const io = globalIo();
    const stdin_file = std.Io.File.stdin();
    const stdout_file = std.Io.File.stdout();

    // Check if interactive
    const is_tty = stdin_file.isTty(io) catch false;
    if (!is_tty) {
        return PromptError.NotInteractive;
    }

    // Use a buffer large enough for the maximum line length plus room for the
    // delimiter. takeDelimiterExclusive works on the reader's internal buffer.
    const rbuf_size = @min(@max(config.max_length + 2, 4096), 65536);
    const rbuf = allocator.alloc(u8, rbuf_size) catch return PromptError.OutOfMemory;
    defer allocator.free(rbuf);
    var reader_state = stdin_file.reader(io, rbuf);

    var wbuf: [4096]u8 = undefined;
    var writer_state = stdout_file.writer(io, &wbuf);
    defer writer_state.interface.flush() catch {};

    return inputInternal(&reader_state.interface, &writer_state.interface, message, config, allocator);
}

/// Internal input implementation that accepts std.Io reader/writer for testability.
fn inputInternal(reader: *std.Io.Reader, writer: *std.Io.Writer, message: []const u8, config: InputConfig, allocator: std.mem.Allocator) PromptError![]const u8 {
    while (true) {
        // Print prompt
        writer.print("{s}", .{message}) catch return PromptError.ReadError;
        if (config.default) |def| {
            writer.print(" [{s}]", .{def}) catch return PromptError.ReadError;
        }
        writer.print(": ", .{}) catch return PromptError.ReadError;
        writer.flush() catch return PromptError.ReadError;

        const line_opt = try readLineAlloc(reader, allocator);
        if (line_opt == null) {
            return PromptError.Cancelled;
        }
        const line = line_opt.?;
        defer allocator.free(line);

        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Handle empty input
        if (trimmed.len == 0) {
            if (config.default) |def| {
                return allocator.dupe(u8, def) catch return PromptError.OutOfMemory;
            }
            if (!config.allow_empty) {
                writer.print("Input cannot be empty. Please try again.\n", .{}) catch {};
                writer.flush() catch {};
                continue;
            }
            return allocator.dupe(u8, "") catch return PromptError.OutOfMemory;
        }

        // Check length
        if (trimmed.len > config.max_length) {
            writer.print("Input too long (max {d} characters). Please try again.\n", .{config.max_length}) catch {};
            writer.flush() catch {};
            continue;
        }

        // Validate
        if (config.validator) |validate| {
            if (!validate(trimmed)) {
                writer.print("{s}. Please try again.\n", .{config.validation_error}) catch {};
                writer.flush() catch {};
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
    const io = globalIo();
    const stdin_file = std.Io.File.stdin();
    const stdout_file = std.Io.File.stdout();

    // Check if interactive
    const is_tty = stdin_file.isTty(io) catch false;
    if (!is_tty) {
        return PromptError.NotInteractive;
    }

    var wbuf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(io, &wbuf);
    const stdout_w = &stdout_writer.interface;

    // Print prompt
    stdout_w.print("{s}", .{message}) catch return PromptError.ReadError;
    stdout_w.flush() catch return PromptError.ReadError;

    var rbuf: [2048]u8 = undefined;
    var stdin_reader = stdin_file.reader(io, &rbuf);
    const stdin_r = &stdin_reader.interface;

    // Disable echo
    if (comptime builtin.os.tag == .windows) {
        // Windows: manipulate console mode to suppress echo
        const windows = std.os.windows;
        const handle = stdin_file.handle;
        var original_mode: windows.DWORD = undefined;
        if (windows.kernel32.GetConsoleMode(handle, &original_mode) != 0) {
            // Clear ENABLE_ECHO_INPUT (0x0004) to suppress echo
            const new_mode = original_mode & ~@as(windows.DWORD, 0x0004);
            _ = windows.kernel32.SetConsoleMode(handle, new_mode);
            defer {
                _ = windows.kernel32.SetConsoleMode(handle, original_mode);
                stdout_w.print("\n", .{}) catch {};
                stdout_w.flush() catch {};
            }
            return passwordInternal(stdin_r, allocator);
        } else {
            // GetConsoleMode failed -- fall back to simple read
            return passwordInternal(stdin_r, allocator);
        }
    } else {
        var termios = std.posix.tcgetattr(stdin_file.handle) catch return PromptError.ReadError;
        const original = termios;

        // Disable ECHO
        termios.lflag.ECHO = false;
        std.posix.tcsetattr(stdin_file.handle, .FLUSH, termios) catch return PromptError.ReadError;

        defer {
            // Restore original settings
            std.posix.tcsetattr(stdin_file.handle, .FLUSH, original) catch {};
            stdout_w.print("\n", .{}) catch {};
            stdout_w.flush() catch {};
        }

        return passwordInternal(stdin_r, allocator);
    }
}

/// Internal password implementation that accepts a std.Io.Reader for testability.
/// Reads a single line and returns a heap-allocated trimmed copy.
fn passwordInternal(reader: *std.Io.Reader, allocator: std.mem.Allocator) PromptError![]const u8 {
    const line_opt = try readLineAlloc(reader, allocator);
    if (line_opt == null) {
        return PromptError.Cancelled;
    }
    const line = line_opt.?;
    defer {
        @memset(line, 0);
        allocator.free(line);
    }

    return allocator.dupe(u8, std.mem.trim(u8, line, " \t\r")) catch return PromptError.OutOfMemory;
}

/// Ask for yes/no confirmation
pub fn confirm(message: []const u8, default: bool) PromptError!bool {
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

    return confirmInternal(&reader_state.interface, &writer_state.interface, message, default);
}

/// Internal confirm implementation that accepts std.Io reader/writer for testability.
fn confirmInternal(reader: *std.Io.Reader, writer: *std.Io.Writer, message: []const u8, default: bool) PromptError!bool {
    while (true) {
        // Print prompt with default indicator
        if (default) {
            writer.print("{s} [Y/n]: ", .{message}) catch return PromptError.ReadError;
        } else {
            writer.print("{s} [y/N]: ", .{message}) catch return PromptError.ReadError;
        }
        writer.flush() catch return PromptError.ReadError;

        // Read response
        var buffer: [64]u8 = undefined;
        const line_opt = try readLineInto(reader, &buffer);
        if (line_opt == null) {
            return PromptError.Cancelled;
        }
        const line = line_opt.?;

        const trimmed = std.mem.trim(u8, line, " \t\r");

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

        // Check for full words (copy to a scratch buffer because `trimmed`
        // aliases the reader's internal buffer, and lowerString writes in place).
        var lower_buf: [64]u8 = undefined;
        if (trimmed.len <= lower_buf.len) {
            @memcpy(lower_buf[0..trimmed.len], trimmed);
            const lower = std.ascii.lowerString(lower_buf[0..trimmed.len], lower_buf[0..trimmed.len]);
            if (std.mem.eql(u8, lower, "yes")) return true;
            if (std.mem.eql(u8, lower, "no")) return false;
        }

        writer.print("Please enter 'y' or 'n'.\n", .{}) catch {};
        writer.flush() catch {};
    }
}

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
    var reader = std.Io.Reader.fixed("hello world\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try inputInternal(&reader, &writer, "Name", .{}, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "input: empty with default returns default" {
    var reader = std.Io.Reader.fixed("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try inputInternal(&reader, &writer, "Name", .{ .default = "Alice" }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Alice", result);
}

test "input: empty with allow_empty=false retries then accepts" {
    // First line is empty (triggers retry), second line has valid input
    var reader = std.Io.Reader.fixed("\ngood\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try inputInternal(&reader, &writer, "Name", .{ .allow_empty = false }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("good", result);
    // Verify retry message was printed
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Input cannot be empty") != null);
}

test "input: max_length exceeded retries then accepts" {
    // First line is too long, second is within limit
    var reader = std.Io.Reader.fixed("toolong\nok\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try inputInternal(&reader, &writer, "Val", .{ .max_length = 3 }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("ok", result);
    const output = writer.buffered();
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
    var reader = std.Io.Reader.fixed("abc123\nabc\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try inputInternal(&reader, &writer, "Name", .{
        .validator = &S.noDigits,
        .validation_error = "No digits allowed",
    }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("abc", result);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "No digits allowed") != null);
}

test "input: EOF returns Cancelled" {
    // Empty stream (no newline) = EOF
    var reader = std.Io.Reader.fixed("");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = inputInternal(&reader, &writer, "Name", .{}, std.testing.allocator);
    try std.testing.expectError(PromptError.Cancelled, result);
}

test "input: empty with allow_empty=true returns empty string" {
    var reader = std.Io.Reader.fixed("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try inputInternal(&reader, &writer, "Name", .{ .allow_empty = true }, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

// --- passwordInternal tests ---

test "password: valid input returned" {
    var reader = std.Io.Reader.fixed("s3cret\n");

    const result = try passwordInternal(&reader, std.testing.allocator);
    defer {
        @memset(@constCast(result), 0);
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqualStrings("s3cret", result);
}

test "password: EOF returns Cancelled" {
    var reader = std.Io.Reader.fixed("");

    const result = passwordInternal(&reader, std.testing.allocator);
    try std.testing.expectError(PromptError.Cancelled, result);
}

test "password: input is trimmed" {
    var reader = std.Io.Reader.fixed("  mypass  \n");

    const result = try passwordInternal(&reader, std.testing.allocator);
    defer {
        @memset(@constCast(result), 0);
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqualStrings("mypass", result);
}

// --- confirmInternal tests ---

test "confirm: y returns true" {
    var reader = std.Io.Reader.fixed("y\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", false);
    try std.testing.expect(result == true);
}

test "confirm: Y returns true" {
    var reader = std.Io.Reader.fixed("Y\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", false);
    try std.testing.expect(result == true);
}

test "confirm: yes returns true" {
    var reader = std.Io.Reader.fixed("yes\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", false);
    try std.testing.expect(result == true);
}

test "confirm: n returns false" {
    var reader = std.Io.Reader.fixed("n\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", true);
    try std.testing.expect(result == false);
}

test "confirm: N returns false" {
    var reader = std.Io.Reader.fixed("N\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", true);
    try std.testing.expect(result == false);
}

test "confirm: no returns false" {
    var reader = std.Io.Reader.fixed("no\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", true);
    try std.testing.expect(result == false);
}

test "confirm: empty returns default true" {
    var reader = std.Io.Reader.fixed("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", true);
    try std.testing.expect(result == true);
}

test "confirm: empty returns default false" {
    var reader = std.Io.Reader.fixed("\n");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", false);
    try std.testing.expect(result == false);
}

test "confirm: invalid input retries then accepts" {
    // "maybe" is invalid, then "y" is valid
    var reader = std.Io.Reader.fixed("maybe\ny\n");
    var writer_buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = try confirmInternal(&reader, &writer, "Continue?", false);
    try std.testing.expect(result == true);
    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "Please enter 'y' or 'n'.") != null);
}

test "confirm: EOF returns Cancelled" {
    var reader = std.Io.Reader.fixed("");
    var writer_buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buf);

    const result = confirmInternal(&reader, &writer, "Continue?", false);
    try std.testing.expectError(PromptError.Cancelled, result);
}

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
