const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 1: Validates root safety and emits top-level scan roots (`[]const CleanScanRoot`)
/// so directory tree traversal and snapshot scanning execute in parallel.
pub const CleanDiscoverRootsService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *CleanDiscoverRootsService, alloc: std.mem.Allocator, inputs: types.CleanInputs) ![]const types.CleanScanRoot {
        const fs = self.services.filesystem;
        const env = self.services.environment;

        const canonical = try fs.realpath(alloc, inputs.target);
        defer alloc.free(canonical);

        if (types.isUnsafeRoot(alloc, fs, env, canonical)) {
            self.logger.err("Refusing to clean unsafe or non-project root: {s}", .{canonical});
            return error.UnsafeCleanRoot;
        }

        var roots: std.ArrayListUnmanaged(types.CleanScanRoot) = .empty;
        errdefer roots.deinit(alloc);

        var idx: i64 = 0;
        if (fs.listDir(alloc, canonical)) |entries| {
            defer platform.PlatformFs.freeDirEntries(alloc, entries);

            for (entries) |ent| {
                if (ent.kind != .directory) continue;
                if (std.mem.eql(u8, ent.name, constants.ZigDirs.dot_git)) continue;
                if (std.mem.eql(u8, ent.name, constants.ZigDirs.zig_pkg) and !inputs.include_zig_pkg) continue;

                const child = try std.fs.path.join(alloc, &.{ canonical, ent.name });
                const is_cache = std.mem.eql(u8, ent.name, constants.ZigDirs.dot_zig_cache) or
                    std.mem.eql(u8, ent.name, constants.ZigDirs.zig_cache);
                const is_out = inputs.include_out and std.mem.eql(u8, ent.name, constants.ZigDirs.zig_out);

                try roots.append(alloc, .{
                    .order_index = idx,
                    .dir_path = child,
                    .kind = if (is_cache or is_out) @tagName(types.CleanRootKind.root_match) else @tagName(types.CleanRootKind.workspace_subdir),
                    .dry_run = inputs.dry_run,
                    .include_out = inputs.include_out,
                    .include_zig_pkg = inputs.include_zig_pkg,
                });
                idx += 1;
            }
        } else |_| {}

        if (inputs.snapshots) {
            var home = try config.HiveHome.resolve(alloc, env, .{
                .artifact_repository_dir = if (inputs.repo_dir.len > 0) inputs.repo_dir else null,
            });
            defer home.deinit(alloc);

            if (fs.listDir(alloc, home.packages_dir)) |pkg_entries| {
                defer platform.PlatformFs.freeDirEntries(alloc, pkg_entries);

                for (pkg_entries) |pkg_ent| {
                    if (pkg_ent.kind != .directory) continue;
                    try roots.append(alloc, .{
                        .order_index = idx,
                        .dir_path = try std.fs.path.join(alloc, &.{ home.packages_dir, pkg_ent.name }),
                        .kind = @tagName(types.CleanRootKind.snapshot_pkg),
                        .dry_run = inputs.dry_run,
                        .include_out = inputs.include_out,
                        .include_zig_pkg = inputs.include_zig_pkg,
                    });
                    idx += 1;
                }
            } else |_| {}
        }

        return try roots.toOwnedSlice(alloc);
    }
};
