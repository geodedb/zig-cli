# Flag Validation Guide

This guide explains how to validate command-line flag values.

## Overview

Flag validation ensures user input meets requirements before command execution:

- Built-in validators (hostname, port, URL, email, etc.)
- Custom validation functions
- Flag groups (mutually exclusive, required together)
- Positional argument validators

## Built-in Validators

### Available Validators

```zig
const validate = @import("cli").validate;

// Network validators
validate.hostname  // Valid hostname format
validate.port      // Valid port number (1-65535)
validate.ip        // Valid IPv4 or IPv6 address
validate.ipv4      // Valid IPv4 address only
validate.ipv6      // Valid IPv6 address only
validate.url       // Valid URL format

// Format validators
validate.email     // Valid email format
validate.uuid      // Valid UUID format

// Path validators
validate.file_exists  // File must exist
validate.dir_exists   // Directory must exist
validate.path_exists  // File or directory must exist

// Numeric validators
validate.positive     // Positive number
validate.non_negative // Zero or positive
validate.range(1, 100) // Number in range
```

### Using Built-in Validators

```zig
const cli = @import("cli");

const cmd = cli.Command{
    .name = "server",
    .flags = &.{
        cli.FlagSpec{
            .name = "host",
            .help = "Server hostname",
            .ftype = .string,
            .validator = cli.validate.hostname,
        },
        cli.FlagSpec{
            .name = "port",
            .help = "Server port",
            .ftype = .int,
            .validator = cli.validate.port,
        },
        cli.FlagSpec{
            .name = "config",
            .help = "Config file",
            .ftype = .path,
            .validator = cli.validate.file_exists,
        },
    },
};
```

## Custom Validators

### Simple Validation

```zig
const cli = @import("cli");

fn validateProjectName(value: []const u8) ?[]const u8 {
    // Must start with letter
    if (value.len == 0 or !std.ascii.isAlphabetic(value[0])) {
        return "Project name must start with a letter";
    }

    // Only alphanumeric and hyphens
    for (value) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-') {
            return "Project name can only contain letters, numbers, and hyphens";
        }
    }

    // Length check
    if (value.len < 3 or value.len > 50) {
        return "Project name must be 3-50 characters";
    }

    return null; // Valid
}

const cmd = cli.Command{
    .flags = &.{
        cli.FlagSpec{
            .name = "name",
            .help = "Project name",
            .ftype = .string,
            .validator = validateProjectName,
        },
    },
};
```

### Validation with Context

For validators that need additional context:

```zig
fn createEnvValidator(allowed: []const []const u8) cli.Validator {
    return struct {
        fn validate(value: []const u8) ?[]const u8 {
            for (allowed) |env| {
                if (std.mem.eql(u8, value, env)) {
                    return null; // Valid
                }
            }
            return "Invalid environment. Allowed: dev, staging, prod";
        }
    }.validate;
}

const cmd = cli.Command{
    .flags = &.{
        cli.FlagSpec{
            .name = "env",
            .help = "Target environment",
            .ftype = .string,
            .validator = createEnvValidator(&.{ "dev", "staging", "prod" }),
        },
    },
};
```

## Flag Groups

### Mutually Exclusive

Only one flag from the group can be set:

```zig
const cmd = cli.Command{
    .name = "output",
    .flags = &.{
        cli.FlagSpec{ .name = "json", .ftype = .bool },
        cli.FlagSpec{ .name = "yaml", .ftype = .bool },
        cli.FlagSpec{ .name = "xml", .ftype = .bool },
    },
    .flag_groups = &.{
        cli.FlagGroup{
            .flags = &.{ "json", "yaml", "xml" },
            .rule = .mutually_exclusive,
        },
    },
};

// Valid:   --json
// Valid:   --yaml
// Invalid: --json --yaml (Error: --json and --yaml are mutually exclusive)
```

### Required Together

If one is set, all must be set:

