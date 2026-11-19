const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const types = @import("types.zig");
const provider_mod = @import("../../provider/mod.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Transfers and verifies each individual artifact in parallel.
pub const FetchTransferService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *FetchTransferService, alloc: std.mem.Allocator, art: types.FetchArtifactTask) !types.FetchDepResult {
        if (art.already_cached) {
            return .{
                .order_index = art.order_index,
                .name = try alloc.dupe(u8, art.name),
                .version = try alloc.dupe(u8, art.version),
                .target = try alloc.dupe(u8, art.target),
                .status = @tagName(types.FetchStatus.cached),
                .bytes = 0,
            };
        }

        const repo_type = std.meta.stringToEnum(config.hive_json.RepositoryType, art.repo_type) orelse .local;
        const repo_provider = provider_mod.selectProvider(repo_type);
        const bytes = try repo_provider.transferFetch(alloc, self.services, art);

        return .{
            .order_index = art.order_index,
            .name = try alloc.dupe(u8, art.name),
            .version = try alloc.dupe(u8, art.version),
            .target = try alloc.dupe(u8, art.target),
            .status = @tagName(types.FetchStatus.downloaded),
            .bytes = @intCast(bytes),
        };
    }
};
