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
