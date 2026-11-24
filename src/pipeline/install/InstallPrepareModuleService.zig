const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental flat-map): Checks release immutability per module/target
/// and emits `InstallDirScanTask` entries for `zig-out/{lib,bin,dist}` (zero loops).
pub const InstallPrepareModuleService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InstallPrepareModuleService, alloc: std.mem.Allocator, mod_ref: types.InstallModuleRef) ![]const types.InstallDirScanTask {
        const fs = self.services.filesystem;

        var mod_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, mod_ref.repo_dir);
        defer mod_cfg.deinit();
        const mc = mod_cfg.value();
        const meta = try build_types.resolveProjectNameAndVersion(alloc, fs, mod_ref.repo_dir, mc.name, mc.version);
        defer alloc.free(meta.version);

        const group = mc.group orelse constants.Defaults.default_group;
        const eff_ver = try config.HiveHome.effectiveVersion(alloc, meta.version, mod_ref.snapshot);
        const dest_target_dir = try std.fs.path.join(alloc, &.{ mod_ref.packages_dir, group, meta.name, eff_ver, mod_ref.target });
        const dest_ver_dir = try std.fs.path.join(alloc, &.{ mod_ref.packages_dir, group, meta.name, eff_ver });

        if (mod_ref.release and !mod_ref.force) {
            if (mc.artifacts.map.count() > 0) {
                var art_it = mc.artifacts.map.iterator();
                while (art_it.next()) |entry| {
                    const art_dir = try std.fs.path.join(alloc, &.{ mod_ref.packages_dir, group, entry.key_ptr.*, eff_ver, mod_ref.target });
                    defer alloc.free(art_dir);
                    if (fs.exists(alloc, art_dir)) {
                        self.logger.err("Stable release {s}:{s}@{s} ({s}) already exists; pass --force to overwrite", .{
                            group,
                            entry.key_ptr.*,
                            eff_ver,
                            mod_ref.target,
                        });
                        return error.ImmutableReleaseExists;
                    }
                }
            } else if (fs.exists(alloc, dest_target_dir)) {
                self.logger.err("Stable release {s}:{s}@{s} ({s}) already exists; pass --force to overwrite", .{
                    group,
                    meta.name,
                    eff_ver,
                    mod_ref.target,
                });
                return error.ImmutableReleaseExists;
            }
        }

        const buckets = [_]types.InstallBucket{ .lib, .bin, .dist };
        const out = try alloc.alloc(types.InstallDirScanTask, buckets.len);
        inline for (buckets, 0..) |b, idx| {
            const sub = switch (b) {
                .lib => constants.ZigDirs.lib,
                .bin => constants.ZigDirs.bin,
                .dist => constants.ZigDirs.dist,
            };
            out[idx] = .{
                .order_index = mod_ref.order_index,
                .repo_dir = try alloc.dupe(u8, mod_ref.repo_dir),
                .group = try alloc.dupe(u8, group),
                .module_name = try alloc.dupe(u8, meta.name),
                .effective_version = try alloc.dupe(u8, eff_ver),
                .target = try alloc.dupe(u8, mod_ref.target),
                .packages_dir = try alloc.dupe(u8, mod_ref.packages_dir),
                .src_dir = try std.fs.path.join(alloc, &.{ mod_ref.repo_dir, constants.ZigDirs.zig_out, sub }),
                .dest_target_dir = try alloc.dupe(u8, dest_target_dir),
                .dest_ver_dir = try alloc.dupe(u8, dest_ver_dir),
                .bucket = @tagName(b),
            };
        }
        return out;
    }
};
