const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const git = @import("../../git.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental map): Runs pre-flight Git, SemVer, tag, and `.path` dependency checks.
pub const ReleasePreflightService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *ReleasePreflightService, alloc: std.mem.Allocator, mod_ref: types.ReleaseModuleRef) !types.ReleasePreparedModule {
        const fs = self.services.filesystem;
        const env = self.services.environment;

        var mod_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, mod_ref.repo_dir);
        defer mod_cfg.deinit();
        const mc = mod_cfg.value();
        const meta = try build_types.resolveProjectNameAndVersion(alloc, fs, mod_ref.repo_dir, mc.name, mc.version);

        const release_branch = if (mc.release) |r| r.branch else constants.Defaults.release_branch;

        const target_ver = if (mod_ref.explicit_version.len > 0)
            try alloc.dupe(u8, mod_ref.explicit_version)
        else if (mod_ref.bump.len > 0) blk: {
            const bk = std.meta.stringToEnum(types.BumpKind, mod_ref.bump) orelse return error.InvalidBumpKind;
            break :blk try types.bumpSemVer(alloc, meta.version, bk);
        } else try alloc.dupe(u8, meta.version);

        if (!types.isValidReleaseSemVer(target_ver)) {
            self.logger.err("Invalid release SemVer '{s}' (must be X.Y.Z without -snapshot)", .{target_ver});
            return error.InvalidReleaseSemVer;
        }

        const zon_path = try std.fs.path.join(alloc, &.{ mod_ref.repo_dir, constants.HivePaths.build_zig_zon });
        defer alloc.free(zon_path);
        if (fs.exists(alloc, zon_path)) {
            const zon_bytes = try fs.readFileAlloc(alloc, zon_path, 2 * 1024 * 1024);
            defer alloc.free(zon_bytes);
            if (types.hasRelativePathDep(zon_bytes)) {
                self.logger.err("Refusing release: '{s}' contains local '../' .path dependencies", .{zon_path});
                return error.RelativePathDependencyInRelease;
            }
        }

        var gc = try git.GitClient.init(alloc, env, self.services.runner);
        defer gc.deinit(alloc);

        if (!mod_ref.dry_run) {
            const clean = try gc.isClean(alloc, mod_ref.repo_dir);
            if (!clean) {
                self.logger.err("Working tree is dirty in '{s}'", .{mod_ref.repo_dir});
                return error.DirtyWorkingTree;
            }
        }

        const cur_branch = try gc.currentBranch(alloc, mod_ref.repo_dir);
        defer alloc.free(cur_branch);
        if (!std.mem.eql(u8, cur_branch, release_branch)) {
            self.logger.err("Expected branch '{s}', found '{s}'", .{ release_branch, cur_branch });
            return error.WrongReleaseBranch;
        }

        const tag_name = try std.fmt.allocPrint(alloc, "v{s}", .{target_ver});
        defer alloc.free(tag_name);
        if (try gc.tagExists(alloc, mod_ref.repo_dir, tag_name)) {
            self.logger.err("Tag '{s}' already exists locally", .{tag_name});
            return error.TagAlreadyExists;
        }

        return .{
            .order_index = mod_ref.order_index,
            .repo_dir = try alloc.dupe(u8, mod_ref.repo_dir),
            .name = meta.name,
            .current_version = meta.version,
            .target_version = target_ver,
            .release_branch = try alloc.dupe(u8, release_branch),
            .dry_run = mod_ref.dry_run,
        };
    }
};