```zig
const cmd = cli.Command{
    .name = "auth",
    .flags = &.{
        cli.FlagSpec{ .name = "username", .ftype = .string },
        cli.FlagSpec{ .name = "password", .ftype = .string },
    },
    .flag_groups = &.{
        cli.FlagGroup{
            .flags = &.{ "username", "password" },
            .rule = .required_together,
        },
    },
};

// Valid:   --username alice --password secret
// Valid:   (neither set)
// Invalid: --username alice (Error: --password is required when --username is set)
```

### One Required

At least one from the group must be set:

```zig
const cmd = cli.Command{
    .name = "input",
    .flags = &.{
        cli.FlagSpec{ .name = "file", .ftype = .path },
        cli.FlagSpec{ .name = "stdin", .ftype = .bool },
        cli.FlagSpec{ .name = "url", .ftype = .string },
    },
    .flag_groups = &.{
        cli.FlagGroup{
            .flags = &.{ "file", "stdin", "url" },
            .rule = .one_required,
        },
    },
};

// Valid:   --file data.txt
// Valid:   --stdin
// Valid:   --file data.txt --stdin (multiple allowed)
// Invalid: (none set) (Error: One of --file, --stdin, --url is required)
```

## Positional Argument Validators

### Exact Count

```zig
const cmd = cli.Command{
    .name = "copy",
    .args = .{
        .validator = cli.args.exact(2), // Exactly 2 args required
    },
};

// Valid:   copy source.txt dest.txt
// Invalid: copy source.txt (Error: Expected 2 arguments, got 1)
```

### Minimum Count

```zig
const cmd = cli.Command{
    .name = "cat",
    .args = .{
        .validator = cli.args.minimum(1), // At least 1 arg
    },
};

// Valid:   cat file1.txt file2.txt file3.txt
// Invalid: cat (Error: Expected at least 1 argument)
```

### Maximum Count

```zig
const cmd = cli.Command{
    .name = "diff",
    .args = .{
        .validator = cli.args.maximum(2),
    },
};

// Valid:   diff file1.txt file2.txt
// Invalid: diff a.txt b.txt c.txt (Error: Expected at most 2 arguments)
```

### Range

```zig
const cmd = cli.Command{
    .name = "merge",
    .args = .{
        .validator = cli.args.range(2, 10), // 2-10 args
    },
};
```

### Custom Positional Validator

```zig
fn validateFileArgs(args: []const []const u8) ?[]const u8 {
    for (args) |arg| {
        if (!std.mem.endsWith(u8, arg, ".txt")) {
            return "All files must have .txt extension";
        }
    }
    return null;
}

const cmd = cli.Command{
    .name = "process",
    .args = .{
        .validator = validateFileArgs,
    },
};
```

## Error Messages

### Default Error Messages

The library provides clear error messages:

```text
Error: Invalid value for --port: "99999"
  Port must be between 1 and 65535

Error: --json and --yaml are mutually exclusive

Error: --password is required when --username is set

Error: Expected 2 arguments, got 1
  Usage: copy <source> <destination>
```

### Custom Error Messages

```zig
fn validateEnv(value: []const u8) ?[]const u8 {
    const valid = &[_][]const u8{ "dev", "staging", "prod" };
    for (valid) |v| {
        if (std.mem.eql(u8, value, v)) return null;
    }
    // Return helpful error message
    return "Invalid environment. Valid values: dev, staging, prod";
}
```

## Validation Flow

1. **Parse flags** - Extract flag values from arguments
2. **Type validation** - Ensure value matches flag type (int, bool, etc.)
3. **Custom validation** - Run validator function if specified
4. **Flag groups** - Check group rules (mutually exclusive, etc.)
5. **Required flags** - Verify all required flags are set
6. **Positional args** - Validate argument count/content
7. **Execute command** - Only if all validation passes

## Best Practices

1. **Provide helpful errors** - Tell users exactly what's wrong
2. **Validate early** - Fail fast before expensive operations
3. **Use built-in validators** - They're well-tested
4. **Combine validators** - Chain multiple checks
5. **Document constraints** - Show valid values in help text
6. **Test edge cases** - Empty strings, special characters, boundaries

