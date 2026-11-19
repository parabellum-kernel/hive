const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");
const provider_mod = @import("../../provider/mod.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Computes SHA-256 and uploads each asset via `PublishProvider` VTable.
pub const PublishUploadService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PublishUploadService, alloc: std.mem.Allocator, task: types.PublishAssetTask) !types.PublishAssetResult {
        const fs = self.services.filesystem;
        const data = try fs.readFileAlloc(alloc, task.src_path, 256 * 1024 * 1024);
        defer alloc.free(data);

        const sha = build_types.computeSha256Hex(data);

        if (!task.dry_run) {
            const repo_type = std.meta.stringToEnum(config.hive_json.RepositoryType, task.repo_type) orelse .http;
            const repo_provider = provider_mod.selectProvider(repo_type);
            try repo_provider.upload(alloc, self.services, task, data);
        }

        return .{
            .order_index = task.order_index,
            .module_name = try alloc.dupe(u8, task.module_name),
            .effective_version = try alloc.dupe(u8, task.effective_version),
            .repo_name = try alloc.dupe(u8, task.repo_name),
            .file_name = try alloc.dupe(u8, task.file_name),
            .sha256 = try alloc.dupe(u8, &sha),
            .bytes = @intCast(data.len),
            .dry_run = task.dry_run,
        };
    }
};
