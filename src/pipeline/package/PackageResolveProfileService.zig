const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental map): Applies `hive.json` `packaging` + `--profile` precedence
/// and resolves deliverable output coordinates in `zig-out/dist/`.
pub const PackageResolveProfileService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(_: *PackageResolveProfileService, alloc: std.mem.Allocator, mod_ref: types.PackageModuleRef) !types.PackagePlanTask {
        const fs = @import("parabellum_platform").fs.nativeFs();

        var mod_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, mod_ref.repo_dir);
        defer mod_cfg.deinit();
        const mc = mod_cfg.value();
        const meta = try build_types.resolveProjectNameAndVersion(alloc, fs, mod_ref.repo_dir, mc.name, mc.version);

        var fmt_val: config.hive_json.PackageFormat = if (mc.packaging) |p| p.default_format else .so;
        var resolved_target: []const u8 = mod_ref.target;
        var strip = mod_ref.strip;
        var lto = mod_ref.lto;
        var sources = mod_ref.sources or (if (mc.packaging) |p| p.sources else false);
        var docs = mod_ref.docs or (if (mc.packaging) |p| p.docs else false);

        var packagers_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer packagers_buf.deinit(alloc);

        if (mc.packaging) |pkg| {
            if (mod_ref.profile_name.len > 0) {
                if (pkg.profiles.map.get(mod_ref.profile_name)) |prof| {
                    if (prof.format) |pf| fmt_val = pf;
                    if (!mod_ref.target_explicit) {
                        if (prof.target) |pt| resolved_target = pt;
                    }
                    if (prof.strip) |ps| strip = strip or ps;
                    if (prof.lto) |pl| lto = lto or pl;
                    if (prof.sources) |psrc| sources = sources or psrc;
                    if (prof.docs) |pdocs| docs = docs or pdocs;
                    for (prof.packagers) |pname| {
                        try packagers_buf.appendSlice(alloc, pname);
                        try packagers_buf.append(alloc, '\n');
                    }
                }
            }
        }

        if (mod_ref.format_override.len > 0) {
            fmt_val = std.meta.stringToEnum(config.hive_json.PackageFormat, mod_ref.format_override) orelse fmt_val;
        }
        if (mod_ref.packager_override.len > 0) {
            try packagers_buf.appendSlice(alloc, mod_ref.packager_override);
            try packagers_buf.append(alloc, '\n');
        }

        const dist_dir = try std.fs.path.join(alloc, &.{ mod_ref.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.dist });
        const out_filename = try types.formatOutputFilename(alloc, meta.name, meta.version, resolved_target, fmt_val);
        defer alloc.free(out_filename);
        const output_path = try std.fs.path.join(alloc, &.{ dist_dir, out_filename });

        return .{
            .order_index = mod_ref.order_index,
            .repo_dir = try alloc.dupe(u8, mod_ref.repo_dir),
            .module_name = meta.name,
            .version = meta.version,
            .target = try alloc.dupe(u8, resolved_target),
            .format = @tagName(fmt_val),
            .strip = strip,
            .lto = lto,
            .sources = sources,
            .docs = docs,
            .verify_abi = mod_ref.verify_abi,
            .dist_dir = dist_dir,
            .output_path = output_path,
            .packages_dir = try alloc.dupe(u8, mod_ref.packages_dir),
            .packagers_packed = try alloc.dupe(u8, packagers_buf.items),
        };
    }
};
