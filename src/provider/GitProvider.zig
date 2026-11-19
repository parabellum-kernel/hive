const std = @import("std");
const platform = @import("parabellum_platform");
const git = @import("../git.zig");
const fetch_types = @import("../pipeline/fetch/types.zig");
const publish_types = @import("../pipeline/publish/types.zig");
const ProviderMod = @import("ArtifactRepositoryProvider.zig");

const ArtifactRepositoryProvider = ProviderMod.ArtifactRepositoryProvider;

pub fn provider() ArtifactRepositoryProvider {
    return .{ .vtable = &vtable };
}

fn prepareFetch(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    _: platform.PlatformServices,
    task: fetch_types.FetchDepTask,
    dest_dir: []const u8,
) ![]const fetch_types.FetchArtifactTask {
    const out = try alloc.alloc(fetch_types.FetchArtifactTask, 1);
    out[0] = try ProviderMod.makeFetchArtifactTask(alloc, task, dest_dir, "", "");
    return out;
}

fn transferFetch(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    art: fetch_types.FetchArtifactTask,
) !u64 {
    var gc = try git.GitClient.init(alloc, services.environment, services.runner);
    defer gc.deinit(alloc);

    if (services.filesystem.exists(alloc, art.dest_dir)) {
        if (art.refresh) {
            try gc.pullFastForward(alloc, art.dest_dir);
        }
    } else {
        try services.filesystem.mkdirAll(alloc, std.fs.path.dirname(art.dest_dir) orelse art.dest_dir);
        try gc.clone(alloc, art.repo_url_or_path, art.dest_dir, .{ .depth = 1 });
    }
    return services.filesystem.computeTreeBytes(alloc, art.dest_dir);
}

fn upload(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    task: publish_types.PublishAssetTask,
    data: []const u8,
) !void {
    const fs = services.filesystem;
    var gc = try git.GitClient.init(alloc, services.environment, services.runner);
    defer gc.deinit(alloc);

    const tmp_reg = try std.fs.path.join(alloc, &.{ services.environment.tempDir(alloc), "hive-publish-git-reg" });
    defer alloc.free(tmp_reg);
    try fs.deleteTree(alloc, tmp_reg);
    defer fs.deleteTree(alloc, tmp_reg) catch {};

    try gc.clone(alloc, task.repo_url_or_path, tmp_reg, .{ .depth = 1 });

    const dest_path = try std.fs.path.join(alloc, &.{ tmp_reg, task.module_name, task.effective_version, task.target, task.file_name });
    defer alloc.free(dest_path);
    try fs.atomicWriteFile(alloc, dest_path, data, false);

    const msg = try std.fmt.allocPrint(alloc, "publish: {s}@{s} ({s})", .{ task.module_name, task.effective_version, task.file_name });
    defer alloc.free(msg);
    try gc.commit(alloc, tmp_reg, msg);
    try gc.pushWithTags(alloc, tmp_reg, "origin", "main");
}

const vtable = ArtifactRepositoryProvider.VTable{
    .prepare_fetch = prepareFetch,
    .transfer_fetch = transferFetch,
    .upload = upload,
};
