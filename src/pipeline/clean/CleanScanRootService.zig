const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental flat-map): Scans each root subtree or snapshot package directory
/// in parallel and emits `[]const CleanTarget`.
pub const CleanScanRootService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *CleanScanRootService, alloc: std.mem.Allocator, root: types.CleanScanRoot) ![]const types.CleanTarget {
        const fs = self.services.filesystem;
        const kind = std.meta.stringToEnum(types.CleanRootKind, root.kind) orelse .workspace_subdir;

        var paths: std.ArrayListUnmanaged([]u8) = .empty;
        errdefer {
            for (paths.items) |p| alloc.free(p);
            paths.deinit(alloc);
        }

        switch (kind) {
            .root_match => {
                try paths.append(alloc, try alloc.dupe(u8, root.dir_path));
            },
            .workspace_subdir => {
                try types.discoverCleanTargets(alloc, fs, root.dir_path, root.include_out, root.include_zig_pkg, &paths);
            },
            .snapshot_pkg => {
                if (fs.listDir(alloc, root.dir_path)) |ver_entries| {
                    defer platform.PlatformFs.freeDirEntries(alloc, ver_entries);
                    for (ver_entries) |ver_ent| {
                        if (ver_ent.kind != .directory) continue;
                        if (!std.mem.endsWith(u8, ver_ent.name, constants.HivePaths.snapshot_suffix)) continue;
                        try paths.append(alloc, try std.fs.path.join(alloc, &.{ root.dir_path, ver_ent.name }));
                    }
                } else |_| {}
            },
        }

        const targets = try alloc.alloc(types.CleanTarget, paths.items.len);
        for (paths.items, 0..) |p, idx| {
            targets[idx] = .{
                .order_index = root.order_index,
                .path = p,
                .dry_run = root.dry_run,
            };
        }
        paths.deinit(alloc);
        return targets;
    }
};
