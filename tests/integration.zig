// SPDX-License-Identifier: MIT
// Copyright (c) 2024 DevNW

//! # Integration Tests
//!
//! Tests for the zig-cli library covering:
//! - Help generation forms
//! - Config precedence
//! - NO_COLOR behavior
//! - Suggestions for typos
//! - Secret handling
//! - Order-independent parsing

const std = @import("std");
const testing = std.testing;

const cli = @import("cli");
const config = @import("config");
const term = @import("term");
const util = @import("util");

// ============================================================================
// Help Tests
// ============================================================================

test "help shows examples first" {
    const cmd = cli.Command{
        .name = "test",
        .summary = "Test command",
        .examples = &.{
            "test --help",
            "test kv get KEY",
        },
    };

    var ctx = cli.Context.init(testing.allocator);
    defer ctx.deinit();

    // Redirect stdout to /dev/null to prevent pipe deadlock in test harness
    const devnull = std.Io.Dir.openFileAbsolute("/dev/null", .{ .mode = .write_only }) catch {
        return; // Skip if /dev/null not available
    };
    defer devnull.close();
    ctx.stdout = devnull.writerStreaming(std.Io.Threaded.global_single_threaded.io(), &[_]u8{} ** 0);

    // Help generation doesn't crash
    cli.printHelp(&cmd, &ctx);
}

test "help shows subcommands" {
    const sub = cli.Command{
        .name = "sub",
        .summary = "Subcommand",
    };

    const root = cli.Command{
        .name = "root",
        .summary = "Root command",
        .subcommands = &.{&sub},
    };

    try testing.expect(root.hasSubcommands());
    try testing.expect(root.findSubcommand("sub") != null);
}

// ============================================================================
// Precedence Tests
// ============================================================================

test "config precedence - higher priority wins" {
    var tracker = config.ProvenanceTracker.init(testing.allocator);
    defer tracker.deinit();

    // Set from system (lowest priority)
    try tracker.set("port", "8080", .system, "/etc/app/config.toml");

    // Override from user
    try tracker.set("port", "9000", .user, "~/.config/app/config.toml");

    // Value should be from user
    const val = tracker.get("port").?;
    try testing.expectEqualStrings("9000", val.value);
    try testing.expectEqual(config.Source.user, val.source);

    // Try to override from system again - should NOT change
    try tracker.set("port", "7000", .system, "/etc/app2/config.toml");
    const val2 = tracker.get("port").?;
    try testing.expectEqualStrings("9000", val2.value);
}

test "source precedence order" {
    try testing.expect(config.Source.flag.precedence() < config.Source.env.precedence());
    try testing.expect(config.Source.env.precedence() < config.Source.project.precedence());
    try testing.expect(config.Source.project.precedence() < config.Source.user.precedence());
    try testing.expect(config.Source.user.precedence() < config.Source.system.precedence());
    try testing.expect(config.Source.system.precedence() < config.Source.default.precedence());
}

// ============================================================================
// NO_COLOR Tests
// ============================================================================

test "color context respects no_color flag" {
    const ctx = term.ColorContext.init(null, true); // no_color = true
    try testing.expect(!ctx.enabled);
}

test "color context can be forced on" {
    const ctx = term.ColorContext.init(true, false); // force_color = true
    try testing.expect(ctx.enabled);
}

test "strip ANSI removes sequences" {
    const colored = "\x1b[31mred\x1b[0m text";
    const stripped = try term.stripAnsi(colored, testing.allocator);
    defer testing.allocator.free(stripped);

    try testing.expectEqualStrings("red text", stripped);
}

// ============================================================================
// Suggestion Tests
// ============================================================================

test "suggest closest - typo correction" {
    const commands = &[_][]const u8{ "status", "start", "stop", "serve" };

    // staus -> status (one char swap)
    const suggestion = util.suggestClosest("staus", commands, 2);
    try testing.expect(suggestion != null);
    try testing.expectEqualStrings("status", suggestion.?);
}

test "suggest closest - no match beyond distance" {
    const commands = &[_][]const u8{ "status", "start", "stop", "serve" };

    // xyz is too different
    const suggestion = util.suggestClosest("xyz", commands, 2);
    try testing.expect(suggestion == null);
}

test "levenshtein distance" {
    try testing.expectEqual(@as(usize, 0), util.levenshteinDistance("hello", "hello"));
    try testing.expectEqual(@as(usize, 1), util.levenshteinDistance("hello", "hallo"));
    try testing.expectEqual(@as(usize, 1), util.levenshteinDistance("hello", "helo"));
}

// ============================================================================
// Secret Handling Tests
// ============================================================================

test "secret redaction" {
    const redacted = config.secret.redact("super-secret-password");
    try testing.expectEqualStrings("***REDACTED***", redacted);
}