## Complete Example

```zig
const std = @import("std");
const cli = @import("cli");

// Custom validators
fn validateVersion(value: []const u8) ?[]const u8 {
    // Semantic versioning pattern: X.Y.Z
    var parts = std.mem.split(u8, value, ".");
    var count: usize = 0;

    while (parts.next()) |part| {
        count += 1;
        _ = std.fmt.parseInt(u32, part, 10) catch {
            return "Version must be in format X.Y.Z (e.g., 1.2.3)";
        };
    }

    if (count != 3) {
        return "Version must have exactly 3 parts (X.Y.Z)";
    }

    return null;
}

fn validateTag(value: []const u8) ?[]const u8 {
    if (value.len == 0) {
        return "Tag cannot be empty";
    }
    if (value.len > 128) {
        return "Tag cannot exceed 128 characters";
    }
    if (value[0] == '-') {
        return "Tag cannot start with a hyphen";
    }
    for (value) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '.') {
            return "Tag can only contain letters, numbers, hyphens, underscores, and dots";
        }
    }
    return null;
}

const deploy_cmd = cli.Command{
    .name = "deploy",
    .summary = "Deploy application to environment",
    .flags = &.{
        // Environment with built-in validation
        cli.FlagSpec{
            .name = "env",
            .short = 'e',
            .help = "Target environment (dev, staging, prod)",
            .ftype = .string,
            .required = true,
            .env = "DEPLOY_ENV",
        },

        // Version with custom validation
        cli.FlagSpec{
            .name = "version",
            .short = 'v',
            .help = "Version to deploy (X.Y.Z)",
            .ftype = .string,
            .validator = validateVersion,
        },

        // Tag with custom validation
        cli.FlagSpec{
            .name = "tag",
            .short = 't',
            .help = "Docker image tag",
            .ftype = .string,
            .validator = validateTag,
        },

        // Port with built-in validation
        cli.FlagSpec{
            .name = "port",
            .short = 'p',
            .help = "Service port",
            .ftype = .int,
            .default_str = "8080",
            .validator = cli.validate.port,
        },

        // Replicas with range validation
        cli.FlagSpec{
            .name = "replicas",
            .short = 'r',
            .help = "Number of replicas (1-10)",
            .ftype = .int,
            .default_str = "3",
            .validator = cli.validate.range(1, 10),
        },

        // Config file with existence check
        cli.FlagSpec{
            .name = "config",
            .short = 'c',
            .help = "Configuration file",
            .ftype = .path,
            .validator = cli.validate.file_exists,
        },

        // Mutually exclusive output formats
        cli.FlagSpec{
            .name = "json",
            .help = "Output in JSON format",
            .ftype = .bool,
        },
        cli.FlagSpec{
            .name = "quiet",
            .short = 'q',
            .help = "Suppress output",
            .ftype = .bool,
        },

        // Authentication flags (required together)
        cli.FlagSpec{
            .name = "username",
            .short = 'u',
            .help = "API username",
            .ftype = .string,
        },
        cli.FlagSpec{
            .name = "password",
            .help = "API password",
            .ftype = .string,
            .secret = true, // Read from file or stdin only
        },
    },

    .flag_groups = &.{
        // Can't use both --json and --quiet
        cli.FlagGroup{
            .flags = &.{ "json", "quiet" },
            .rule = .mutually_exclusive,
        },
        // If username is set, password must be too
        cli.FlagGroup{
            .flags = &.{ "username", "password" },
            .rule = .required_together,
        },
    },

    .args = .{
        // Exactly one service name required
        .validator = cli.args.exact(1),
    },

    .run = runDeploy,
};

fn runDeploy(ctx: *cli.Context) !void {
    const service = ctx.positionals()[0];
    const env = ctx.getString("env").?;
    const version = ctx.getString("version") orelse "latest";
    const replicas = ctx.getInt("replicas") orelse 3;

    try ctx.stdout.print("Deploying {s} v{s} to {s} with {d} replicas\n", .{
        service, version, env, replicas,
    });
}
```
