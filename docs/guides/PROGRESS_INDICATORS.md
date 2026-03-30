# Progress Indicators Guide

This guide explains how to use spinners and progress bars for long-running operations.

## Overview

The CLI library provides two progress indicator types:

- **Spinner**: Animated indicator for indeterminate operations
- **Progress Bar**: Bar with percentage for determinate operations

## Spinner

Use spinners when you don't know how long an operation will take:

```zig
const progress = @import("cli").progress;

pub fn downloadFiles(ctx: *cli.Context) !void {
    var spinner = progress.Spinner.init(ctx.stdout, .{
        .message = "Downloading files...",
        .style = .dots,  // Animation style
    });

    spinner.start();
    defer spinner.stop();

    // Perform long operation
    try performDownload();

    spinner.succeed("Download complete!");
}
```

### Spinner Styles

```zig
// Available spinner styles
const style: progress.SpinnerStyle = .dots;      // ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
const style: progress.SpinnerStyle = .line;      // - \ | /
const style: progress.SpinnerStyle = .arrow;     // ▹▹▹▹▹ ▸▹▹▹▹ ▹▸▹▹▹
const style: progress.SpinnerStyle = .pulse;     // █▓▒░ ▓▒░█ ▒░█▓ ░█▓▒
const style: progress.SpinnerStyle = .bounce;    // [=   ] [ =  ] [  = ]
```

### Updating Spinner Message

```zig
var spinner = progress.Spinner.init(ctx.stdout, .{
    .message = "Starting...",
});

spinner.start();

spinner.setMessage("Connecting to server...");
try connect();

spinner.setMessage("Authenticating...");
try authenticate();

spinner.setMessage("Downloading data...");
try download();

spinner.succeed("All done!");
```

### Spinner States

```zig
// Success - shows checkmark
spinner.succeed("Operation completed!");

// Failure - shows X
spinner.fail("Operation failed!");

// Warning - shows warning symbol
spinner.warn("Completed with warnings");

// Info - shows info symbol
spinner.info("Here's some information");

// Just stop without message
spinner.stop();
```

## Progress Bar

Use progress bars when you know the total amount of work:

```zig
pub fn processFiles(ctx: *cli.Context, files: []const []const u8) !void {
    var bar = progress.ProgressBar.init(ctx.stdout, .{
        .total = files.len,
        .width = 40,
        .format = "[{bar}] {percent}% ({current}/{total})",
    });

    bar.start();
    defer bar.finish();

    for (files, 0..) |file, i| {
        try processFile(file);
        bar.update(i + 1);
    }
}
```

### Progress Bar Formats

```zig
// Default format
.format = "[{bar}] {percent}%"
// Output: [████████████░░░░░░░░] 60%

// With counts
.format = "[{bar}] {current}/{total}"
// Output: [████████████░░░░░░░░] 600/1000

// With message
.format = "{message} [{bar}] {percent}%"
// Output: Downloading... [████████░░░░░░░░░░░░] 40%

// Minimal
.format = "{percent}%"
// Output: 75%
```

### Custom Bar Characters

```zig
var bar = progress.ProgressBar.init(ctx.stdout, .{
    .total = 100,
    .filled_char = '=',
    .empty_char = ' ',
    .bracket_open = '[',
    .bracket_close = ']',
});
// Output: [========            ]
```

### Progress Bar with ETA

```zig
var bar = progress.ProgressBar.init(ctx.stdout, .{
    .total = total_bytes,
    .format = "[{bar}] {percent}% ETA: {eta}",
    .show_eta = true,
});

bar.start();

for (chunks) |chunk| {
    try downloadChunk(chunk);
    bar.increment(chunk.len);
}

bar.finish();
```

## Non-TTY Behavior

Progress indicators detect non-TTY output and degrade gracefully:

```zig
var spinner = progress.Spinner.init(ctx.stdout, .{
    .message = "Processing...",
});

// In a TTY: Shows animated spinner
// In a pipe: Prints "Processing..." once and final status

spinner.start();
try process();
spinner.succeed("Done!");
// Non-TTY output:
// Processing...
// Done!
```

