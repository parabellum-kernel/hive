const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Computes tree size and deletes each target directory in parallel.
pub const CleanExecuteService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *CleanExecuteService, alloc: std.mem.Allocator, target: types.CleanTarget) !types.CleanTargetResult {
        const fs = self.services.filesystem;
        const sz = fs.computeTreeBytes(alloc, target.path);

        if (!target.dry_run) {
            try fs.deleteTree(alloc, target.path);
        }

        return .{
            .order_index = target.order_index,
            .path = try alloc.dupe(u8, target.path),
            .bytes = @intCast(sz),
            .dry_run = target.dry_run,
        };
    }
};
