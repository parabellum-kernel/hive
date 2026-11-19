const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engine_dep = b.dependency("parabellum", .{
        .target = target,
        .optimize = optimize,
    });
    const sdk_dep = b.dependency("parabellum_sdk", .{
        .target = target,
        .optimize = optimize,
    });
    const libs_dep = b.dependency("parabellum_libs", .{
        .target = target,
        .optimize = optimize,
    });
    const ext_dep = b.dependency("parabellum_extensions", .{
        .target = target,
        .optimize = optimize,
    });

    const parabellum_mod = engine_dep.module("parabellum");
    const sdk_mod = sdk_dep.module("parabellum_sdk");
    const yaml_mod = libs_dep.module("parabellum_yaml");
    const platform_mod = libs_dep.module("parabellum_platform");
    const otel_mod = ext_dep.module("ext_opentelemetry");
    const trace_jsonl_mod = ext_dep.module("ext_trace_jsonl");

    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", "2.0.2");
    const build_opts_mod = build_opts.createModule();

    const hive_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "parabellum", .module = parabellum_mod },
            .{ .name = "parabellum_sdk", .module = sdk_mod },
            .{ .name = "parabellum_yaml", .module = yaml_mod },
            .{ .name = "parabellum_platform", .module = platform_mod },
            .{ .name = "ext_opentelemetry", .module = otel_mod },
            .{ .name = "ext_trace_jsonl", .module = trace_jsonl_mod },
            .{ .name = "build_options", .module = build_opts_mod },
        },
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "hive", .module = hive_mod },
            .{ .name = "parabellum", .module = parabellum_mod },
            .{ .name = "parabellum_sdk", .module = sdk_mod },
            .{ .name = "parabellum_platform", .module = platform_mod },
            .{ .name = "build_options", .module = build_opts_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "hive",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run hive CLI");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run hive unit tests");
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "hive", .module = hive_mod },
            .{ .name = "parabellum", .module = parabellum_mod },
            .{ .name = "parabellum_sdk", .module = sdk_mod },
            .{ .name = "parabellum_platform", .module = platform_mod },
            .{ .name = "build_options", .module = build_opts_mod },
        },
    });
    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}
