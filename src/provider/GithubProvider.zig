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
    try services.filesystem.mkdirAll(alloc, dest_dir);
    const tarball_name = try std.fmt.allocPrint(alloc, "{s}-{s}-{s}.tar.gz", .{ task.name, task.version, task.target });
    defer alloc.free(tarball_name);

    const out = try alloc.alloc(fetch_types.FetchArtifactTask, 1);
    out[0] = try ProviderMod.makeFetchArtifactTask(alloc, task, dest_dir, tarball_name, "");
    return out;
}

fn transferFetch(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    art: fetch_types.FetchArtifactTask,
) !u64 {
    const fs = services.filesystem;
    const env = services.environment;

    const token = env.getEnv(alloc, constants.EnvVar.HIVE_GITHUB_TOKEN.key()) orelse
        env.getEnv(alloc, constants.EnvVar.GITHUB_TOKEN.key());
    defer if (token) |t| alloc.free(t);

    const asset_url = try std.fmt.allocPrint(alloc, "https://github.com/{s}/{s}/releases/download/v{s}/{s}", .{
        art.repo_url_or_path,
        art.name,
        art.version,
        art.file_name,
    });
    defer alloc.free(asset_url);

    const tarball_dest = try std.fs.path.join(alloc, &.{ art.dest_dir, art.file_name });
    defer alloc.free(tarball_dest);

    try ProviderMod.downloadWithCurl(alloc, services.runner, asset_url, tarball_dest, token);
    const data = try fs.readFileAlloc(alloc, tarball_dest, 256 * 1024 * 1024);
    defer alloc.free(data);

    var tar_res = try services.runner.run(alloc, .{
        .argv = &.{ "tar", "-xzf", tarball_dest, "-C", art.dest_dir },
    });
    defer tar_res.deinit(alloc);
    if (tar_res.exit_code != 0) return error.ArchiveExtractFailed;

    return data.len;
}

fn upload(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    task: publish_types.PublishAssetTask,
    _: []const u8,
) !void {
    const token = services.environment.getEnv(alloc, constants.EnvVar.HIVE_GITHUB_TOKEN.key()) orelse
        services.environment.getEnv(alloc, constants.EnvVar.GITHUB_TOKEN.key()) orelse
        return error.MissingGithubToken;
    defer alloc.free(token);

    const tag = try std.fmt.allocPrint(alloc, "v{s}", .{task.effective_version});
    defer alloc.free(tag);

    const repo_slug = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ task.repo_url_or_path, task.module_name });
    defer alloc.free(repo_slug);

    var res = try services.runner.run(alloc, .{
        .argv = &.{ "gh", "release", "upload", tag, task.src_path, "--repo", repo_slug, "--clobber" },
        .env_overrides = &.{.{ .key = constants.EnvVar.GITHUB_TOKEN.key(), .value = token }},
    });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.GithubUploadFailed;
}

const vtable = ArtifactRepositoryProvider.VTable{
    .prepare_fetch = prepareFetch,
    .transfer_fetch = transferFetch,
    .upload = upload,
};
