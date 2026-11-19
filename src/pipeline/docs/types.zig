const std = @import("std");
const sdk = @import("parabellum_sdk");
const constants = @import("../../constants.zig");

pub const DocsInputs = struct {
    project_dir: []const u8 = ".",
    step: []const u8 = constants.Defaults.docs_step,
    out_dir: []const u8 = "zig-out/docs",
    package_bundle: bool = false,
    optimize: []const u8 = "Debug",
    module_filter: []const u8 = "",
};

pub const DocsModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    step: []const u8,
    out_dir: []const u8,
    package_bundle: bool,
    optimize: []const u8,
};

pub const DocsModuleResult = struct {
    order_index: i64,
    module_name: []const u8,
    repo_dir: []const u8,
    out_dir: []const u8,
    tarball_path: []const u8,
    package_bundle: bool,
};

pub const DocsSummarizeInputs = struct {
    results: sdk.task.Rows(DocsModuleResult),
};

pub const DocsOutputs = struct {
    modules_documented: i64,
};

pub fn lessThanDocsResult(_: void, a: DocsModuleResult, b: DocsModuleResult) bool {
    return a.order_index < b.order_index;
}
