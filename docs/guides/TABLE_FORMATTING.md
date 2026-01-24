# Table Formatting Guide

This guide explains how to display structured data in tables.

## Overview

The table formatter provides:

- Multiple border styles (ASCII, Unicode, minimal, none)
- Column alignment (left, center, right)
- Automatic column width calculation
- Header rows
- Row striping
- Maximum column widths with truncation

## Basic Usage

```zig
const table = @import("cli").table;

pub fn listUsers(ctx: *cli.Context) !void {
    var t = table.Table.init(ctx.allocator, .{
        .columns = &.{
            .{ .header = "ID", .alignment = .right },
            .{ .header = "Name", .alignment = .left },
            .{ .header = "Email", .alignment = .left },
        },
    });
    defer t.deinit();

    try t.addRow(&.{ "1", "Alice", "alice@example.com" });
    try t.addRow(&.{ "2", "Bob", "bob@example.com" });
    try t.addRow(&.{ "3", "Charlie", "charlie@example.com" });

    try t.render(ctx.stdout);
}
```

Output:
```
+----+---------+---------------------+
| ID | Name    | Email               |
+----+---------+---------------------+
|  1 | Alice   | alice@example.com   |
|  2 | Bob     | bob@example.com     |
|  3 | Charlie | charlie@example.com |
+----+---------+---------------------+
```

## Border Styles

### ASCII (Default)

```zig
var t = table.Table.init(allocator, .{
    .style = .ascii,
    // ...
});
```
```
+----+---------+
| ID | Name    |
+----+---------+
|  1 | Alice   |
|  2 | Bob     |
+----+---------+
```

### Unicode

```zig
var t = table.Table.init(allocator, .{
    .style = .unicode,
    // ...
});
```
```
┌────┬─────────┐
│ ID │ Name    │
├────┼─────────┤
│  1 │ Alice   │
│  2 │ Bob     │
└────┴─────────┘
```

### Unicode Double

```zig
var t = table.Table.init(allocator, .{
    .style = .unicode_double,
    // ...
});
```
```
╔════╦═════════╗
║ ID ║ Name    ║
╠════╬═════════╣
║  1 ║ Alice   ║
║  2 ║ Bob     ║
╚════╩═════════╝
```

### Minimal

```zig
var t = table.Table.init(allocator, .{
    .style = .minimal,
    // ...
});
```
```
ID  Name
--  ----
 1  Alice
 2  Bob
```

### None

```zig
var t = table.Table.init(allocator, .{
    .style = .none,
    // ...
});
```
```
ID  Name
 1  Alice
 2  Bob
```

## Column Options

### Alignment

```zig
.columns = &.{
    .{ .header = "Count", .alignment = .right },   // Right-aligned numbers
    .{ .header = "Status", .alignment = .center }, // Centered text
    .{ .header = "Message", .alignment = .left },  // Left-aligned (default)
},
```

### Maximum Width

```zig
.columns = &.{
    .{ .header = "Description", .max_width = 40 },
},
```

Long text will be truncated with "...":
```
| Description                              |
| This is a very long description that ... |
```

### Minimum Width

```zig
.columns = &.{
    .{ .header = "ID", .min_width = 6 },
},
```

### Custom Padding

```zig
var t = table.Table.init(allocator, .{
    .padding = 2,  // Spaces on each side of cell content
    // ...
});
```

## Headers

### With Headers (Default)

```zig
var t = table.Table.init(allocator, .{
    .show_header = true,  // Default
    .columns = &.{
        .{ .header = "Name" },
        .{ .header = "Value" },
    },
});
```

### Without Headers

```zig
var t = table.Table.init(allocator, .{
    .show_header = false,
    .columns = &.{
        .{ .alignment = .left },
        .{ .alignment = .right },
    },
});
```

## Adding Data

### Row by Row

```zig
try t.addRow(&.{ "value1", "value2", "value3" });
try t.addRow(&.{ "value4", "value5", "value6" });
```

### From Structs

```zig
const User = struct {
    id: u32,
    name: []const u8,
    active: bool,
};

const users = [_]User{
    .{ .id = 1, .name = "Alice", .active = true },
    .{ .id = 2, .name = "Bob", .active = false },
};

for (users) |user| {
    try t.addRow(&.{
        try std.fmt.allocPrint(allocator, "{d}", .{user.id}),
        user.name,
        if (user.active) "Yes" else "No",
    });
}
```

### From Iterator

```zig
var iter = data.iterator();
while (iter.next()) |item| {
    try t.addRow(&.{ item.key, item.value });
}
```

