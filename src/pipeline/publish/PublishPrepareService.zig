const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const build_types = @import("../build/types.zig");
const fetch_types = @import("../fetch/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental flat-map): Resolves target repository and packaged assets
/// in `zig-out/{dist,lib,bin}` per module, emitting `[]const PublishAssetTask`.
pub const PublishPrepareService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PublishPrepareService, alloc: std.mem.Allocator, mod_ref: types.PublishModuleRef) ![]const types.PublishAssetTask {
        const fs = self.services.filesystem;

        var mod_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, mod_ref.repo_dir);
        defer mod_cfg.deinit();
        const mc = mod_cfg.value();
        const meta = try build_types.resolveProjectNameAndVersion(alloc, fs, mod_ref.repo_dir, mc.name, mc.version);
        defer alloc.free(meta.version);

        const base_ver = if (mod_ref.version_override.len > 0) mod_ref.version_override else meta.version;
        const eff_ver = try config.HiveHome.effectiveVersion(alloc, base_ver, mod_ref.snapshot);

        const repo_opt = fetch_types.findRepository(
            mc.repositories,
            if (mod_ref.repo_name_override.len > 0) mod_ref.repo_name_override else null,
        ) orelse {
            self.logger.err("No matching repository configured in hive.json for '{s}'", .{meta.name});
            return error.MissingPublishRepository;
        };

        const repo_loc = repo_opt.url orelse repo_opt.owner orelse repo_opt.path orelse "";
        const auth_env = repo_opt.auth_env orelse "";

        var tasks: std.ArrayListUnmanaged(types.PublishAssetTask) = .empty;
        errdefer tasks.deinit(alloc);

        const scan_subdirs = [_][]const u8{ constants.ZigDirs.dist, constants.ZigDirs.lib, constants.ZigDirs.bin };
        for (scan_subdirs) |sub| {
            const dir_path = try std.fs.path.join(alloc, &.{ mod_ref.repo_dir, constants.ZigDirs.zig_out, sub });
            defer alloc.free(dir_path);

            const entries = fs.listDir(alloc, dir_path) catch continue;
            defer platform.PlatformFs.freeDirEntries(alloc, entries);

            for (entries) |ent| {
                if (ent.kind != .file) continue;
                try tasks.append(alloc, .{
                    .order_index = mod_ref.order_index,
                    .module_name = try alloc.dupe(u8, meta.name),
                    .effective_version = try alloc.dupe(u8, eff_ver),
                    .target = try alloc.dupe(u8, mod_ref.target),
                    .repo_name = try alloc.dupe(u8, repo_opt.name),
                    .repo_type = @tagName(repo_opt.type),
                    .repo_url_or_path = try alloc.dupe(u8, repo_loc),
                    .auth_env = try alloc.dupe(u8, auth_env),
                    .src_path = try std.fs.path.join(alloc, &.{ dir_path, ent.name }),
                    .file_name = try alloc.dupe(u8, ent.name),
                    .force = mod_ref.force,
                    .dry_run = mod_ref.dry_run,
                    .snapshot = mod_ref.snapshot,
                });
            }
        }

        return try tasks.toOwnedSlice(alloc);
    }
};
