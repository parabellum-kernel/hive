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

    var archives = try PackageAssemblerMod.collectStaticArchives(alloc, fs, task);
    defer {
        for (archives.items) |p| alloc.free(p);
        archives.deinit(alloc);
    }

    // If no static archives were produced and `zig-out/bin/<name>` exists, copy it directly.
    if (archives.items.len == 0) {
        const bin_name = try std.fmt.allocPrint(alloc, "{s}{s}", .{ task.module_name, services.environment.exeExt() });
        defer alloc.free(bin_name);
        const bin_src = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.bin, bin_name });
        defer alloc.free(bin_src);

        if (!fs.exists(alloc, bin_src)) return error.NoExecutableOrArchiveToPackage;
        const data = try fs.readFileAlloc(alloc, bin_src, 256 * 1024 * 1024);
        defer alloc.free(data);
        try fs.atomicWriteFile(alloc, task.output_path, data, true);
        return;
    }

    try PackageAssemblerMod.linkWithZigCc(alloc, services, task, archives.items, false);
}

const vtable = PackageAssembler.VTable{ .assemble = assemble };
