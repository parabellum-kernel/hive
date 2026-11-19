const std = @import("std");
const platform = @import("parabellum_platform");
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
    if (archives.items.len == 0) return error.NoStaticArchivesToPackage;

    try PackageAssemblerMod.linkWithZigCc(alloc, services, task, archives.items, true);
}

const vtable = PackageAssembler.VTable{ .assemble = assemble };
