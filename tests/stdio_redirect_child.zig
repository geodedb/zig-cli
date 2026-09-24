// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Helper child for tests/stdio_redirect.zig (SONNY-2608): makes several
//! separate writes to the Context stdout/stderr writers so the parent test
//! can check they append when the streams are redirected to regular files.

const std = @import("std");
const cli = @import("cli");

pub fn main(init: std.process.Init) !void {
    var ctx = cli.Context.init(init.gpa);
    defer ctx.deinit();

    try ctx.stdout.writeAll("{");
    try ctx.stdout.print("\"actions\":[{d},{d}]", .{ 1, 2 });
    try ctx.stdout.writeByte('}');
    try ctx.stdout.writeAll("\n");

    try ctx.stderr.writeAll("warn: ");
    try ctx.stderr.print("{s}", .{"first"});
    try ctx.stderr.writeByte('\n');
    try ctx.stderr.writeAll("warn: second\n");
}
