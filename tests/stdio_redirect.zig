// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Regression test for SONNY-2608: a CLI whose stdout/stderr are redirected
//! to regular files (`app > out 2> err`) must append each write rather than
//! overwrite from offset 0. Pipes do not show the bug, so the child is run
//! with real files as its stdio.

const std = @import("std");
const options = @import("stdio_redirect_options");

test "Context stdout/stderr append when redirected to regular files" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const out = try tmp.dir.createFile(io, "out.txt", .{});
        defer out.close(io);
        const err = try tmp.dir.createFile(io, "err.txt", .{});
        defer err.close(io);

        var child = try std.process.spawn(io, .{
            .argv = &.{options.child_path},
            .stdin = .ignore,
            .stdout = .{ .file = out },
            .stderr = .{ .file = err },
        });
        const term = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }

    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "{\"actions\":[1,2]}\n",
        try tmp.dir.readFile(io, "out.txt", &buf),
    );
    try std.testing.expectEqualStrings(
        "warn: first\nwarn: second\n",
        try tmp.dir.readFile(io, "err.txt", &buf),
    );
}
