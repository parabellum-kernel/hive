const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../../../constants.zig");
const types = @import("../types.zig");
const PackageAssemblerMod = @import("PackageAssembler.zig");

const PackageAssembler = PackageAssemblerMod.PackageAssembler;

pub fn assembler() PackageAssembler {
    return .{ .vtable = &vtable };
}

fn assemble(
    _: ?*anyopaque,
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    task: types.PackagePlanTask,
) !void {
    const fs = services.filesystem;
    try fs.mkdirAll(alloc, task.dist_dir);

    const zig_out = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.zig_out });
    defer alloc.free(zig_out);

    var res = try services.runner.run(alloc, .{
        .argv = &.{ "tar", "-czf", task.output_path, "-C", zig_out, constants.ZigDirs.bin, constants.ZigDirs.lib },
        .cwd = task.repo_dir,
    });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.TarPackageFailed;
}

const vtable = PackageAssembler.VTable{ .assemble = assemble };
