// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Help: Shared Helpers
//!
//! Helpers used by two or more format-specific renderers in the help subsystem
//! (`help/text.zig`, `help/markdown.zig`).
//!
//! Do NOT put format-specific escapers here — each renderer's escaper is
//! intentionally distinct (security finding NS-060) and must stay co-located
//! with its renderer.

const std = @import("std");
const mem = std.mem;

const command = @import("../command.zig");
const Command = command.Command;

/// Collect unique group names from a command's visible subcommands.
/// Returns the number of unique groups found.
///
/// **Limit:** At most 32 unique groups are tracked. Commands with more
/// than 32 groups will have excess groups silently omitted from output.
///
/// Used by the text renderer (`help/text.zig`) and the Markdown generator
/// (`help/markdown.zig`).
// Internal to the help subsystem; pub for cross-file use within the module.
pub fn collectUniqueGroups(subcommands: []const *const Command, groups: *[32][]const u8) usize {
    var count: usize = 0;
    for (subcommands) |subcmd| {
        if (subcmd.hidden) continue;
        var found = false;
        for (groups[0..count]) |g| {
            if (mem.eql(u8, g, subcmd.group)) {
                found = true;
                break;
            }
        }
        if (!found and count < groups.len) {
            groups[count] = subcmd.group;
            count += 1;
        }
    }
    return count;
}
