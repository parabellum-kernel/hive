const std = @import("std");
const sdk = @import("parabellum_sdk");
const constants = @import("../../constants.zig");

pub const TestTier = enum {
    unit,
    e2e,
    all,
};

pub const TestInputs = struct {
    project_dir: []const u8 = ".",
    tier: []const u8 = @tagName(TestTier.unit),
    filter: []const u8 = "",
    fail_fast: bool = false,
    optimize: []const u8 = "Debug",
    module_filter: []const u8 = "",
    extra_args_packed: []const u8 = "",
};

pub const TestModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    tier: []const u8,
    optimize: []const u8,
    filter: []const u8,
    fail_fast: bool,
    extra_args_packed: []const u8,
};

pub const TestStepTask = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    zig_step: []const u8,
    tier: []const u8,
    optimize: []const u8,
    filter: []const u8,
    fail_fast: bool,
    extra_args_packed: []const u8,
};

pub const TestStepResult = struct {
    order_index: i64,
    module_name: []const u8,
    tier: []const u8,
    passed: bool,
    duration_ms: i64,
};

pub const TestSummarizeInputs = struct {
    results: sdk.task.Rows(TestStepResult),
};

pub const TestOutputs = struct {
    total_suites: i64,
    passed_suites: i64,
    failed_suites: i64,
};

pub fn hasZigBuildStep(alloc: std.mem.Allocator, runner: @import("parabellum_platform").ProcessRunner, repo_dir: []const u8, step_name: []const u8) bool {
    var res = runner.run(alloc, .{
        .argv = &.{ constants.TestSteps.zig_bin, constants.TestSteps.zig_build_cmd, constants.TestSteps.help_flag },
        .cwd = repo_dir,
    }) catch return false;
    defer res.deinit(alloc);
    if (res.exit_code != 0) return false;
    return std.mem.indexOf(u8, res.stdout, step_name) != null;
}

pub fn lessThanResult(_: void, a: TestStepResult, b: TestStepResult) bool {
    if (a.order_index != b.order_index) return a.order_index < b.order_index;
    return std.mem.order(u8, a.tier, b.tier) == .lt;
}
