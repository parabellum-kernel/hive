const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental flat-map): Resolves module metadata, invokes `zig build`
/// in parallel across modules, and emits `[]const BuildArtifactTask` for parallel verification.
pub const BuildCompileService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *BuildCompileService, alloc: std.mem.Allocator, task: types.BuildModuleRef) ![]const types.BuildArtifactTask {
        const fs = self.services.filesystem;
        const env = self.services.environment;
        const term = self.services.terminal;

        var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, task.repo_dir);
        defer loaded_cfg.deinit();
        const cfg = loaded_cfg.value();
        const meta = try types.resolveProjectNameAndVersion(alloc, fs, task.repo_dir, cfg.name, cfg.version);
        defer alloc.free(meta.version);

        const zig_version = try resolveZigVersion(alloc, self.services.runner);
        defer alloc.free(zig_version);

        try writeHiveDepsZig(alloc, fs, task, cfg, meta.name, meta.version);
        try writeBuildMetaJson(alloc, fs, task, zig_version);

        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(alloc);

        const opt_flag = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.TestSteps.optimize_prefix, task.optimize });
        defer alloc.free(opt_flag);
        try argv.appendSlice(alloc, &.{ constants.TestSteps.zig_bin, constants.TestSteps.zig_build_cmd, opt_flag });

        var target_flag: ?[]u8 = null;
        defer if (target_flag) |tf| alloc.free(tf);
        if (task.target.len > 0 and !std.mem.eql(u8, task.target, env.nativeTargetTriple())) {
            target_flag = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.TestSteps.target_prefix, task.target });
            try argv.append(alloc, target_flag.?);
        }

        var cpu_flag: ?[]u8 = null;
        defer if (cpu_flag) |cf| alloc.free(cf);
        if (task.cpu.len > 0 and !std.mem.eql(u8, task.cpu, constants.Defaults.baseline_cpu)) {
            cpu_flag = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.TestSteps.cpu_prefix, task.cpu });
            try argv.append(alloc, cpu_flag.?);
        }

        var extra_it = std.mem.splitScalar(u8, task.extra_args_packed, '\n');
        while (extra_it.next()) |arg| {
            if (arg.len > 0) try argv.append(alloc, arg);
        }

        var res = try self.services.runner.run(alloc, .{
            .argv = argv.items,
            .cwd = task.repo_dir,
        });
        defer res.deinit(alloc);

        if (res.stdout.len > 0) term.writeStdout(res.stdout);
        if (res.stderr.len > 0) term.writeStderr(res.stderr);

        if (res.exit_code != 0) {
            self.logger.err("zig build failed for '{s}' (exit {d})", .{ meta.name, res.exit_code });
            return error.ZigBuildFailed;
        }

        var validator_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer validator_buf.deinit(alloc);
        if (cfg.abi) |abi| {
            for (abi.validator) |part| {
                try validator_buf.appendSlice(alloc, part);
                try validator_buf.append(alloc, '\n');
            }
        }
        const validator_packed = try alloc.dupe(u8, validator_buf.items);

        var out: std.ArrayListUnmanaged(types.BuildArtifactTask) = .empty;

        const lib_dir = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.lib });
        defer alloc.free(lib_dir);
        if (fs.listDir(alloc, lib_dir)) |entries| {
            defer platform.PlatformFs.freeDirEntries(alloc, entries);
            for (entries) |ent| {
                if (ent.kind != .file) continue;
                const kind = types.classifyLibArtifact(ent.name) orelse continue;
                try out.append(alloc, .{
                    .order_index = task.order_index,
                    .repo_dir = try alloc.dupe(u8, task.repo_dir),
                    .module_name = meta.name,
                    .artifact_path = try std.fs.path.join(alloc, &.{ lib_dir, ent.name }),
                    .kind = @tagName(kind),
                    .verify_abi = task.verify_abi,
                    .validator_packed = validator_packed,
                });
            }
        } else |_| {}

        const bin_dir = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.zig_out, constants.ZigDirs.bin });
        defer alloc.free(bin_dir);
        if (fs.listDir(alloc, bin_dir)) |entries| {
            defer platform.PlatformFs.freeDirEntries(alloc, entries);
            for (entries) |ent| {
                if (ent.kind != .file) continue;
                const kind = types.classifyBinArtifact(ent.name);
                try out.append(alloc, .{
                    .order_index = task.order_index,
                    .repo_dir = try alloc.dupe(u8, task.repo_dir),
                    .module_name = meta.name,
                    .artifact_path = try std.fs.path.join(alloc, &.{ bin_dir, ent.name }),
                    .kind = @tagName(kind),
                    .verify_abi = task.verify_abi,
                    .validator_packed = validator_packed,
                });
            }
        } else |_| {}

        return try out.toOwnedSlice(alloc);
    }
};

