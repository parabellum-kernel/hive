const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental map): Deletes each non-`.git` entry in destination when `--force wipe` is active.
pub const InitWipeEntryService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InitWipeEntryService, alloc: std.mem.Allocator, task: types.InitWipeTask) !types.InitWipeResult {
        if (!task.skip_delete and task.path.len > 0) {
            try self.services.filesystem.deleteTree(alloc, task.path);
        }
        return .{
            .template_dir = try alloc.dupe(u8, task.template_dir),
            .dest_dir = try alloc.dupe(u8, task.dest_dir),
            .vars_packed = try alloc.dupe(u8, task.vars_packed),
        };
    }
};
