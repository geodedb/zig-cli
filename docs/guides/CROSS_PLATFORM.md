# Cross-Platform Development Guide

This guide covers platform-specific considerations when building CLIs with zig-cli.

## Supported Platforms

| Platform | Architecture | Build | Test |
|----------|-------------|-------|------|
| Linux | x86_64 | Native | Native |
| Linux | ARM64 | Native | Native |
| Linux | ARM | Cross | Cross |
| Linux | RISC-V | Cross | Cross |
| macOS | ARM64 (M1/M2) | Native | Native |
| macOS | x86_64 | Cross | Native |
| Windows | x86_64 | Native | Native |
| Windows | ARM64 | Cross | Cross |

## Cross-Compilation

Zig makes cross-compilation simple:

```bash
# Linux ARM64
zig build -Dtarget=aarch64-linux-gnu

# Windows x86_64
zig build -Dtarget=x86_64-windows-msvc

# macOS x86_64 (from Linux)
zig build -Dtarget=x86_64-macos
```

## Platform Detection

```zig
const builtin = @import("builtin");

if (builtin.os.tag == .windows) {
    // Windows-specific code
} else if (builtin.os.tag == .macos) {
    // macOS-specific code
} else {
    // Linux/Unix code
}
```

## Terminal Handling

### TTY Detection

Works across all platforms:

```zig
const term = @import("cli").term;

if (term.isStdoutTty()) {
    // Interactive terminal
} else {
    // Piped or redirected
}
```

### Terminal Size

```zig
if (term.getTermSize()) |size| {
    std.debug.print("{}x{}\n", .{size.cols, size.rows});
}
```

- **Linux/macOS**: Uses `ioctl(TIOCGWINSZ)`
- **Windows**: Uses `GetConsoleScreenBufferInfo`

### Color Support

zig-cli respects platform conventions:

```zig
const ctx = cli.Context.init(allocator);

if (ctx.useColor()) {
    // ANSI colors are supported
}
```

Color is disabled when:
- `NO_COLOR` environment variable is set
- `TERM=dumb`
- Not a TTY
- `--no-color` flag passed
- `--plain` flag passed

## Signal Handling

### POSIX (Linux/macOS)

```zig
const signal = @import("cli").signal;

try signal.install(.{
    .handle_interrupt = true,  // SIGINT
    .handle_terminate = true,  // SIGTERM
});
```

### Windows

On Windows, the signal module handles:
- `CTRL_C_EVENT` (Ctrl+C)
- `CTRL_BREAK_EVENT` (Ctrl+Break)
- `CTRL_CLOSE_EVENT` (console close)

The same API works:

```zig
if (signal.wasInterrupted()) {
    // User pressed Ctrl+C
}
```

## Path Handling

### XDG Directories

```zig
const config = @import("cli").config;

const config_dir = try config.xdg.getConfigDir("myapp", allocator);
```

| Platform | Result |
|----------|--------|
| Linux | `~/.config/myapp` |
| macOS | `~/.config/myapp` |
| Windows | Not yet supported (use `%APPDATA%`) |

### Path Separators

Use `std.fs.path` for cross-platform paths:

```zig
const path = std.fs.path.join(allocator, &.{"dir", "file.txt"});
// Linux: "dir/file.txt"
// Windows: "dir\\file.txt"
```

## Environment Variables

### POSIX

```zig
const value = std.posix.getenv("MY_VAR");
```

### Windows

Use `std.process.getEnvVarOwned` for cross-platform:

```zig
const value = std.process.getEnvVarOwned(allocator, "MY_VAR") catch null;
if (value) |v| {
    defer allocator.free(v);
    // use v
}
```

## File Permissions

### POSIX

```zig
const stat = try std.fs.cwd().statFile("config.toml");
const mode = stat.mode;
```

### Windows

Windows doesn't use Unix-style permissions. For cross-platform code:

```zig
if (builtin.os.tag != .windows) {
    // Check/set permissions
}
```

## CI/CD Configuration

Example GitLab CI for cross-platform testing:

```yaml
test-linux:
  stage: test
  script:
    - zig build test

test-macos:
  stage: test
  tags:
    - saas-macos-medium-m1
  script:
    - zig build test

test-windows:
  stage: test
  tags:
    - saas-windows-medium-amd64
  script:
    - zig build test

cross-compile:
  stage: build
  script:
    - zig build -Dtarget=aarch64-linux-gnu
    - zig build -Dtarget=x86_64-windows-msvc
    - zig build -Dtarget=x86_64-macos
```

## Best Practices

1. **Use zig's cross-platform abstractions** (`std.fs`, `std.process`)
2. **Test on all target platforms** (even if just in CI)
3. **Handle missing features gracefully** (fallback values)
4. **Document platform-specific behavior** in your README
5. **Avoid shell dependencies** (use Zig instead of shell commands)
6. **Use `builtin.os.tag`** for platform-specific code paths