fn resolveZigVersion(alloc: std.mem.Allocator, runner: platform.ProcessRunner) ![]u8 {
    if (runner.run(alloc, .{ .argv = &.{ constants.TestSteps.zig_bin, "version" } })) |res_val| {
        var res = res_val;
        defer res.deinit(alloc);
        if (res.exit_code == 0) {
            const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
            if (trimmed.len > 0) return try alloc.dupe(u8, trimmed);
        }
    } else |_| {}
    return try alloc.dupe(u8, @import("builtin").zig_version_string);
}

fn writeHiveDepsZig(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    task: types.BuildModuleRef,
    cfg: config.HiveJsonSchema,
    project_name: []const u8,
    project_version: []const u8,
) !void {
    const cache_dir = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.dot_zig_cache });
    defer alloc.free(cache_dir);
    try fs.mkdirAll(alloc, cache_dir);

    const deps_path = try std.fs.path.join(alloc, &.{ cache_dir, constants.HivePaths.hive_deps_zig });
    defer alloc.free(deps_path);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    const header = try std.fmt.allocPrint(alloc,
        \\// Auto-generated by `hive build`. Do not edit manually.
        \\pub const name: []const u8 = "{s}";
        \\pub const version: []const u8 = "{s}";
        \\pub const target: []const u8 = "{s}";
        \\pub const optimize: []const u8 = "{s}";
        \\pub const cpu: []const u8 = "{s}";
        \\pub const lto: bool = {s};
        \\pub const bundle_compiler_rt: bool = {s};
        \\pub const packages_dir: []const u8 = "{s}";
        \\
        \\pub const Dependency = struct {{
        \\    name: []const u8,
        \\    version: []const u8,
        \\    path: []const u8,
        \\}};
        \\
        \\pub const dependencies = [_]Dependency{{
        \\
    , .{
        project_name,
        project_version,
        task.target,
        task.optimize,
        task.cpu,
        if (task.lto) "true" else "false",
        if (task.bundle_compiler_rt) "true" else "false",
        task.packages_dir,
    });
    defer alloc.free(header);
    try buf.appendSlice(alloc, header);

    var it = cfg.dependencies.map.iterator();
    while (it.next()) |entry| {
        const dep_name = entry.key_ptr.*;
        const eff_ver = if (cfg.dependency_overrides.map.get(dep_name)) |ov| ov.version else entry.value_ptr.version;
        const dep_path = try config.hive_home.joinPackageTargetDir(alloc, task.packages_dir, dep_name, eff_ver, task.target);
        defer alloc.free(dep_path);
        const line = try std.fmt.allocPrint(
            alloc,
            "    .{{ .name = \"{s}\", .version = \"{s}\", .path = \"{s}\" }},\n",
            .{ dep_name, eff_ver, dep_path },
        );
        defer alloc.free(line);
        try buf.appendSlice(alloc, line);
    }

    try buf.appendSlice(alloc, "};\n");
    try fs.atomicWriteFile(alloc, deps_path, buf.items, false);
}

fn writeBuildMetaJson(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    task: types.BuildModuleRef,
    zig_version: []const u8,
) !void {
    const cache_dir = try std.fs.path.join(alloc, &.{ task.repo_dir, constants.ZigDirs.dot_zig_cache });
    defer alloc.free(cache_dir);
    try fs.mkdirAll(alloc, cache_dir);

    const meta_path = try std.fs.path.join(alloc, &.{ cache_dir, constants.HivePaths.hive_build_meta });
    defer alloc.free(meta_path);

    const hash_hex = config.hive_home.computeBuildConfigHash(
        zig_version,
        task.optimize,
        task.cpu,
        task.lto,
        task.bundle_compiler_rt,
    );
    const fp = config.hive_home.BuildConfigFingerprint{
        .zig_version = zig_version,
        .optimize = task.optimize,
        .cpu = task.cpu,
        .lto = task.lto,
        .bundle_compiler_rt = task.bundle_compiler_rt,
        .config_hash = &hash_hex,
    };
    const json_bytes = try std.json.Stringify.valueAlloc(alloc, fp, .{ .whitespace = .indent_2 });
    defer alloc.free(json_bytes);
    try fs.atomicWriteFile(alloc, meta_path, json_bytes, false);
}
