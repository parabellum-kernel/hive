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

    const resolved_deps = try config.dep_graph.resolveTransitiveDependencies(
        alloc,
        fs,
        task.packages_dir,
        task.target,
        cfg,
    );
    defer config.dep_graph.freeResolvedDeps(alloc, resolved_deps);

    for (resolved_deps) |dep| {
        const dep_dir = try std.fs.path.join(alloc, &.{ task.packages_dir, dep.name, dep.version, task.target });
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
    var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, services.filesystem, task.repo_dir);
    defer loaded_cfg.deinit();
    const cfg = loaded_cfg.value();

    const resolved_deps = try config.dep_graph.resolveTransitiveDependencies(
        alloc,
        services.filesystem,
        task.packages_dir,
        task.target,
        cfg,
    );
    defer config.dep_graph.freeResolvedDeps(alloc, resolved_deps);

    var build_meta = config.hive_home.LoadedBuildMeta.loadFromRepo(alloc, services.filesystem, task.repo_dir);
    defer build_meta.deinit();

    const effective_lto = try config.dep_graph.validateBuildConfigCompatibility(
        alloc,
        services.filesystem,
        task.packages_dir,
        task.target,
        resolved_deps,
        build_meta.value(),
        task.lto,
    );

    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(alloc);

    var owned_args: std.ArrayListUnmanaged([]u8) = .empty;
    defer {
        for (owned_args.items) |a| alloc.free(a);
        owned_args.deinit(alloc);
    }

    try argv.appendSlice(alloc, &.{ constants.TestSteps.zig_bin, "cc" });
    if (task.target.len > 0 and
        !std.mem.eql(u8, task.target, constants.Defaults.native_target) and
        !std.mem.eql(u8, task.target, services.environment.nativeTargetTriple()))
    {
        try argv.appendSlice(alloc, &.{ "-target", task.target });
    }
    if (shared) try argv.append(alloc, "-shared");
    if (task.strip) try argv.append(alloc, "-s");
    if (effective_lto) try argv.append(alloc, "-flto");

    try appendWholeArchiveFlags(alloc, &argv, &owned_args, task.target, archives);

    var export_tmp_dir: ?[]u8 = null;
    defer if (export_tmp_dir) |d| {
        services.filesystem.deleteTree(alloc, d) catch {};
        alloc.free(d);
    };

    if (shared) {
        if (cfg.abi) |abi| {
            if (try createAbiExportScript(alloc, services.filesystem, task.dist_dir, task.target, abi)) |exp| {
                export_tmp_dir = exp.tmp_dir;
                try owned_args.append(alloc, exp.linker_flag);
                try argv.append(alloc, exp.linker_flag);
            }
        }
    }

    if (cfg.packaging) |pkg| {
        for (pkg.link_libs) |lib| {
            const flag = try std.fmt.allocPrint(alloc, "-l{s}", .{lib});
            try owned_args.append(alloc, flag);
            try argv.append(alloc, flag);
        }
    }

    try argv.appendSlice(alloc, &.{ "-o", task.output_path });
    var res = try services.runner.run(alloc, .{ .argv = argv.items, .cwd = task.repo_dir });
    defer res.deinit(alloc);
    if (res.exit_code != 0) {
        if (res.stderr.len > 0) services.terminal.writeStderr(res.stderr);
        return error.PackageLinkFailed;
    }
}

/// Appends target-family whole-archive linker flags so unreferenced `export fn` / `linksection` symbols survive linking.
pub fn appendWholeArchiveFlags(
    alloc: std.mem.Allocator,
    argv: *std.ArrayListUnmanaged([]const u8),
    owned_args: *std.ArrayListUnmanaged([]u8),
    target: []const u8,
    archives: []const []const u8,
) !void {
    switch (types.targetFamily(target)) {
        .elf => {
            try argv.append(alloc, "-Wl,--whole-archive");
            for (archives) |a| try argv.append(alloc, a);
            try argv.append(alloc, "-Wl,--no-whole-archive");
        },
        .macho => {
            for (archives) |a| {
                const flag = try std.fmt.allocPrint(alloc, "-Wl,-force_load,{s}", .{a});
                try owned_args.append(alloc, flag);
                try argv.append(alloc, flag);
            }
        },
        .coff => {
            for (archives) |a| {
                const flag = try std.fmt.allocPrint(alloc, "-Wl,/WHOLEARCHIVE:{s}", .{a});
                try owned_args.append(alloc, flag);
                try argv.append(alloc, flag);
            }
        },
    }
}

pub const AbiExportScript = struct {
    tmp_dir: []u8,
    linker_flag: []u8,
};

/// Generates a link-time symbol visibility script (`exports.map` for ELF, `exports.txt` for Mach-O)
/// from `hive.json` `abi` contracts so non-ABI symbols are hidden from `.dynsym` at link time.
pub fn createAbiExportScript(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    dist_dir: []const u8,
    target: []const u8,
    abi: config.hive_json.AbiSpec,
) !?AbiExportScript {
    if (abi.required_symbols.len == 0 and abi.any_of_symbols.len == 0) return null;

    const family = types.targetFamily(target);
    if (family == .coff) return null;

    const tmp_dir = try std.fs.path.join(alloc, &.{ dist_dir, ".hive_exports_tmp" });
    errdefer alloc.free(tmp_dir);
    try fs.mkdirAll(alloc, tmp_dir);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    switch (family) {
        .elf => {
            try buf.appendSlice(alloc, "{\n  global:\n");
            for (abi.required_symbols) |sym| {
                try buf.appendSlice(alloc, "    ");
                try buf.appendSlice(alloc, sym);
                try buf.appendSlice(alloc, ";\n");
            }
            for (abi.any_of_symbols) |sym| {
                try buf.appendSlice(alloc, "    ");
                try buf.appendSlice(alloc, sym);
                try buf.appendSlice(alloc, ";\n");
            }
            try buf.appendSlice(alloc, "  local:\n    *;\n};\n");

            const script_path = try std.fs.path.join(alloc, &.{ tmp_dir, "exports.map" });
            defer alloc.free(script_path);
            try fs.atomicWriteFile(alloc, script_path, buf.items, false);
            const flag = try std.fmt.allocPrint(alloc, "-Wl,--version-script={s}", .{script_path});
            return .{ .tmp_dir = tmp_dir, .linker_flag = flag };
        },
        .macho => {
            for (abi.required_symbols) |sym| {
                try buf.append(alloc, '_');
                try buf.appendSlice(alloc, sym);
                try buf.append(alloc, '\n');
            }
            for (abi.any_of_symbols) |sym| {
                try buf.append(alloc, '_');
                try buf.appendSlice(alloc, sym);
                try buf.append(alloc, '\n');
            }

            const script_path = try std.fs.path.join(alloc, &.{ tmp_dir, "exports.txt" });
            defer alloc.free(script_path);
            try fs.atomicWriteFile(alloc, script_path, buf.items, false);
            const flag = try std.fmt.allocPrint(alloc, "-Wl,-exported_symbols_list,{s}", .{script_path});
            return .{ .tmp_dir = tmp_dir, .linker_flag = flag };
        },
        .coff => unreachable,
    }
}
