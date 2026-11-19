const std = @import("std");
const platform = @import("parabellum_platform");
const config = @import("../config/mod.zig");
const fetch_types = @import("../pipeline/fetch/types.zig");
const publish_types = @import("../pipeline/publish/types.zig");

const LocalProvider = @import("LocalProvider.zig");
const HttpProvider = @import("HttpProvider.zig");
const GithubProvider = @import("GithubProvider.zig");
const GitProvider = @import("GitProvider.zig");

/// Unified polymorphic Artifact Repository Provider interface (VTable pattern)
/// shared by `hive fetch` (`prepareFetch`, `transferFetch`) and `hive publish` (`upload`).
pub const ArtifactRepositoryProvider = struct {
    ptr: ?*anyopaque = null,
    vtable: *const VTable,

    pub const VTable = struct {
        prepare_fetch: *const fn (
            ctx: ?*anyopaque,
            alloc: std.mem.Allocator,
            services: platform.PlatformServices,
            task: fetch_types.FetchDepTask,
            dest_dir: []const u8,
        ) anyerror![]const fetch_types.FetchArtifactTask,
        transfer_fetch: *const fn (
            ctx: ?*anyopaque,
            alloc: std.mem.Allocator,
            services: platform.PlatformServices,
            art: fetch_types.FetchArtifactTask,
        ) anyerror!u64,
        upload: *const fn (
            ctx: ?*anyopaque,
            alloc: std.mem.Allocator,
            services: platform.PlatformServices,
            task: publish_types.PublishAssetTask,
            data: []const u8,
        ) anyerror!void,
    };

    pub fn prepareFetch(
        self: ArtifactRepositoryProvider,
        alloc: std.mem.Allocator,
        services: platform.PlatformServices,
        task: fetch_types.FetchDepTask,
        dest_dir: []const u8,
    ) ![]const fetch_types.FetchArtifactTask {
        return self.vtable.prepare_fetch(self.ptr, alloc, services, task, dest_dir);
    }

    pub fn transferFetch(
        self: ArtifactRepositoryProvider,
        alloc: std.mem.Allocator,
        services: platform.PlatformServices,
        art: fetch_types.FetchArtifactTask,
    ) !u64 {
        return self.vtable.transfer_fetch(self.ptr, alloc, services, art);
    }

    pub fn upload(
        self: ArtifactRepositoryProvider,
        alloc: std.mem.Allocator,
        services: platform.PlatformServices,
        task: publish_types.PublishAssetTask,
        data: []const u8,
    ) !void {
        return self.vtable.upload(self.ptr, alloc, services, task, data);
    }
};

pub fn selectProvider(repo_type: config.hive_json.RepositoryType) ArtifactRepositoryProvider {
    return switch (repo_type) {
        .local => LocalProvider.provider(),
        .http => HttpProvider.provider(),
        .github => GithubProvider.provider(),
        .git => GitProvider.provider(),
    };
}

pub fn makeFetchArtifactTask(
    alloc: std.mem.Allocator,
    task: fetch_types.FetchDepTask,
    dest_dir: []const u8,
    file_name: []const u8,
    expected_sha256: []const u8,
) !fetch_types.FetchArtifactTask {
    return .{
        .order_index = task.order_index,
        .name = try alloc.dupe(u8, task.name),
        .version = try alloc.dupe(u8, task.version),
        .target = try alloc.dupe(u8, task.target),
        .repo_type = try alloc.dupe(u8, task.repo_type),
        .repo_url_or_path = try alloc.dupe(u8, task.repo_url_or_path),
        .auth_env = try alloc.dupe(u8, task.auth_env),
        .dest_dir = try alloc.dupe(u8, dest_dir),
        .file_name = try alloc.dupe(u8, file_name),
        .expected_sha256 = try alloc.dupe(u8, expected_sha256),
        .already_cached = false,
        .refresh = task.refresh,
    };
}

pub fn downloadWithCurl(
    alloc: std.mem.Allocator,
    runner: platform.ProcessRunner,
    url: []const u8,
    dest_path: []const u8,
    token: ?[]const u8,
) !void {
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(alloc);

    try argv.appendSlice(alloc, &.{ "curl", "-fsSL", "-o", dest_path });
    var auth_hdr: ?[]u8 = null;
    defer if (auth_hdr) |h| alloc.free(h);
    if (token) |t| {
        auth_hdr = try std.fmt.allocPrint(alloc, "Authorization: Bearer {s}", .{t});
        try argv.append(alloc, "-H");
        try argv.append(alloc, auth_hdr.?);
    }
    try argv.append(alloc, url);

    var res = try runner.run(alloc, .{ .argv = argv.items });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.DownloadFailed;
}
