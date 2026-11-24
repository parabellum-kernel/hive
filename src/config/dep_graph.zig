const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../constants.zig");
const hive_home = @import("hive_home.zig");
const hive_json = @import("hive_json.zig");

pub const ResolvedDep = struct {
    name: []u8,
    version: []u8,
};

pub fn freeResolvedDeps(alloc: std.mem.Allocator, deps: []ResolvedDep) void {
    for (deps) |d| {
        alloc.free(d.name);
        alloc.free(d.version);
    }
    alloc.free(deps);
}

fn effectiveDepVersion(cfg: hive_json.HiveJsonSchema, name: []const u8, declared_version: []const u8) []const u8 {
    if (cfg.dependency_overrides.map.get(name)) |ov| return ov.version;
    return declared_version;
}

fn loadDepManifest(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    packages_dir: []const u8,
    coord: []const u8,
    version: []const u8,
    target: []const u8,
) ?std.json.Parsed(hive_home.PackageManifest) {
    const dir = hive_home.joinPackageTargetDir(alloc, packages_dir, coord, version, target) catch return null;
    defer alloc.free(dir);
    const manifest_path = std.fs.path.join(alloc, &.{ dir, constants.HivePaths.manifest_file }) catch return null;
    defer alloc.free(manifest_path);
    if (!fs.exists(alloc, manifest_path)) return null;
    const bytes = fs.readFileAlloc(alloc, manifest_path, 1024 * 1024) catch return null;
    defer alloc.free(bytes);
    return std.json.parseFromSlice(hive_home.PackageManifest, alloc, bytes, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch null;
}

/// Resolves the transitive dependency closure starting from `root_cfg`, honoring
/// `dependency_overrides` and failing fast with `error.DependencyVersionConflict` on mismatches.
pub fn resolveTransitiveDependencies(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    packages_dir: []const u8,
    target: []const u8,
    root_cfg: hive_json.HiveJsonSchema,
) ![]ResolvedDep {
    var resolved: std.StringHashMapUnmanaged([]u8) = .empty;
    defer {
        var it = resolved.iterator();
        while (it.next()) |e| {
            alloc.free(e.key_ptr.*);
            alloc.free(e.value_ptr.*);
        }
        resolved.deinit(alloc);
    }

    var queue: std.ArrayListUnmanaged(ResolvedDep) = .empty;
    defer queue.deinit(alloc);

    var root_it = root_cfg.dependencies.map.iterator();
    while (root_it.next()) |entry| {
        const name = entry.key_ptr.*;
        const ver = effectiveDepVersion(root_cfg, name, entry.value_ptr.version);
        if (resolved.get(name)) |existing| {
            if (!std.mem.eql(u8, existing, ver)) return error.DependencyVersionConflict;
            continue;
        }
        const k = try alloc.dupe(u8, name);
        errdefer alloc.free(k);
        const v = try alloc.dupe(u8, ver);
        errdefer alloc.free(v);
        try resolved.put(alloc, k, v);
        try queue.append(alloc, .{ .name = k, .version = v });
    }

    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const cur = queue.items[head];
        var parsed_opt = loadDepManifest(alloc, fs, packages_dir, cur.name, cur.version, target);
        defer if (parsed_opt) |*p| p.deinit();

        if (parsed_opt) |p| {
            for (p.value.dependencies) |tdep| {
                const eff_ver = effectiveDepVersion(root_cfg, tdep.name, tdep.version);
                if (resolved.get(tdep.name)) |existing| {
                    if (!std.mem.eql(u8, existing, eff_ver)) {
                        return error.DependencyVersionConflict;
                    }
                    continue;
                }
                const k = try alloc.dupe(u8, tdep.name);
                errdefer alloc.free(k);
                const v = try alloc.dupe(u8, eff_ver);
                errdefer alloc.free(v);
                try resolved.put(alloc, k, v);
                try queue.append(alloc, .{ .name = k, .version = v });
            }
        }
    }

    var out = try alloc.alloc(ResolvedDep, queue.items.len);
    for (queue.items, 0..) |item, i| {
        out[i] = .{
            .name = try alloc.dupe(u8, item.name),
            .version = try alloc.dupe(u8, item.version),
        };
    }
    return out;
}

/// Validates build configuration compatibility across collected dependencies and returns
/// the effective LTO setting (`true` if all inputs use LTO bitcode, failing fast on mixed LTO).
pub fn validateBuildConfigCompatibility(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    packages_dir: []const u8,
    target: []const u8,
    deps: []const ResolvedDep,
    expected_meta: ?hive_home.BuildConfigFingerprint,
    require_lto: bool,
) !bool {
    var saw_lto_true = if (expected_meta) |m| m.lto else false;
    var saw_lto_false = if (expected_meta) |m| !m.lto else false;
    if (require_lto and expected_meta != null and !expected_meta.?.lto) {
        return error.MixedLtoConfiguration;
    }

    for (deps) |dep| {
        var parsed_opt = loadDepManifest(alloc, fs, packages_dir, dep.name, dep.version, target);
        defer if (parsed_opt) |*p| p.deinit();
        const p = parsed_opt orelse continue;
        const dep_bc = p.value.build_config orelse continue;

        if (dep_bc.lto) {
            saw_lto_true = true;
        } else {
            saw_lto_false = true;
        }

        if (require_lto and !dep_bc.lto) {
            return error.MixedLtoConfiguration;
        }

        if (expected_meta) |exp| {
            if (!std.mem.eql(u8, dep_bc.config_hash, exp.config_hash)) {
                if (dep_bc.lto != exp.lto) return error.MixedLtoConfiguration;
                return error.IncompatibleBuildConfig;
            }
        }
    }

    if (saw_lto_true and saw_lto_false) {
        return error.MixedLtoConfiguration;
    }
    return require_lto or saw_lto_true;
}
