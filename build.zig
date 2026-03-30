// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ========================================================================
    // External Dependencies
    // ========================================================================

    const use_config = b.option(bool, "config", "Use internal config dependency") orelse true;
    const ext_config_mod: ?*std.Build.Module = if (use_config) blk: {
        const config_dep = b.dependency("config", .{
            .target = target,
            .optimize = optimize,
            .spice = false,
        });
        break :blk config_dep.module("config");
    } else null;

    // Spice: optional heartbeat-scheduled parallelism
    const enable_spice = b.option(bool, "spice", "Enable spice-based parallelism") orelse true;

    const spice_mod: ?*std.Build.Module = if (enable_spice) blk: {
        const spice_dep = b.dependency("spice", .{
            .target = target,
            .optimize = optimize,
        });
        break :blk spice_dep.module("spice");
    } else null;

    // Build options (enable_spice flag for scale-bench and parallel module)
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_spice", enable_spice);
    const build_options_mod = build_options.createModule();

    // ========================================================================
    // Define Library Modules
    // ========================================================================
    //
    // Module organization follows Cobra/Viper patterns:
    // - cli: Command-line parsing, help, completions
    // - config: Configuration loading with XDG, precedence, secrets (from external lib)
    // - term: Terminal utilities (TTY, color, pager, progress)
    // - util: Common utilities (errors, suggestions, text, fs)

    // CLI Module
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Config Module (wrapper around external config library)
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (ext_config_mod) |m| config_mod.addImport("config", m);

    // Terminal Module
    const term_mod = b.addModule("term", .{
        .root_source_file = b.path("src/term.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Utility Module
    const util_mod = b.addModule("util", .{
        .root_source_file = b.path("src/util.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Parallel Module: optional spice-based parallelism
    const parallel_mod: ?*std.Build.Module = if (enable_spice) blk: {
        break :blk b.addModule("parallel", .{
        .root_source_file = b.path("src/parallel.zig"),
        .target = target,
        .optimize = optimize,
    });
    } else null;
    if (parallel_mod) |pm| { if (spice_mod) |sm| pm.addImport("spice", sm); }

    // Root Module: Public API
    _ = b.addModule("zig_cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // Unit Tests
    // ========================================================================

    // CLI module tests
    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    // Config module tests
    const config_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (ext_config_mod) |m| config_tests_mod.addImport("config", m);
    const config_tests = b.addTest(.{
        .root_module = config_tests_mod,
    });
    const run_config_tests = b.addRunArtifact(config_tests);

    // Term module tests
    const term_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/term.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_term_tests = b.addRunArtifact(term_tests);

    // Util module tests
    const util_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/util.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_util_tests = b.addRunArtifact(util_tests);

    // Parallel module tests
    const parallel_test_mod = b.createModule(.{
        .root_source_file = b.path("src/parallel.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (spice_mod) |sm| {
        parallel_test_mod.addImport("spice", sm);
    }
    const parallel_tests = b.addTest(.{
        .root_module = parallel_test_mod,
    });
    const run_parallel_tests = b.addRunArtifact(parallel_tests);

    // Root module tests
    const root_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (ext_config_mod) |m| root_tests_mod.addImport("config", m);
    const root_tests = b.addTest(.{
        .root_module = root_tests_mod,
    });
    const run_root_tests = b.addRunArtifact(root_tests);

    // Test step: runs all unit tests
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_config_tests.step);
    test_step.dependOn(&run_term_tests.step);
    test_step.dependOn(&run_util_tests.step);
    test_step.dependOn(&run_parallel_tests.step);
    test_step.dependOn(&run_root_tests.step);

    // ========================================================================
    // Integration Tests
    // ========================================================================

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cli", .module = cli_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "term", .module = term_mod },
                .{ .name = "util", .module = util_mod },
                
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const test_integration_step = b.step("test-integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);

    // ========================================================================
    // All Tests
    // ========================================================================

    const test_all_step = b.step("test-all", "Run all tests (unit + integration)");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(test_integration_step);

    // ========================================================================
    // Check Step (for IDE integration)
    // ========================================================================
    //
    // Reuses the test compile steps (compile only, no run) to avoid
    // duplicating module definitions. This was previously 5 separate
    // b.createModule() calls identical to the test section above.

    const check_step = b.step("check", "Check for compilation errors (for IDE integration)");
    check_step.dependOn(&cli_tests.step);
    check_step.dependOn(&config_tests.step);
    check_step.dependOn(&term_tests.step);
    check_step.dependOn(&util_tests.step);
    check_step.dependOn(&parallel_tests.step);
    check_step.dependOn(&root_tests.step);

    // ========================================================================
    // Benchmarks
    // ========================================================================

    // Quick benchmarks (tests/bench.zig)
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "cli", .module = cli_mod },
                .{ .name = "util", .module = util_mod },
            },
        }),
    });

    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run quick performance benchmarks");
    bench_step.dependOn(&run_bench.step);

    // Scale benchmarks with JSON output (benchmarks/scale_bench.zig)
    const scale_bench_mod = b.createModule(.{
        .root_source_file = b.path("benchmarks/scale_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "cli", .module = cli_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "build_options", .module = build_options_mod },
        },
    });
    if (parallel_mod) |pm| scale_bench_mod.addImport("parallel", pm);
    const scale_bench = b.addExecutable(.{
        .name = "scale-bench",
        .root_module = scale_bench_mod,
    });
    b.installArtifact(scale_bench);

    const run_scale_bench = b.addRunArtifact(scale_bench);
    if (b.args) |args| {
        run_scale_bench.addArgs(args);
    }
    const scale_bench_step = b.step("scale-bench", "Run scale benchmarks with JSON output (pipe stdout to file)");
    scale_bench_step.dependOn(&run_scale_bench.step);

    // Benchmark comparison tool (benchmarks/compare.zig)
    const compare_bench = b.addExecutable(.{
        .name = "compare-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/compare.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    b.installArtifact(compare_bench);

    const run_compare_bench = b.addRunArtifact(compare_bench);
    if (b.args) |args| {
        run_compare_bench.addArgs(args);
    }
    const compare_bench_step = b.step("compare-bench", "Compare benchmark results against baseline");
    compare_bench_step.dependOn(&run_compare_bench.step);

    // ========================================================================
    // Demo Executable
    // ========================================================================

    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cli", .module = cli_mod },
                .{ .name = "config", .module = config_mod },
                .{ .name = "term", .module = term_mod },
                .{ .name = "util", .module = util_mod },
            },
        }),
    });

    b.installArtifact(demo);

    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| {
        run_demo.addArgs(args);
    }

    const run_step = b.step("run", "Build and run the demo");
    run_step.dependOn(&run_demo.step);
}
