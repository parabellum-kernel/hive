const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Discovers target project/workspace module paths for packaging.
pub const PackageDiscoverService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PackageDiscoverService, alloc: std.mem.Allocator, inputs: types.PackageInputs) ![]const types.PackageModuleRef {
        const fs = self.services.filesystem;
        const env = self.services.environment;

        const canonical_root = try fs.realpath(alloc, inputs.project_dir);
        defer alloc.free(canonical_root);

        var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, canonical_root);
        defer loaded_cfg.deinit();
        const cfg = loaded_cfg.value();

        var home = try config.HiveHome.resolve(alloc, env, .{
            .artifact_repository_dir = if (inputs.artifact_repository_dir.len > 0) inputs.artifact_repository_dir else null,
        });
        defer home.deinit(alloc);

        const resolved_target = if (std.mem.eql(u8, inputs.target, constants.Defaults.native_target) or inputs.target.len == 0)
            env.nativeTargetTriple()
        else
            inputs.target;

        var refs: std.ArrayListUnmanaged(types.PackageModuleRef) = .empty;
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
                    .format_override = try alloc.dupe(u8, inputs.format),
                    .strip = inputs.strip,
                    .lto = inputs.lto,
                    .sources = inputs.sources,
                    .docs = inputs.docs,
                    .packager_override = try alloc.dupe(u8, inputs.packager),
                    .profile_name = try alloc.dupe(u8, inputs.profile),
                    .verify_abi = inputs.verify_abi,
                    .target = try alloc.dupe(u8, resolved_target),
                    .packages_dir = try alloc.dupe(u8, home.packages_dir),
                });
                idx += 1;
            }
        } else {
            try refs.append(alloc, .{
                .order_index = 0,
                .repo_dir = try alloc.dupe(u8, canonical_root),
                .format_override = try alloc.dupe(u8, inputs.format),
                .strip = inputs.strip,
                .lto = inputs.lto,
                .sources = inputs.sources,
                .docs = inputs.docs,
                .packager_override = try alloc.dupe(u8, inputs.packager),
                .profile_name = try alloc.dupe(u8, inputs.profile),
                .verify_abi = inputs.verify_abi,
                .target = try alloc.dupe(u8, resolved_target),
                .packages_dir = try alloc.dupe(u8, home.packages_dir),
            });
        }

        if (refs.items.len == 0) {
            self.logger.err("No packageable modules matched in '{s}'", .{canonical_root});
            return error.NoModulesMatched;
        }

        return try refs.toOwnedSlice(alloc);
    }
};
