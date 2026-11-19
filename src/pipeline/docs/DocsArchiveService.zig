const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Optionally bundles `zig-out/docs/` into
/// `zig-out/dist/<name>-docs.tar.gz` when `--package` is set.
pub const DocsArchiveService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *DocsArchiveService, alloc: std.mem.Allocator, item: types.DocsModuleResult) !types.DocsModuleResult {
        if (!item.package_bundle) {
            return .{
                .order_index = item.order_index,
                .module_name = try alloc.dupe(u8, item.module_name),
                .repo_dir = try alloc.dupe(u8, item.repo_dir),
                .out_dir = try alloc.dupe(u8, item.out_dir),
                .tarball_path = "",
                .package_bundle = false,
            };
        }

        const dist_dir = try std.fs.path.join(alloc, &.{ item.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.dist });
        defer alloc.free(dist_dir);
        try self.services.filesystem.mkdirAll(alloc, dist_dir);

        const tarball_name = try std.fmt.allocPrint(alloc, "{s}-docs.tar.gz", .{item.module_name});
        defer alloc.free(tarball_name);
        const tarball_path = try std.fs.path.join(alloc, &.{ dist_dir, tarball_name });

        var res = try self.services.runner.run(alloc, .{
            .argv = &.{ "tar", "-czf", tarball_path, "-C", item.out_dir, "." },
            .cwd = item.repo_dir,
        });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.DocsArchiveFailed;

        return .{
            .order_index = item.order_index,
            .module_name = try alloc.dupe(u8, item.module_name),
            .repo_dir = try alloc.dupe(u8, item.repo_dir),
            .out_dir = try alloc.dupe(u8, item.out_dir),
            .tarball_path = tarball_path,
            .package_bundle = true,
        };
    }
};
