const std = @import("std");
const sdk = @import("parabellum_sdk");
const constants = @import("../../constants.zig");

pub const InstallInputs = struct {
    project_dir: []const u8 = ".",
    snapshot: bool = true,
    release: bool = false,
    force: bool = false,
    target: []const u8 = constants.Defaults.native_target,
    artifact_repository_dir: []const u8 = "",
    module_filter: []const u8 = "",
};

pub const InstallModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    snapshot: bool,
    release: bool,
    force: bool,
    target: []const u8,
    packages_dir: []const u8,
};

pub const InstallBucket = enum {
    lib,
    bin,
    dist,
};

pub const InstallDirScanTask = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    effective_version: []const u8,
    target: []const u8,
    src_dir: []const u8,
    dest_target_dir: []const u8,
    dest_ver_dir: []const u8,
    bucket: []const u8,
};

pub const InstallRawEntry = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    effective_version: []const u8,
    target: []const u8,
    src_dir: []const u8,
    dest_target_dir: []const u8,
    dest_ver_dir: []const u8,
    bucket: []const u8,
    file_name: []const u8,
};

pub const InstallArtifactTask = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    effective_version: []const u8,
    target: []const u8,
    src_path: []const u8,
    dest_dir: []const u8,
    dest_path: []const u8,
    file_name: []const u8,
    kind: []const u8,
    executable: bool,
};

pub const InstallArtifactResult = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    effective_version: []const u8,
    target: []const u8,
    dest_dir: []const u8,
    file_name: []const u8,
    kind: []const u8,
    sha256: []const u8,
    size_bytes: i64,
};

pub const InstallSummarizeInputs = struct {
    results: sdk.task.Rows(InstallArtifactResult),
};

pub const InstallOutputs = struct {
    artifacts_installed: i64,
    bytes_installed: i64,
};

pub fn lessThanInstallResult(_: void, a: InstallArtifactResult, b: InstallArtifactResult) bool {
    if (a.order_index != b.order_index) return a.order_index < b.order_index;
    return std.mem.order(u8, a.file_name, b.file_name) == .lt;
}