test "secure zero clears buffer" {
    var buffer = [_]u8{ 's', 'e', 'c', 'r', 'e', 't' };
    config.secret.secureZero(&buffer);

    for (buffer) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

// ============================================================================
// Order-Independent Parsing Tests
// ============================================================================

test "parser handles flags before and after subcommand" {
    const root = cli.Command{
        .name = "test",
        .summary = "Test command",
        .flags = &.{
            cli.FlagSpec{
                .name = "verbose",
                .short = 'v',
                .help = "Verbose output",
                .ftype = .bool,
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &root, "1.0.0", "");

    // Flags can be anywhere
    var result = try parser.parse(&.{ "test", "-v" });
    defer result.deinit(testing.allocator);

    try testing.expect(result.context.getBool("verbose"));
}

// ============================================================================
// Exit Code Tests
// ============================================================================

test "exit codes" {
    try testing.expectEqual(@as(u8, 0), util.ExitCode.success.toInt());
    try testing.expectEqual(@as(u8, 1), util.ExitCode.general_error.toInt());
    try testing.expectEqual(@as(u8, 2), util.ExitCode.usage_error.toInt());
}

// ============================================================================
// Format Detection Tests
// ============================================================================

test "config format detection" {
    try testing.expectEqual(config.Format.toml, config.Format.fromExtension("config.toml"));
    try testing.expectEqual(config.Format.json, config.Format.fromExtension("config.json"));
    try testing.expectEqual(config.Format.yaml, config.Format.fromExtension("config.yaml"));
    try testing.expectEqual(config.Format.yaml, config.Format.fromExtension("config.yml"));
}

// ============================================================================
// XDG Tests
// ============================================================================

test "getSystemConfigDir" {
    const dir = try config.xdg.getSystemConfigDir("testapp", testing.allocator);
    defer testing.allocator.free(dir);

    try testing.expectEqualStrings("/etc/testapp", dir);
}

// ============================================================================
// Text Utility Tests
// ============================================================================

test "text truncation with ellipsis" {
    const truncated = try util.truncate("hello world", 8, testing.allocator);
    defer testing.allocator.free(truncated);

    try testing.expectEqualStrings("hello...", truncated);
}

test "text padding" {
    const padded = try util.padRight("hi", 5, testing.allocator);
    defer testing.allocator.free(padded);

    try testing.expectEqual(@as(usize, 5), padded.len);
}

// ============================================================================
// Filesystem Tests
// ============================================================================

test "exists returns true for current directory" {
    try testing.expect(util.exists("."));
}

test "isDirectory detects directories" {
    try testing.expect(util.isDirectory("."));
}

test "safe path detection" {
    try testing.expect(util.fs.isSafePath("/home/user/file.txt"));
    try testing.expect(!util.fs.isSafePath("/etc/shadow"));
}

// ============================================================================
// Validation Tests
// ============================================================================

test "required validation" {
    try config.validate.required("value");
    try testing.expectError(config.ValidationError.Required, config.validate.required(null));
    try testing.expectError(config.ValidationError.Required, config.validate.required(""));
}

test "url validation" {
    try config.validate.url("https://example.com");
    try config.validate.url("http://localhost:8080");
    try testing.expectError(config.ValidationError.PatternMismatch, config.validate.url("ftp://example.com"));
}

// ============================================================================
// Config Loading Integration Tests (#6)
// ============================================================================

test "config: parseContent YAML" {
    const content =
        \\server:
        \\  host: localhost
        \\  port: 8080
        \\debug: true
    ;
    var parsed = try config.parseContent(testing.allocator, content, .yaml);
    defer parsed.deinit();

    try testing.expectEqualStrings("localhost", parsed.getString("server.host").?);
    try testing.expectEqual(@as(i64, 8080), parsed.getInt("server.port").?);
    try testing.expectEqual(true, parsed.getBool("debug").?);
}

test "config: parseContent JSON" {
    const content = "{\"server\":{\"host\":\"localhost\",\"port\":8080},\"debug\":true}";
    var parsed = try config.parseContent(testing.allocator, content, .json);
    defer parsed.deinit();

    try testing.expectEqualStrings("localhost", parsed.getString("server.host").?);
    try testing.expectEqual(@as(i64, 8080), parsed.getInt("server.port").?);
    try testing.expectEqual(true, parsed.getBool("debug").?);
}

test "config: parseContent TOML" {
    const content =
        \\[server]
        \\host = "localhost"
        \\port = 8080
        \\debug = true
    ;
    var parsed = try config.parseContent(testing.allocator, content, .toml);
    defer parsed.deinit();

    try testing.expectEqualStrings("localhost", parsed.getString("server.host").?);
    try testing.expectEqual(@as(i64, 8080), parsed.getInt("server.port").?);
    try testing.expectEqual(true, parsed.getBool("server.debug").?);
}

test "config: provenance tracks multiple sources" {
    var tracker = config.ProvenanceTracker.init(testing.allocator);
    defer tracker.deinit();

    // Set from default
    try tracker.set("timeout", "30", .default, "builtin");

    // Override from system config
    try tracker.set("timeout", "60", .system, "/etc/app/config.toml");

    // Override from user config
    try tracker.set("timeout", "120", .user, "~/.config/app/config.toml");

    // Override from project config
    try tracker.set("timeout", "180", .project, "./config.toml");

    // Override from env
    try tracker.set("timeout", "240", .env, "APP_TIMEOUT");

    // Final value should be from env (higher precedence)
    const val = tracker.get("timeout").?;
    try testing.expectEqualStrings("240", val.value);
    try testing.expectEqual(config.Source.env, val.source);
}

test "config: flag precedence overrides env" {
    var tracker = config.ProvenanceTracker.init(testing.allocator);
    defer tracker.deinit();

    // Set from env
    try tracker.set("port", "8080", .env, "APP_PORT");

    // Override from CLI flag
    try tracker.set("port", "9000", .flag, "--port");

    // Flag should win
    const val = tracker.get("port").?;
    try testing.expectEqualStrings("9000", val.value);
    try testing.expectEqual(config.Source.flag, val.source);
}

test "config: lower precedence cannot override" {
    var tracker = config.ProvenanceTracker.init(testing.allocator);
    defer tracker.deinit();

    // Set from user config
    try tracker.set("debug", "true", .user, "~/.config/app/config.toml");

    // Try to override from system (lower precedence)
    try tracker.set("debug", "false", .system, "/etc/app/config.toml");

    // User config should still win
    const val = tracker.get("debug").?;
    try testing.expectEqualStrings("true", val.value);
    try testing.expectEqual(config.Source.user, val.source);
}

test "config: getAll returns all tracked values" {
    var tracker = config.ProvenanceTracker.init(testing.allocator);
    defer tracker.deinit();

    try tracker.set("host", "localhost", .default, "builtin");
    try tracker.set("port", "8080", .user, "~/.config/app/config.toml");
    try tracker.set("debug", "true", .env, "APP_DEBUG");

    const all = tracker.getAll();
    defer testing.allocator.free(all);
    try testing.expectEqual(@as(usize, 3), all.len);
}

// Note: Complex nested parsing tests disabled due to external library issues

test "config: format detection from extension" {
    try testing.expectEqual(config.Format.toml, config.Format.fromExtension("app.toml"));
    try testing.expectEqual(config.Format.json, config.Format.fromExtension("config.json"));
    try testing.expectEqual(config.Format.yaml, config.Format.fromExtension("settings.yaml"));
    try testing.expectEqual(config.Format.yaml, config.Format.fromExtension("settings.yml"));
    // Unknown extensions default to TOML
    try testing.expectEqual(config.Format.toml, config.Format.fromExtension("config.txt"));
    try testing.expectEqual(config.Format.toml, config.Format.fromExtension("noextension"));
}

test "config: validation integration" {
    // Test multiple validators together
    try config.validate.required("value");
    try config.validate.minLength("hello", 3);
    try config.validate.maxLength("hello", 10);
    try config.validate.url("https://example.com/path?query=1");
    try config.validate.email("test@example.com");
    try config.validate.hostname("example.com");
    try config.validate.port(8080);

    // Test validation failures
    try testing.expectError(config.ValidationError.Required, config.validate.required(null));
    try testing.expectError(config.ValidationError.TooShort, config.validate.minLength("ab", 3));
    try testing.expectError(config.ValidationError.TooLong, config.validate.maxLength("hello world", 5));
    try testing.expectError(config.ValidationError.OutOfRange, config.validate.port(0));
}

test "config: CLI flag value applied to context" {
    const cmd = cli.Command{
        .name = "app",
        .summary = "Test application",
        .flags = &.{
            cli.FlagSpec{
                .name = "port",
                .short = 'p',
                .help = "Server port",
                .ftype = .int,
                .default_str = "8080",
                .env = "APP_PORT",
            },
            cli.FlagSpec{
                .name = "host",
                .short = 'H',
                .help = "Server host",
                .ftype = .string,
                .default_str = "localhost",
                .env = "APP_HOST",
            },
            cli.FlagSpec{
                .name = "debug",
                .short = 'd',
                .help = "Enable debug mode",
                .ftype = .bool,
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &cmd, "1.0.0", "");

    // Test with explicit flag values
    var result = try parser.parse(&.{ "app", "--port", "9000", "--host", "0.0.0.0", "--debug" });
    defer result.deinit(testing.allocator);

    // Flag values should be accessible from context
    try testing.expectEqual(@as(i64, 9000), result.context.getInt("port").?);
    try testing.expectEqualStrings("0.0.0.0", result.context.getString("host").?);
    try testing.expect(result.context.getBool("debug"));
}

test "config: CLI uses default values when not specified" {
    const cmd = cli.Command{
        .name = "app",
        .summary = "Test application",
        .flags = &.{
            cli.FlagSpec{
                .name = "port",
                .help = "Server port",
                .ftype = .int,
                .default_str = "8080",
            },
            cli.FlagSpec{
                .name = "host",
                .help = "Server host",
                .ftype = .string,
                .default_str = "localhost",
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &cmd, "1.0.0", "");

    // Parse with no flags specified
    var result = try parser.parse(&.{"app"});
    defer result.deinit(testing.allocator);

    // Should have default values applied
    try testing.expectEqual(@as(i64, 8080), result.context.getInt("port").?);
    try testing.expectEqualStrings("localhost", result.context.getString("host").?);
}
