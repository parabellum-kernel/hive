const std = @import("std");
const platform = @import("parabellum_platform");
const config = @import("../config/mod.zig");
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
    const env = services.environment;
    try fs.mkdirAll(alloc, dest_dir);

    const base = std.mem.trimEnd(u8, task.repo_url_or_path, "/");
    const manifest_url = try std.fmt.allocPrint(alloc, "{s}/{s}/{s}/{s}/{s}", .{
        base,
        task.name,
        task.version,
        task.target,
        constants.HivePaths.manifest_file,
    });
    defer alloc.free(manifest_url);

    const manifest_dest = try std.fs.path.join(alloc, &.{ dest_dir, constants.HivePaths.manifest_file });
    defer alloc.free(manifest_dest);

    const token = if (task.auth_env.len > 0)
        env.getEnv(alloc, task.auth_env)
    else
        env.getEnv(alloc, constants.EnvVar.HIVE_HTTP_TOKEN.key());
    defer if (token) |t| alloc.free(t);

    try ProviderMod.downloadWithCurl(alloc, services.runner, manifest_url, manifest_dest, token);

    const m_bytes = try fs.readFileAlloc(alloc, manifest_dest, 1024 * 1024);
    defer alloc.free(m_bytes);
    var parsed = try std.json.parseFromSlice(config.PackageManifest, alloc, m_bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    var out: std.ArrayListUnmanaged(fetch_types.FetchArtifactTask) = .empty;
    for (parsed.value.artifacts) |art| {
        try out.append(alloc, try ProviderMod.makeFetchArtifactTask(alloc, task, dest_dir, art.file, art.sha256));
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
    const env = services.environment;

    const base = std.mem.trimEnd(u8, art.repo_url_or_path, "/");
    const art_url = try std.fmt.allocPrint(alloc, "{s}/{s}/{s}/{s}/{s}", .{
        base,
        art.name,
        art.version,
        art.target,
        art.file_name,
    });
    defer alloc.free(art_url);

    const art_dest = try std.fs.path.join(alloc, &.{ art.dest_dir, art.file_name });
    defer alloc.free(art_dest);

    const token = if (art.auth_env.len > 0)
        env.getEnv(alloc, art.auth_env)
    else
        env.getEnv(alloc, constants.EnvVar.HIVE_HTTP_TOKEN.key());
    defer if (token) |t| alloc.free(t);

    try ProviderMod.downloadWithCurl(alloc, services.runner, art_url, art_dest, token);
    const art_bytes = try fs.readFileAlloc(alloc, art_dest, 256 * 1024 * 1024);
    defer alloc.free(art_bytes);

    if (art.expected_sha256.len > 0) {
        const actual_sha = fetch_types.computeSha256Hex(art_bytes);
        if (!std.mem.eql(u8, &actual_sha, art.expected_sha256)) {
            return error.ChecksumMismatch;
        }
    }
    return art_bytes.len;
}

fn upload(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    task: publish_types.PublishAssetTask,
    _: []const u8,
) !void {
    const base = std.mem.trimEnd(u8, task.repo_url_or_path, "/");
    const url = try std.fmt.allocPrint(alloc, "{s}/{s}/{s}/{s}/{s}", .{
        base,
        task.module_name,
        task.effective_version,
        task.target,
        task.file_name,
    });
    defer alloc.free(url);

    const token = if (task.auth_env.len > 0)
        services.environment.getEnv(alloc, task.auth_env)
    else
        services.environment.getEnv(alloc, constants.EnvVar.HIVE_HTTP_TOKEN.key());
    defer if (token) |t| alloc.free(t);

    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(alloc);
    try argv.appendSlice(alloc, &.{ "curl", "-fsSL", "-X", "PUT", "-T", task.src_path });

    var auth_hdr: ?[]u8 = null;
    defer if (auth_hdr) |h| alloc.free(h);
    if (token) |t| {
        auth_hdr = try std.fmt.allocPrint(alloc, "Authorization: Bearer {s}", .{t});
        try argv.append(alloc, "-H");
        try argv.append(alloc, auth_hdr.?);
    }
    try argv.append(alloc, url);

    var res = try services.runner.run(alloc, .{ .argv = argv.items });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.HttpUploadFailed;
}

const vtable = ArtifactRepositoryProvider.VTable{
    .prepare_fetch = prepareFetch,
    .transfer_fetch = transferFetch,
    .upload = upload,
};