## Styling

### Row Striping

```zig
var t = table.Table.init(allocator, .{
    .striped = true,  // Alternate row colors
    // ...
});
```

### Colors

```zig
const colors = @import("cli").colors;

// Add colored values
try t.addRow(&.{
    colors.green("SUCCESS"),
    "Operation completed",
});

try t.addRow(&.{
    colors.red("ERROR"),
    "Operation failed",
});
```

## JSON Output

Support `--json` flag for machine-readable output:

```zig
pub fn listItems(ctx: *cli.Context) !void {
    const items = try fetchItems();

    if (ctx.json) {
        // Output as JSON array
        try std.json.stringify(items, .{}, ctx.stdout);
        try ctx.stdout.writeAll("\n");
    } else {
        // Output as table
        var t = table.Table.init(ctx.allocator, .{
            .columns = &.{
                .{ .header = "ID" },
                .{ .header = "Name" },
            },
        });
        defer t.deinit();

        for (items) |item| {
            try t.addRow(&.{ item.id, item.name });
        }

        try t.render(ctx.stdout);
    }
}
```

## Plain Text Output

For `--plain` flag, use minimal style:

```zig
pub fn listItems(ctx: *cli.Context) !void {
    const style = if (ctx.plain) table.Style.none else table.Style.ascii;

    var t = table.Table.init(ctx.allocator, .{
        .style = style,
        // ...
    });
    // ...
}
```

## Sorting

Sort before rendering:

```zig
var t = table.Table.init(allocator, .{ ... });

// Add rows...

// Sort by column index
t.sortByColumn(0, .ascending);
// or
t.sortByColumn(2, .descending);

try t.render(ctx.stdout);
```

## Best Practices

1. **Use right alignment for numbers** - Easier to compare
2. **Set max_width for variable content** - Prevent table overflow
3. **Support --json flag** - For machine parsing
4. **Support --plain flag** - For piping to other tools
5. **Use consistent column order** - Users expect predictable output
6. **Include headers** - Unless output is for parsing
7. **Sort by meaningful column** - Usually ID or name

## Complete Example

```zig
const std = @import("std");
const cli = @import("cli");
const table = cli.table;

const ProcessInfo = struct {
    pid: u32,
    name: []const u8,
    cpu: f32,
    memory: u64,
    status: []const u8,
};

fn listProcesses(ctx: *cli.Context) !void {
    const processes = try getProcesses();

    // JSON output
    if (ctx.json) {
        try std.json.stringify(processes, .{}, ctx.stdout);
        try ctx.stdout.writeAll("\n");
        return;
    }

    // Determine style
    const style = blk: {
        if (ctx.plain) break :blk table.Style.none;
        if (ctx.useColor()) break :blk table.Style.unicode;
        break :blk table.Style.ascii;
    };

    // Create table
    var t = table.Table.init(ctx.allocator, .{
        .style = style,
        .striped = ctx.useColor(),
        .columns = &.{
            .{ .header = "PID", .alignment = .right, .min_width = 6 },
            .{ .header = "Name", .alignment = .left, .max_width = 20 },
            .{ .header = "CPU%", .alignment = .right },
            .{ .header = "Memory", .alignment = .right },
            .{ .header = "Status", .alignment = .center },
        },
    });
    defer t.deinit();

    // Add rows
    for (processes) |proc| {
        const status_colored = switch (proc.status[0]) {
            'R' => cli.colors.green(proc.status),
            'S' => cli.colors.yellow(proc.status),
            'Z' => cli.colors.red(proc.status),
            else => proc.status,
        };

        try t.addRow(&.{
            try std.fmt.allocPrint(ctx.allocator, "{d}", .{proc.pid}),
            proc.name,
            try std.fmt.allocPrint(ctx.allocator, "{d:.1}", .{proc.cpu}),
            try formatBytes(ctx.allocator, proc.memory),
            if (ctx.useColor()) status_colored else proc.status,
        });
    }

    // Sort by CPU descending
    t.sortByColumn(2, .descending);

    // Render
    try t.render(ctx.stdout);

    // Summary
    if (!ctx.quiet) {
        try ctx.stdout.print("\nTotal: {d} processes\n", .{processes.len});
    }
}

fn formatBytes(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var size: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (size >= 1024 and unit_idx < units.len - 1) {
        size /= 1024;
        unit_idx += 1;
    }

    return std.fmt.allocPrint(allocator, "{d:.1} {s}", .{ size, units[unit_idx] });
}
```
