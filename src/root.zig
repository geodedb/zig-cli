// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # Zig CLI Library
//!
//! A comprehensive command-line interface and configuration management library
//! for Zig applications, providing Cobra/Viper-class features.
//!
//! ## Features
//!
//! ### CLI Features
//! - Nested command trees with subcommands
//! - Type-safe flag parsing (bool, int, float, string, path, arrays)
//! - Automatic help generation with examples-first approach
//! - Shell completion generation (bash, zsh, fish, PowerShell)
//! - Man page generation
//! - Error messages with typo suggestions
//!
//! ### Config Features
//! - Multiple format support (TOML, JSON, YAML)
//! - XDG Base Directory compliance
//! - Precedence: flags > env > project > user > system > defaults
//! - Secret handling (file/stdin only, never flags/env)
//! - Provenance tracking
//!
//! ### Terminal Features
//! - TTY detection
//! - ANSI color with NO_COLOR compliance
//! - Pager integration
//! - Progress indicators (spinners, bars)
//!
//! ## Quick Start
//!
//! ```zig
//! const zig_cli = @import("zig_cli");
//! const cli = zig_cli.cli;
//!
//! const root_cmd = cli.Command{
//!     .name = "myapp",
//!     .summary = "My application",
//!     .run = myRun,
//! };
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!
//!     const args = try std.process.argsAlloc(gpa.allocator());
//!     defer std.process.argsFree(gpa.allocator(), args);
//!
//!     const exit_code = try cli.run(&root_cmd, args, gpa.allocator());
//!     std.process.exit(exit_code);
//! }
//! ```

const std = @import("std");

pub const cli = @import("cli.zig");
pub const config = @import("config.zig");
pub const parallel = @import("parallel.zig");
pub const term = @import("term.zig");
pub const util = @import("util.zig");
pub const signal = @import("signal.zig");
pub const prompt = @import("prompt.zig");

/// Library version (single-sourced from build.zig.zon via build options)
pub const version = @import("build_options").version;

// ============================================================================
// Convenience Re-exports
// ============================================================================

// CLI types — command tree, flag specs, parsing, and shell-completion helpers
pub const Command = cli.Command;
pub const Context = cli.Context;
pub const FlagSpec = cli.FlagSpec;
pub const FlagType = cli.FlagType;
pub const SecretPolicy = cli.SecretPolicy;
pub const ParseError = cli.ParseError;
pub const run = cli.run;
pub const generateCompletions = cli.generateCompletions;
pub const generateMan = cli.generateMan;

// Config types — multi-format loader (TOML/JSON/YAML) with XDG compliance
pub const Loader = config.Loader;
pub const LoadOptions = config.LoadOptions;
pub const Source = config.Source;
pub const load = config.load;

// Terminal types — color rendering, spinners, and progress bars
pub const Color = term.Color;
pub const Progress = term.Progress;
pub const ProgressBar = term.ProgressBar;

// Utility types — fuzzy suggestions and process exit codes
pub const suggestClosest = util.suggestClosest;
pub const ExitCode = util.ExitCode;

// Signal handling — flag-and-poll pattern; callbacks run in normal context
pub const Signal = signal.Signal;
pub const installSignalHandlers = signal.install;
pub const wasInterrupted = signal.wasInterrupted;
pub const shouldShutdown = signal.shouldShutdown;
pub const onCleanup = signal.onCleanup;

// Interactive prompts — text, password, confirmation, single/multi-select
pub const PromptError = prompt.PromptError;
pub const InputConfig = prompt.InputConfig;
pub const promptInput = prompt.input;
pub const promptPassword = prompt.password;
pub const promptFreeSecret = prompt.freeSecret;
pub const promptConfirm = prompt.confirm;
pub const promptSelect = prompt.select;
pub const promptMultiSelect = prompt.multiSelect;

// ============================================================================
// Tests
// ============================================================================

test {
    _ = cli;
    _ = config;
    _ = parallel;
    _ = term;
    _ = util;
    _ = signal;
    _ = prompt;
}

test "version is a semantic version" {
    _ = try std.SemanticVersion.parse(version);
}

test "parallel: forEach is exposed via root and works end-to-end" {
    parallel.initPool(.{ .worker_count = 2 });
    defer parallel.deinitPool();

    const inputs = [_]u32{ 1, 2, 3, 4 };
    var outputs: [4]u64 = undefined;

    const Double = struct {
        fn apply(x: u32) u64 {
            return @as(u64, x) * 2;
        }
    };
    parallel.forEach(u32, u64, &inputs, &outputs, Double.apply);

    try std.testing.expectEqual(@as(u64, 2), outputs[0]);
    try std.testing.expectEqual(@as(u64, 4), outputs[1]);
    try std.testing.expectEqual(@as(u64, 6), outputs[2]);
    try std.testing.expectEqual(@as(u64, 8), outputs[3]);
}

test "parallel: map is exposed via root and works end-to-end" {
    const inputs = [_]u32{ 10, 20, 30, 40 };
    const results = try parallel.map(u32, u64, std.testing.allocator, &inputs, struct {
        fn triple(x: u32) u64 {
            return @as(u64, x) * 3;
        }
    }.triple);
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(u64, 30), results[0]);
    try std.testing.expectEqual(@as(u64, 60), results[1]);
    try std.testing.expectEqual(@as(u64, 90), results[2]);
    try std.testing.expectEqual(@as(u64, 120), results[3]);
}
