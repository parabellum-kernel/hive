const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Discovers target project/workspace module paths and assigns deterministic `order_index`.
pub const BuildDiscoverModulesService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *BuildDiscoverModulesService, alloc: std.mem.Allocator, inputs: types.BuildInputs) ![]const types.BuildModuleRef {
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

        var refs: std.ArrayListUnmanaged(types.BuildModuleRef) = .empty;
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
                    .optimize = try alloc.dupe(u8, inputs.optimize),
                    .target = try alloc.dupe(u8, resolved_target),
                    .cpu = try alloc.dupe(u8, inputs.cpu),
                    .linkage = try alloc.dupe(u8, inputs.linkage),
                    .lto = inputs.lto,
                    .bundle_compiler_rt = inputs.bundle_compiler_rt,
                    .verify_abi = inputs.verify_abi,
                    .packages_dir = try alloc.dupe(u8, home.packages_dir),
                    .extra_args_packed = try alloc.dupe(u8, inputs.extra_args_packed),
                });
                idx += 1;
            }
        } else {
            try refs.append(alloc, .{
                .order_index = 0,
                .repo_dir = try alloc.dupe(u8, canonical_root),
                .optimize = try alloc.dupe(u8, inputs.optimize),
                .target = try alloc.dupe(u8, resolved_target),
                .cpu = try alloc.dupe(u8, inputs.cpu),
                .linkage = try alloc.dupe(u8, inputs.linkage),
                .lto = inputs.lto,
                .bundle_compiler_rt = inputs.bundle_compiler_rt,
                .verify_abi = inputs.verify_abi,
                .packages_dir = try alloc.dupe(u8, home.packages_dir),
                .extra_args_packed = try alloc.dupe(u8, inputs.extra_args_packed),
            });
        }

        if (refs.items.len == 0) {
            self.logger.err("No buildable modules matched in '{s}'", .{canonical_root});
            return error.NoModulesMatched;
        }

        return try refs.toOwnedSlice(alloc);
    }
};
