const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../constants.zig");
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
    services: platform.PlatformServices,
    task: fetch_types.FetchDepTask,
    dest_dir: []const u8,
) ![]const fetch_types.FetchArtifactTask {
    const fs = services.filesystem;
    const src_dir = try std.fs.path.join(alloc, &.{ task.repo_url_or_path, task.name, task.version, task.target });
    defer alloc.free(src_dir);

    const manifest_src = try std.fs.path.join(alloc, &.{ src_dir, constants.HivePaths.manifest_file });
    defer alloc.free(manifest_src);
    if (!fs.exists(alloc, manifest_src)) return error.ArtifactNotFoundInLocalRepo;
    if (std.mem.eql(u8, src_dir, dest_dir)) return &.{};

    try fs.mkdirAll(alloc, dest_dir);
    const entries = try fs.listDir(alloc, src_dir);
    defer platform.PlatformFs.freeDirEntries(alloc, entries);

    var out: std.ArrayListUnmanaged(fetch_types.FetchArtifactTask) = .empty;
    for (entries) |ent| {
        if (ent.kind != .file) continue;
        try out.append(alloc, try ProviderMod.makeFetchArtifactTask(alloc, task, dest_dir, ent.name, ""));
    }
    return try out.toOwnedSlice(alloc);
}

fn transferFetch(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    art: fetch_types.FetchArtifactTask,
) !u64 {
    const fs = services.filesystem;
    const s_path = try std.fs.path.join(alloc, &.{ art.repo_url_or_path, art.name, art.version, art.target, art.file_name });
    defer alloc.free(s_path);
    const d_path = try std.fs.path.join(alloc, &.{ art.dest_dir, art.file_name });
    defer alloc.free(d_path);

    const data = try fs.readFileAlloc(alloc, s_path, 256 * 1024 * 1024);
    defer alloc.free(data);
    const is_exec = std.mem.endsWith(u8, art.file_name, constants.ArtifactExts.so) or
        std.mem.endsWith(u8, art.file_name, constants.ArtifactExts.dylib);
    try fs.atomicWriteFile(alloc, d_path, data, is_exec);
    return data.len;
}

fn upload(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    task: publish_types.PublishAssetTask,
    data: []const u8,
) !void {
    const fs = services.filesystem;
    const dest_dir = try std.fs.path.join(alloc, &.{ task.repo_url_or_path, task.module_name, task.effective_version, task.target });
    defer alloc.free(dest_dir);
    try fs.mkdirAll(alloc, dest_dir);

    const dest_path = try std.fs.path.join(alloc, &.{ dest_dir, task.file_name });
    defer alloc.free(dest_path);
    try fs.atomicWriteFile(alloc, dest_path, data, false);
}

const vtable = ArtifactRepositoryProvider.VTable{
    .prepare_fetch = prepareFetch,
    .transfer_fetch = transferFetch,
    .upload = upload,
};