## Quiet Mode

Respect the `--quiet` flag:

```zig
if (!ctx.quiet) {
    var spinner = progress.Spinner.init(ctx.stdout, .{
        .message = "Working...",
    });
    spinner.start();
    defer spinner.stop();
}

try performWork();
```

## Nested Progress

For operations with sub-tasks:

```zig
pub fn buildProject(ctx: *cli.Context) !void {
    const phases = &[_][]const u8{ "compile", "link", "package" };

    var main_bar = progress.ProgressBar.init(ctx.stdout, .{
        .total = phases.len,
        .format = "Building: [{bar}] {current}/{total}",
    });

    main_bar.start();

    for (phases, 0..) |phase, i| {
        var spinner = progress.Spinner.init(ctx.stdout, .{
            .message = try std.fmt.allocPrint(
                ctx.allocator,
                "  {s}...",
                .{phase}
            ),
        });

        spinner.start();
        try runPhase(phase);
        spinner.succeed(try std.fmt.allocPrint(
            ctx.allocator,
            "  {s} complete",
            .{phase}
        ));

        main_bar.update(i + 1);
    }

    main_bar.finish();
}
```

## Concurrent Operations

`ProgressBar` is thread-safe: multiple threads can call `update()` and
`increment()` concurrently. The current value uses atomic operations
and render output is mutex-protected.

```zig
const MAX_THREADS = 8;

pub fn downloadAll(urls: []const []const u8) !void {
    var bar = progress.ProgressBar.init(urls.len, "Downloading");

    var threads: [MAX_THREADS]std.Thread = undefined;
    const count = @min(urls.len, MAX_THREADS);
    for (urls[0..count], 0..) |url, i| {
        threads[i] = try std.Thread.spawn(.{}, downloadOne, .{
            url, &bar,
        });
    }

    for (threads[0..count]) |t| {
        t.join();
    }

    bar.finish();
}

fn downloadOne(
    url: []const u8,
    bar: *progress.ProgressBar,
) void {
    download(url) catch return;
    // Thread-safe: increment() uses atomic counter + mutex-protected render
    bar.increment();
}
```

## Best Practices

1. **Always call finish/stop** - Use defer to ensure cleanup
2. **Check TTY status** - Degrade gracefully for pipes
3. **Respect quiet mode** - Honor `--quiet` flag
4. **Use spinners for indeterminate** - When you don't know the total
5. **Use progress bars for determinate** - When you know the total
6. **Update reasonably** - Don't update too frequently (every 100ms is good)
7. **Handle Ctrl+C** - Stop progress on interruption

## Complete Example

```zig
const std = @import("std");
const cli = @import("cli");
const progress = cli.progress;

fn deployProject(ctx: *cli.Context) !void {
    // Skip progress if quiet or non-interactive
    const show_progress = !ctx.quiet and cli.terminal.isTty(ctx.stdout);

    var spinner: ?progress.Spinner = null;
    if (show_progress) {
        spinner = progress.Spinner.init(ctx.stdout, .{
            .message = "Preparing deployment...",
            .style = .dots,
        });
        spinner.?.start();
    }

    // Build phase
    if (spinner) |*s| s.setMessage("Building project...");
    try buildProject();

    // Upload phase with progress bar
    const files = try collectFiles();

    if (spinner) |*s| s.stop();

    if (show_progress) {
        var bar = progress.ProgressBar.init(ctx.stdout, .{
            .total = files.len,
            .format = "Uploading: [{bar}] {percent}% ({current}/{total})",
        });
        bar.start();
        defer bar.finish();

        for (files, 0..) |file, i| {
            try uploadFile(file);
            bar.update(i + 1);
        }
    } else {
        for (files) |file| {
            try uploadFile(file);
        }
    }

    // Finalize
    if (show_progress) {
        var final_spinner = progress.Spinner.init(ctx.stdout, .{
            .message = "Finalizing...",
        });
        final_spinner.start();
        try finalize();
        final_spinner.succeed("Deployment complete!");
    } else {
        try finalize();
        try ctx.stdout.print("Deployment complete.\n", .{});
    }
}
```
