# Configuration Precedence Guide

This guide explains how zig-cli resolves configuration values from multiple sources.

## Precedence Order

From highest to lowest priority:

1. **Command-line flags** (`--port 8080`)
2. **Environment variables** (`MYAPP_PORT=8080`)
3. **Project config** (`./.myapp.toml` or `./myapp.toml`)
4. **User config** (`~/.config/myapp/config.toml`)
5. **System config** (`/etc/myapp/config.toml`)
6. **Default values** (defined in FlagSpec)

## Example Scenario

```text
/etc/myapp/config.toml:
  port = 80

~/.config/myapp/config.toml:
  port = 3000
  host = "0.0.0.0"

./.myapp.toml:
  debug = true

Environment:
  MYAPP_HOST=localhost

Command line:
  myapp --port 8080
```

Result:

- `port = 8080` (from flag)
- `host = "localhost"` (from env, overrides user config)
- `debug = true` (from project config)

## Setting Up Environment Variables

```zig
const root_cmd = cli.Command{
    .name = "myapp",
    .summary = "My application",
    .flags = &.{
        cli.FlagSpec{
            .name = "port",
            .short = 'p',
            .help = "Port to listen on",
            .ftype = .int,
            .env = "MYAPP_PORT",  // Read from MYAPP_PORT env var
            .default_str = "8080",
        },
        cli.FlagSpec{
            .name = "host",
            .help = "Host to bind to",
            .ftype = .string,
            .env = "MYAPP_HOST",
            .default_str = "localhost",
        },
    },
};
```

## Loading Config Files

```zig
const config = @import("cli").config;

// Load from standard locations
const loader = config.Loader.init(allocator, "myapp");
const cfg = try loader.load();
defer cfg.deinit();

// Or load a specific file
var value = try config.parseFile(allocator, "config.yaml");
defer value.deinit();
```

## Provenance Tracking

Track where each value came from:

```zig
var tracker = config.ProvenanceTracker.init(allocator);
defer tracker.deinit();

try tracker.set("port", "80", .system, "/etc/myapp/config.toml");
try tracker.set("port", "3000", .user, "~/.config/myapp/config.toml");

const val = tracker.get("port").?;
std.debug.print("port = {s} (from {s})\n", .{val.value, @tagName(val.source)});
// port = 3000 (from user)
```

## Format Support

The library auto-detects format from file extension:

- `.toml` - TOML format
- `.yaml`, `.yml` - YAML format
- `.json` - JSON format

```zig
const format = config.Format.fromExtension("config.yaml");
// format == .yaml
```

## XDG Directory Standards

zig-cli follows XDG Base Directory Specification:

| Purpose | Linux | macOS |
|---------|-------|-------|
| User Config | `~/.config/APP` | `~/.config/APP` |
| User Data | `~/.local/share/APP` | `~/.local/share/APP` |
| User Cache | `~/.cache/APP` | `~/.cache/APP` |
| System Config | `/etc/APP` | `/etc/APP` |

```zig
const config_dir = try config.xdg.getConfigDir("myapp", allocator);
// "/home/user/.config/myapp"
```

## Best Practices

1. **Always provide defaults** for non-required flags
2. **Use environment variables** for deployment configuration
3. **Document config file locations** in your README
4. **Validate early** using the validation module
5. **Log provenance** in verbose mode for debugging
