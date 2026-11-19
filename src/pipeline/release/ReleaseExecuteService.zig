const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");
const git = @import("../../git.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Bumps versions in `hive.json` / `build.zig.zon`,
/// commits, creates annotated tag `v<version>`, and pushes to `origin` (unless `--dry-run`).
pub const ReleaseExecuteService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *ReleaseExecuteService, alloc: std.mem.Allocator, mod: types.ReleasePreparedModule) !types.ReleaseResult {
        const fs = self.services.filesystem;
        const env = self.services.environment;
        const tag_name = try std.fmt.allocPrint(alloc, "v{s}", .{mod.target_version});

        if (!mod.dry_run) {
            if (!std.mem.eql(u8, mod.current_version, mod.target_version)) {
                try types.updateHiveJsonVersion(alloc, fs, mod.repo_dir, mod.target_version);

                const zon_path = try std.fs.path.join(alloc, &.{ mod.repo_dir, constants.HivePaths.build_zig_zon });
                defer alloc.free(zon_path);
                if (fs.exists(alloc, zon_path)) {
                    const raw_zon = try fs.readFileAlloc(alloc, zon_path, 2 * 1024 * 1024);
                    defer alloc.free(raw_zon);
                    const updated_zon = try types.updateZonVersion(alloc, raw_zon, mod.target_version);
                    defer alloc.free(updated_zon);
                    try fs.atomicWriteFile(alloc, zon_path, updated_zon, false);
                }

                var gc = try git.GitClient.init(alloc, env, self.services.runner);
                defer gc.deinit(alloc);
                const commit_msg = try std.fmt.allocPrint(alloc, "chore(release): {s}", .{tag_name});
                defer alloc.free(commit_msg);
                try gc.commit(alloc, mod.repo_dir, commit_msg);
                try gc.createAnnotatedTag(alloc, mod.repo_dir, tag_name, commit_msg);
                try gc.pushWithTags(alloc, mod.repo_dir, "origin", mod.release_branch);
            } else {
                var gc = try git.GitClient.init(alloc, env, self.services.runner);
                defer gc.deinit(alloc);
                const tag_msg = try std.fmt.allocPrint(alloc, "Release {s}", .{tag_name});
                defer alloc.free(tag_msg);
                try gc.createAnnotatedTag(alloc, mod.repo_dir, tag_name, tag_msg);
                try gc.pushWithTags(alloc, mod.repo_dir, "origin", mod.release_branch);
            }
        }

        return .{
            .order_index = mod.order_index,
            .name = try alloc.dupe(u8, mod.name),
            .target_version = try alloc.dupe(u8, mod.target_version),
            .tag_name = tag_name,
            .dry_run = mod.dry_run,
        };
    }
};
