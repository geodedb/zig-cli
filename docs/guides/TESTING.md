# Testing CLI Applications Guide

This guide covers best practices for testing CLI applications built with zig-cli.

## Unit Testing Commands

### Testing Flag Parsing

```zig
const std = @import("std");
const testing = std.testing;
const cli = @import("cli");

test "parse port flag" {
    const root = cli.Command{
        .name = "server",
        .summary = "Test server",
        .flags = &.{
            cli.FlagSpec{
                .name = "port",
                .short = 'p',
                .help = "Port number",
                .ftype = .int,
                .default_str = "8080",
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &root, "1.0.0", "");

    // Test with explicit value
    var result = try parser.parse(&.{ "server", "--port", "3000" });
    defer result.context.deinit();

    try testing.expectEqual(@as(i64, 3000), result.context.getInt("port").?);
}

test "parse boolean flags" {
    const root = cli.Command{
        .name = "app",
        .summary = "Test app",
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

    // Boolean flag present
    var result1 = try parser.parse(&.{ "app", "-v" });
    defer result1.context.deinit();
    try testing.expect(result1.context.getBool("verbose"));

    // Boolean flag absent
    var result2 = try parser.parse(&.{ "app" });
    defer result2.context.deinit();
    try testing.expect(!result2.context.getBool("verbose"));
}
```

### Testing String Array Flags

```zig
test "parse string array flag" {
    const root = cli.Command{
        .name = "app",
        .summary = "Test app",
        .flags = &.{
            cli.FlagSpec{
                .name = "include",
                .help = "Include paths",
                .ftype = .string_array,
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &root, "1.0.0", "");

    // Multiple values
    var result = try parser.parse(&.{
        "app",
        "--include", "src",
        "--include", "lib"
    });
    defer result.context.deinit();

    const includes = result.context.getStringArray("include").?;
    try testing.expectEqual(@as(usize, 2), includes.len);
    try testing.expectEqualStrings("src", includes[0]);
    try testing.expectEqualStrings("lib", includes[1]);
}
```

### Testing Subcommand Resolution

```zig
test "subcommand routing" {
    const sub = cli.Command{
        .name = "serve",
        .summary = "Start server",
    };

    const root = cli.Command{
        .name = "app",
        .summary = "Test app",
        .subcommands = &.{&sub},
    };

    var parser = cli.Parser.init(testing.allocator, &root, "1.0.0", "");
    var result = try parser.parse(&.{ "app", "serve" });
    defer result.context.deinit();

    try testing.expectEqualStrings("serve", result.command.name);
}
```

### Testing Error Cases

```zig
test "missing required flag returns error" {
    const root = cli.Command{
        .name = "app",
        .summary = "Test app",
        .flags = &.{
            cli.FlagSpec{
                .name = "config",
                .help = "Config file",
                .ftype = .path,
                .required = true,
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &root, "1.0.0", "");

    try testing.expectError(
        cli.ParseError.MissingRequired,
        parser.parse(&.{ "app" })
    );
}

test "invalid integer returns error" {
    const root = cli.Command{
        .name = "app",
        .summary = "Test app",
        .flags = &.{
            cli.FlagSpec{
                .name = "port",
                .help = "Port",
                .ftype = .int,
            },
        },
    };

    var parser = cli.Parser.init(testing.allocator, &root, "1.0.0", "");

    try testing.expectError(
        cli.ParseError.InvalidValue,
        parser.parse(&.{ "app", "--port", "abc" })
    );
}
```

## Testing Help Output

```zig
test "help generation includes flag" {
    const root = cli.Command{
        .name = "myapp",
        .summary = "My application",
        .flags = &.{
            cli.FlagSpec{
                .name = "verbose",
                .short = 'v',
                .help = "Enable verbose output",
                .ftype = .bool,
            },
        },
    };

    const man = try cli.generateMan(&root, testing.allocator);
    defer testing.allocator.free(man);

    try testing.expect(std.mem.indexOf(u8, man, "--verbose") != null);
    try testing.expect(std.mem.indexOf(u8, man, "-v") != null);
}
```

## Testing Completion Output

```zig
test "bash completion includes subcommands" {
    const sub = cli.Command{
        .name = "serve",
        .summary = "Start server",
    };

    const root = cli.Command{
        .name = "myapp",
        .summary = "My application",
        .subcommands = &.{&sub},
    };

    const bash = try cli.generateCompletions(.bash, &root, testing.allocator);
    defer testing.allocator.free(bash);

    try testing.expect(std.mem.indexOf(u8, bash, "serve") != null);
}
```

## Integration Testing

For end-to-end testing, use `zig build run`:

```bash
# Test help output
zig build run -- --help

# Test with specific arguments
zig build run -- serve --port 3000

# Capture output for verification
output=$(zig build run -- --version 2>&1)
echo "$output" | grep -q "1.0.0"
```

## Testing Tips

1. **Test default values** - Verify defaults are applied correctly
2. **Test edge cases** - Empty input, max values, special characters
3. **Test error messages** - Ensure helpful error output
4. **Test flag combinations** - Conflicting flags, required flags with defaults
5. **Memory leak testing** - Use `testing.allocator` to catch leaks
6. **Use defer for cleanup** - Always `defer result.context.deinit()`
