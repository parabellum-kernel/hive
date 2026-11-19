const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Discovers target project/workspace module directories and preserves deterministic `order_index`.
pub const TestDiscoverModulesService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *TestDiscoverModulesService, alloc: std.mem.Allocator, inputs: types.TestInputs) ![]const types.TestModuleRef {
        const fs = self.services.filesystem;
        const canonical_root = try fs.realpath(alloc, inputs.project_dir);
        defer alloc.free(canonical_root);

        var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, canonical_root);
        defer loaded_cfg.deinit();
        const cfg = loaded_cfg.value();

        var refs: std.ArrayListUnmanaged(types.TestModuleRef) = .empty;
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
                    .tier = try alloc.dupe(u8, inputs.tier),
                    .optimize = try alloc.dupe(u8, inputs.optimize),
                    .filter = try alloc.dupe(u8, inputs.filter),
                    .fail_fast = inputs.fail_fast,
                    .extra_args_packed = try alloc.dupe(u8, inputs.extra_args_packed),
                });
                idx += 1;
            }
        } else {
            try refs.append(alloc, .{
                .order_index = 0,
                .repo_dir = try alloc.dupe(u8, canonical_root),
                .tier = try alloc.dupe(u8, inputs.tier),
                .optimize = try alloc.dupe(u8, inputs.optimize),
                .filter = try alloc.dupe(u8, inputs.filter),
                .fail_fast = inputs.fail_fast,
                .extra_args_packed = try alloc.dupe(u8, inputs.extra_args_packed),
            });
        }

        return try refs.toOwnedSlice(alloc);
    }
};
