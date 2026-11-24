const std = @import("std");
const hive = @import("hive");

fn writeTestManifest(
    alloc: std.mem.Allocator,
    fs: hive.platform.PlatformFs,
    packages_dir: []const u8,
    coord: []const u8,
    version: []const u8,
    target: []const u8,
    deps: []const hive.config.hive_home.ManifestDependency,
    build_config: ?hive.config.hive_home.BuildConfigFingerprint,
) !void {
    const parsed = hive.config.hive_home.parseCoordinate(coord, hive.constants.Defaults.default_group);
    const dir = try hive.config.hive_home.joinPackageTargetDir(alloc, packages_dir, coord, version, target);
    defer alloc.free(dir);
    try fs.mkdirAll(alloc, dir);

    const manifest = hive.config.PackageManifest{
        .group = parsed.group,
        .name = parsed.artifact,
        .version = version,
        .target = target,
        .installed_at = "2026-11-23T00:00:00Z",
        .build_config = build_config,
        .dependencies = deps,
    };
    const json_bytes = try std.json.Stringify.valueAlloc(alloc, manifest, .{ .whitespace = .indent_2 });
    defer alloc.free(json_bytes);
    const path = try std.fs.path.join(alloc, &.{ dir, hive.constants.HivePaths.manifest_file });
    defer alloc.free(path);
    try fs.atomicWriteFile(alloc, path, json_bytes, false);
}

test "dep_graph: transitive version conflict fails fast and dependency_overrides resolves it" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root_dir = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer alloc.free(root_dir);
    const packages_dir = try std.fs.path.join(alloc, &.{ root_dir, "packages" });
    defer alloc.free(packages_dir);
    const project_dir = try std.fs.path.join(alloc, &.{ root_dir, "proj" });
    defer alloc.free(project_dir);

    const fs = hive.platform.fs.nativeFs();
    try fs.mkdirAll(alloc, project_dir);
    const target = "x86_64-linux-gnu";

    try writeTestManifest(alloc, fs, packages_dir, "plugin-a", "1.0.0", target, &.{
        .{ .name = "driver-x", .version = "1.0.0" },
    }, null);
    try writeTestManifest(alloc, fs, packages_dir, "plugin-b", "1.0.0", target, &.{
        .{ .name = "driver-x", .version = "1.1.0" },
    }, null);

    // Without overrides -> DependencyVersionConflict
    const hive_json_conflict =
        \\{
        \\  "dependencies": {
        \\    "plugin-a": { "version": "1.0.0" },
        \\    "plugin-b": { "version": "1.0.0" }
        \\  }
        \\}
    ;
    const hj_path = try std.fs.path.join(alloc, &.{ project_dir, "hive.json" });
    defer alloc.free(hj_path);
    try fs.atomicWriteFile(alloc, hj_path, hive_json_conflict, false);

    {
        var loaded = try hive.config.LoadedHiveConfig.loadFromDir(alloc, fs, project_dir);
        defer loaded.deinit();
        try std.testing.expectError(
            error.DependencyVersionConflict,
            hive.config.dep_graph.resolveTransitiveDependencies(alloc, fs, packages_dir, target, loaded.value()),
        );
    }

    // With dependency_overrides -> resolves cleanly to pinned version
    const hive_json_override =
        \\{
        \\  "dependencies": {
        \\    "plugin-a": { "version": "1.0.0" },
        \\    "plugin-b": { "version": "1.0.0" }
        \\  },
        \\  "dependency_overrides": {
        \\    "driver-x": { "version": "1.1.0" }
        \\  }
        \\}
    ;
    try fs.atomicWriteFile(alloc, hj_path, hive_json_override, false);

    {
        var loaded = try hive.config.LoadedHiveConfig.loadFromDir(alloc, fs, project_dir);
        defer loaded.deinit();
        const resolved = try hive.config.dep_graph.resolveTransitiveDependencies(alloc, fs, packages_dir, target, loaded.value());
        defer hive.config.dep_graph.freeResolvedDeps(alloc, resolved);

        try std.testing.expectEqual(@as(usize, 3), resolved.len);
        var found_driver = false;
        for (resolved) |d| {
            if (std.mem.eql(u8, d.name, "driver-x")) {
                found_driver = true;
                try std.testing.expectEqualStrings("1.1.0", d.version);
            }
        }
        try std.testing.expect(found_driver);
    }
}

