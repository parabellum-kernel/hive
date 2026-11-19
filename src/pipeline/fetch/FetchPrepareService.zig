const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");
const provider_mod = @import("../../provider/mod.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental flat-map): Checks local cache / snapshot precedence,
/// prepares per-artifact transfer tasks via `FetchProvider.prepare`.
pub const FetchPrepareService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *FetchPrepareService, alloc: std.mem.Allocator, task: types.FetchDepTask) ![]const types.FetchArtifactTask {
        const fs = self.services.filesystem;

        const dest_dir = try std.fs.path.join(alloc, &.{ task.packages_dir, task.name, task.version, task.target });
        defer alloc.free(dest_dir);
        const manifest_path = try std.fs.path.join(alloc, &.{ dest_dir, constants.HivePaths.manifest_file });
        defer alloc.free(manifest_path);

        const is_cached = fs.exists(alloc, manifest_path);
        const is_snap = types.isSnapshotVersion(task.version);

        if (is_cached and (!task.refresh or (is_snap and !task.refresh))) {
            const cached = try alloc.alloc(types.FetchArtifactTask, 1);
            cached[0] = .{
                .order_index = task.order_index,
                .name = try alloc.dupe(u8, task.name),
                .version = try alloc.dupe(u8, task.version),
                .target = try alloc.dupe(u8, task.target),
                .repo_type = try alloc.dupe(u8, task.repo_type),
                .repo_url_or_path = try alloc.dupe(u8, task.repo_url_or_path),
                .auth_env = try alloc.dupe(u8, task.auth_env),
                .dest_dir = try alloc.dupe(u8, dest_dir),
                .file_name = "",
                .expected_sha256 = "",
                .already_cached = true,
                .refresh = task.refresh,
            };
            return cached;
        }

        if (task.offline) {
            self.logger.err("Offline mode: missing artifact {s}@{s} ({s})", .{ task.name, task.version, task.target });
            return error.OfflineArtifactMissing;
        }

        const repo_type = std.meta.stringToEnum(config.hive_json.RepositoryType, task.repo_type) orelse .local;
        const repo_provider = provider_mod.selectProvider(repo_type);
        return try repo_provider.prepareFetch(alloc, self.services, task, dest_dir);
    }
};
