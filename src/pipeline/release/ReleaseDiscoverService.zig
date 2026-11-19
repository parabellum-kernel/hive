const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Discovers target project/workspace module paths for release orchestration.
pub const ReleaseDiscoverService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *ReleaseDiscoverService, alloc: std.mem.Allocator, inputs: types.ReleaseInputs) ![]const types.ReleaseModuleRef {
        const fs = self.services.filesystem;
        const canonical_root = try fs.realpath(alloc, inputs.project_dir);
        defer alloc.free(canonical_root);

        var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, canonical_root);
        defer loaded_cfg.deinit();
        const cfg = loaded_cfg.value();

        var refs: std.ArrayListUnmanaged(types.ReleaseModuleRef) = .empty;
        errdefer refs.deinit(alloc);

        if (cfg.modules.len > 0) {
            var idx: i64 = 0;
            for (cfg.modules) |mod_rel| {
                if (inputs.module_filter.len > 0 and !std.mem.eql(u8, mod_rel, inputs.module_filter)) {
                    continue;
                }
                try refs.append(alloc, .{
                    .order_index = idx,
                    .repo_dir = try std.fs.path.join(alloc, &.{ canonical_root, mod_rel }),
                    .explicit_version = try alloc.dupe(u8, inputs.version),
                    .bump = try alloc.dupe(u8, inputs.bump),
                    .dry_run = inputs.dry_run,
                });
                idx += 1;
            }
        } else {
            try refs.append(alloc, .{
                .order_index = 0,
                .repo_dir = try alloc.dupe(u8, canonical_root),
                .explicit_version = try alloc.dupe(u8, inputs.version),
                .bump = try alloc.dupe(u8, inputs.bump),
                .dry_run = inputs.dry_run,
            });
        }

        if (refs.items.len == 0) {
            self.logger.err("No releasable modules matched in '{s}'", .{canonical_root});
            return error.NoModulesMatched;
        }

        return try refs.toOwnedSlice(alloc);
    }
};