test "dep_graph: validateBuildConfigCompatibility rejects mixed LTO and mismatched optimize" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const packages_dir = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/packages", .{tmp.sub_path});
    defer alloc.free(packages_dir);
    const fs = hive.platform.fs.nativeFs();
    const target = "x86_64-linux-gnu";

    const h_rel_lto = hive.config.hive_home.computeBuildConfigHash("0.15.1", "ReleaseFast", "baseline", true, false);
    const h_rel_nolto = hive.config.hive_home.computeBuildConfigHash("0.15.1", "ReleaseFast", "baseline", false, false);
    const h_dbg_nolto = hive.config.hive_home.computeBuildConfigHash("0.15.1", "Debug", "baseline", false, false);

    const fp_lto: hive.config.hive_home.BuildConfigFingerprint = .{
        .zig_version = "0.15.1",
        .optimize = "ReleaseFast",
        .cpu = "baseline",
        .lto = true,
        .bundle_compiler_rt = false,
        .config_hash = &h_rel_lto,
    };
    const fp_nolto: hive.config.hive_home.BuildConfigFingerprint = .{
        .zig_version = "0.15.1",
        .optimize = "ReleaseFast",
        .cpu = "baseline",
        .lto = false,
        .bundle_compiler_rt = false,
        .config_hash = &h_rel_nolto,
    };
    const fp_dbg: hive.config.hive_home.BuildConfigFingerprint = .{
        .zig_version = "0.15.1",
        .optimize = "Debug",
        .cpu = "baseline",
        .lto = false,
        .bundle_compiler_rt = false,
        .config_hash = &h_dbg_nolto,
    };

    try writeTestManifest(alloc, fs, packages_dir, "lib-lto", "1.0.0", target, &.{}, fp_lto);
    try writeTestManifest(alloc, fs, packages_dir, "lib-nolto", "1.0.0", target, &.{}, fp_nolto);

    var deps_mixed = [_]hive.config.dep_graph.ResolvedDep{
        .{ .name = try alloc.dupe(u8, "lib-lto"), .version = try alloc.dupe(u8, "1.0.0") },
        .{ .name = try alloc.dupe(u8, "lib-nolto"), .version = try alloc.dupe(u8, "1.0.0") },
    };
    defer {
        for (deps_mixed) |d| {
            alloc.free(d.name);
            alloc.free(d.version);
        }
    }

    try std.testing.expectError(
        error.MixedLtoConfiguration,
        hive.config.dep_graph.validateBuildConfigCompatibility(alloc, fs, packages_dir, target, &deps_mixed, fp_lto, false),
    );

    const deps_single = deps_mixed[1..2];
    try std.testing.expectError(
        error.IncompatibleBuildConfig,
        hive.config.dep_graph.validateBuildConfigCompatibility(alloc, fs, packages_dir, target, deps_single, fp_dbg, false),
    );

    const eff_lto = try hive.config.dep_graph.validateBuildConfigCompatibility(alloc, fs, packages_dir, target, deps_mixed[0..1], fp_lto, false);
    try std.testing.expect(eff_lto);
}

test "cli: build command parses --lto, --cpu, and --bundle-compiler-rt" {
    const alloc = std.testing.allocator;
    var app = try hive.cli.buildCliApp(alloc);
    defer app.deinit();

    var parsed = try app.parse(alloc, &.{
        "hive",
        "build",
        "--optimize",
        "ReleaseFast",
        "--cpu",
        "znver4",
        "--lto",
        "--bundle-compiler-rt",
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.hasFlag(hive.cli.BuildFlag.lto.flagName()));
    try std.testing.expect(parsed.hasFlag(hive.cli.BuildFlag.bundle_compiler_rt.flagName()));
    try std.testing.expectEqualStrings("znver4", parsed.getValue(hive.cli.BuildFlag.cpu.flagName()).?);
}

test "hive_home: parseCoordinate splits group:artifact and falls back to local" {
    const c1 = hive.config.hive_home.parseCoordinate("org.parabellum.drivers:sqlite", "local");
    try std.testing.expectEqualStrings("org.parabellum.drivers", c1.group);
    try std.testing.expectEqualStrings("sqlite", c1.artifact);

    const c2 = hive.config.hive_home.parseCoordinate("sqlite", "local");
    try std.testing.expectEqualStrings("local", c2.group);
    try std.testing.expectEqualStrings("sqlite", c2.artifact);
}
