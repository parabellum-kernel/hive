const std = @import("std");
const sdk = @import("parabellum_sdk");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");

pub const FetchInputs = struct {
    project_dir: []const u8 = ".",
    offline: bool = false,
    refresh: bool = false,
    target: []const u8 = "native",
    artifact_repository_dir: []const u8 = "",
};

pub const FetchDepTask = struct {
    order_index: i64 = 0,
    name: []const u8,
    version: []const u8,
    repo_name: []const u8,
    repo_type: []const u8,
    repo_url_or_path: []const u8,
    auth_env: []const u8,
    require_signature: bool,
    target: []const u8,
    packages_dir: []const u8,
    offline: bool,
    refresh: bool,
};

pub const FetchArtifactTask = struct {
    order_index: i64 = 0,
    name: []const u8,
    version: []const u8,
    target: []const u8,
    repo_type: []const u8,
    repo_url_or_path: []const u8,
    auth_env: []const u8,
    dest_dir: []const u8,
    file_name: []const u8,
    expected_sha256: []const u8,
    already_cached: bool,
    refresh: bool,
};

pub const FetchStatus = enum {
    cached,
    downloaded,
};

pub const FetchDepResult = struct {
    order_index: i64 = 0,
    name: []const u8,
    version: []const u8,
    target: []const u8,
    status: []const u8,
    bytes: i64,
};

pub const FetchSummarizeInputs = struct {
    results: sdk.task.Rows(FetchDepResult),
};

pub const FetchOutputs = struct {
    total_resolved: i64,
    cached_count: i64,
    downloaded_count: i64,
    bytes_fetched: i64,
};

pub fn computeSha256Hex(data: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn isSnapshotVersion(version: []const u8) bool {
    return std.mem.endsWith(u8, version, constants.HivePaths.snapshot_suffix);
}

pub fn findRepository(repos: []const config.hive_json.RepositorySpec, name_opt: ?[]const u8) ?config.hive_json.RepositorySpec {
    if (name_opt) |n| {
        for (repos) |r| {
            if (std.mem.eql(u8, r.name, n)) return r;
        }
        return null;
    }
    if (repos.len > 0) return repos[0];
    return null;
}
