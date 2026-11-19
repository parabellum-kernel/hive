const std = @import("std");
const sdk = @import("parabellum_sdk");
const constants = @import("../../constants.zig");

pub const PublishInputs = struct {
    project_dir: []const u8 = ".",
    repo: []const u8 = "",
    snapshot: bool = false,
    release: bool = true,
    version: []const u8 = "",
    target: []const u8 = constants.Defaults.native_target,
    force: bool = false,
    dry_run: bool = false,
    ecc: bool = false,
    module_filter: []const u8 = "",
};

pub const PublishModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    repo_name_override: []const u8,
    snapshot: bool,
    version_override: []const u8,
    target: []const u8,
    force: bool,
    dry_run: bool,
    ecc: bool,
};

pub const PublishAssetTask = struct {
    order_index: i64,
    module_name: []const u8,
    effective_version: []const u8,
    target: []const u8,
    repo_name: []const u8,
    repo_type: []const u8,
    repo_url_or_path: []const u8,
    auth_env: []const u8,
    src_path: []const u8,
    file_name: []const u8,
    force: bool,
    dry_run: bool,
    snapshot: bool,
};

pub const PublishAssetResult = struct {
    order_index: i64,
    module_name: []const u8,
    effective_version: []const u8,
    repo_name: []const u8,
    file_name: []const u8,
    sha256: []const u8,
    bytes: i64,
    dry_run: bool,
};

pub const PublishSummarizeInputs = struct {
    results: sdk.task.Rows(PublishAssetResult),
};

pub const PublishOutputs = struct {
    assets_published: i64,
    bytes_uploaded: i64,
    dry_run: bool,
};

pub fn lessThanPublishResult(_: void, a: PublishAssetResult, b: PublishAssetResult) bool {
    if (a.order_index != b.order_index) return a.order_index < b.order_index;
    return std.mem.order(u8, a.file_name, b.file_name) == .lt;
}
