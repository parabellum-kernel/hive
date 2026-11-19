const std = @import("std");
const platform = @import("parabellum_platform");
const config = @import("../../../config/mod.zig");
const constants = @import("../../../constants.zig");
const types = @import("../types.zig");

const BinPackageAssembler = @import("BinPackageAssembler.zig");
const SoPackageAssembler = @import("SoPackageAssembler.zig");
const TarPackageAssembler = @import("TarPackageAssembler.zig");

/// Polymorphic deliverable assembler interface (VTable pattern) for `hive package`.
pub const PackageAssembler = struct {
    ptr: ?*anyopaque = null,
    vtable: *const VTable,

    pub const VTable = struct {
        assemble: *const fn (
            ctx: ?*anyopaque,
            alloc: std.mem.Allocator,
            services: platform.PlatformServices,
            task: types.PackagePlanTask,
        ) anyerror!void,
    };

    pub fn assemble(
        self: PackageAssembler,
        alloc: std.mem.Allocator,
        services: platform.PlatformServices,
        task: types.PackagePlanTask,
    ) !void {
        return self.vtable.assemble(self.ptr, alloc, services, task);
    }
};

pub fn selectAssembler(fmt: config.hive_json.PackageFormat) PackageAssembler {
    return switch (fmt) {
        .bin => BinPackageAssembler.assembler(),
        .so => SoPackageAssembler.assembler(),
        .tar => TarPackageAssembler.assembler(),
    };
}

/// Collects static archives (`.a` / `.lib`) from `zig-out/lib/` and declared `hive.json` dependencies.
pub fn collectStaticArchives(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    task: types.PackagePlanTask,
) !std.ArrayListUnmanaged([]u8) {
    var list: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer {
        for (list.items) |p| alloc.free(p);
        list.deinit(alloc);
    }

    const lib_dir = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.lib });
    defer alloc.free(lib_dir);

    if (fs.listDir(alloc, lib_dir)) |entries| {
        defer platform.PlatformFs.freeDirEntries(alloc, entries);
        for (entries) |ent| {
            if (ent.kind != .file) continue;
            for (constants.ArtifactExts.static_exts) |ext| {
                if (std.mem.endsWith(u8, ent.name, ext)) {
                    try list.append(alloc, try std.fs.path.join(alloc, &.{ lib_dir, ent.name }));
                    break;
                }
            }
        }
    } else |_| {}

    var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, task.repo_dir);
    defer loaded_cfg.deinit();
    const cfg = loaded_cfg.value();

    var it = cfg.dependencies.map.iterator();
    while (it.next()) |entry| {
        const dep_dir = try std.fs.path.join(alloc, &.{ task.packages_dir, entry.key_ptr.*, entry.value_ptr.version, task.target });
        defer alloc.free(dep_dir);
        if (fs.listDir(alloc, dep_dir)) |entries| {
            defer platform.PlatformFs.freeDirEntries(alloc, entries);
            for (entries) |ent| {
                if (ent.kind != .file) continue;
                for (constants.ArtifactExts.static_exts) |ext| {
                    if (std.mem.endsWith(u8, ent.name, ext)) {
                        try list.append(alloc, try std.fs.path.join(alloc, &.{ dep_dir, ent.name }));
                        break;
                    }
                }
            }
        } else |_| {}
    }

    return list;
}

pub fn linkWithZigCc(
    alloc: std.mem.Allocator,
    services: platform.PlatformServices,
    task: types.PackagePlanTask,
    archives: []const []u8,
    shared: bool,
) !void {
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(alloc);

    try argv.appendSlice(alloc, &.{ constants.TestSteps.zig_bin, "cc" });
    if (task.target.len > 0 and !std.mem.eql(u8, task.target, constants.Defaults.native_target)) {
        try argv.appendSlice(alloc, &.{ "-target", task.target });
    }
    if (shared) try argv.append(alloc, "-shared");
    if (task.strip) try argv.append(alloc, "-s");
    if (task.lto) try argv.append(alloc, "-flto");

    const is_macos = std.mem.indexOf(u8, task.target, "macos") != null or
        (std.mem.eql(u8, task.target, constants.Defaults.native_target) and @import("builtin").os.tag == .macos);
    if (is_macos) {
        for (archives) |a| {
            try argv.append(alloc, "-Wl,-force_load");
            try argv.append(alloc, a);
        }
    } else {
        try argv.append(alloc, "-Wl,--whole-archive");
        for (archives) |a| try argv.append(alloc, a);
        try argv.append(alloc, "-Wl,--no-whole-archive");
    }

    var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, services.filesystem, task.repo_dir);
    defer loaded_cfg.deinit();
    if (loaded_cfg.value().packaging) |pkg| {
        var libs_buf: std.ArrayListUnmanaged([]u8) = .empty;
        defer {
            for (libs_buf.items) |l| alloc.free(l);
            libs_buf.deinit(alloc);
        }
        for (pkg.link_libs) |lib| {
            const flag = try std.fmt.allocPrint(alloc, "-l{s}", .{lib});
            try libs_buf.append(alloc, flag);
            try argv.append(alloc, flag);
        }
        try argv.appendSlice(alloc, &.{ "-o", task.output_path });
        var res = try services.runner.run(alloc, .{ .argv = argv.items, .cwd = task.repo_dir });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.PackageLinkFailed;
        return;
    }

    try argv.appendSlice(alloc, &.{ "-o", task.output_path });
    var res = try services.runner.run(alloc, .{ .argv = argv.items, .cwd = task.repo_dir });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.PackageLinkFailed;
}
