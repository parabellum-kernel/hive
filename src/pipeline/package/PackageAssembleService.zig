const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");
const PackageAssembler = @import("assembler/PackageAssembler.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Assembles deliverable via `PackageAssembler` VTable,
/// optionally bundles `-sources.tar.gz` / `-docs.tar.gz`, and verifies `.so` ABI magic.
pub const PackageAssembleService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PackageAssembleService, alloc: std.mem.Allocator, task: types.PackagePlanTask) !types.PackageAssembled {
        const fs = self.services.filesystem;
        const fmt = std.meta.stringToEnum(config.hive_json.PackageFormat, task.format) orelse .so;
        const assembler = PackageAssembler.selectAssembler(fmt);
        try assembler.assemble(alloc, self.services, task);

        if (fmt == .so and task.verify_abi) {
            const data = try fs.readFileAlloc(alloc, task.output_path, 256 * 1024 * 1024);
            defer alloc.free(data);
            if (!build_types.hasValidBinaryMagic(data)) {
                self.logger.err("Assembled shared library has invalid binary header: {s}", .{task.output_path});
                return error.InvalidBinaryArtifact;
            }
        }

        var sources_tarball: []const u8 = "";
        if (task.sources) {
            const src_name = try std.fmt.allocPrint(alloc, "{s}-sources.tar.gz", .{task.module_name});
            defer alloc.free(src_name);
            const src_dest = try std.fs.path.join(alloc, &.{ task.dist_dir, src_name });
            var res = try self.services.runner.run(alloc, .{
                .argv = &.{ "tar", "-czf", src_dest, "--exclude=.zig-cache", "--exclude=zig-out", "--exclude=.git", "-C", task.repo_dir, "." },
            });
            defer res.deinit(alloc);
            if (res.exit_code == 0) sources_tarball = src_dest else alloc.free(src_dest);
        }

        var docs_tarball: []const u8 = "";
        if (task.docs) {
            const docs_dir = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.docs });
            defer alloc.free(docs_dir);
            if (fs.exists(alloc, docs_dir)) {
                const docs_name = try std.fmt.allocPrint(alloc, "{s}-docs.tar.gz", .{task.module_name});
                defer alloc.free(docs_name);
                const docs_dest = try std.fs.path.join(alloc, &.{ task.dist_dir, docs_name });
                var res = try self.services.runner.run(alloc, .{
                    .argv = &.{ "tar", "-czf", docs_dest, "-C", docs_dir, "." },
                });
                defer res.deinit(alloc);
                if (res.exit_code == 0) docs_tarball = docs_dest else alloc.free(docs_dest);
            }
        }

        return .{
            .order_index = task.order_index,
            .repo_dir = try alloc.dupe(u8, task.repo_dir),
            .module_name = try alloc.dupe(u8, task.module_name),
            .version = try alloc.dupe(u8, task.version),
            .target = try alloc.dupe(u8, task.target),
            .format = try alloc.dupe(u8, task.format),
            .dist_dir = try alloc.dupe(u8, task.dist_dir),
            .output_path = try alloc.dupe(u8, task.output_path),
            .sources_tarball = sources_tarball,
            .docs_tarball = docs_tarball,
            .packagers_packed = try alloc.dupe(u8, task.packagers_packed),
        };
    }
};
