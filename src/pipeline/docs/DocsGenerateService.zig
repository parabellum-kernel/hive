const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const build_types = @import("../build/types.zig");
const test_types = @import("../test/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 2 (parallel elemental map): Generates static HTML API documentation via Zig's
/// native `autodoc` (`zig build <step>` or `zig build-lib -femit-docs`).
pub const DocsGenerateService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *DocsGenerateService, alloc: std.mem.Allocator, mod_ref: types.DocsModuleRef) !types.DocsModuleResult {
        const fs = self.services.filesystem;
        const term = self.services.terminal;

        var mod_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, mod_ref.repo_dir);
        defer mod_cfg.deinit();
        const mc = mod_cfg.value();
        const meta = try build_types.resolveProjectNameAndVersion(alloc, fs, mod_ref.repo_dir, mc.name, mc.version);
        defer alloc.free(meta.version);

        const step_name = if (mc.docs) |d| d.step else mod_ref.step;
        const abs_out = if (std.fs.path.isAbsolute(mod_ref.out_dir))
            try alloc.dupe(u8, mod_ref.out_dir)
        else
            try std.fs.path.join(alloc, &.{ mod_ref.repo_dir, mod_ref.out_dir });

        if (test_types.hasZigBuildStep(alloc, self.services.runner, mod_ref.repo_dir, step_name)) {
            const opt_flag = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.TestSteps.optimize_prefix, mod_ref.optimize });
            defer alloc.free(opt_flag);

            var res = try self.services.runner.run(alloc, .{
                .argv = &.{ constants.TestSteps.zig_bin, constants.TestSteps.zig_build_cmd, step_name, opt_flag },
                .cwd = mod_ref.repo_dir,
            });
            defer res.deinit(alloc);
            if (res.stdout.len > 0) term.writeStdout(res.stdout);
            if (res.stderr.len > 0) term.writeStderr(res.stderr);
            if (res.exit_code != 0) return error.DocsGenerationFailed;
        } else {
            const root_src = resolveRootSourceFile(alloc, fs, mod_ref.repo_dir, if (mc.docs) |d| d.root_source_file else null) orelse {
                self.logger.err("No root source file found for autodoc in '{s}'", .{mod_ref.repo_dir});
                return error.MissingRootSourceFile;
            };
            defer alloc.free(root_src);

            try fs.mkdirAll(alloc, abs_out);
            const emit_flag = try std.fmt.allocPrint(alloc, "-femit-docs={s}", .{abs_out});
            defer alloc.free(emit_flag);
            const opt_arg = try std.fmt.allocPrint(alloc, "-O{s}", .{mod_ref.optimize});
            defer alloc.free(opt_arg);

            var res = try self.services.runner.run(alloc, .{
                .argv = &.{ constants.TestSteps.zig_bin, "build-lib", emit_flag, "-fno-emit-bin", opt_arg, root_src },
                .cwd = mod_ref.repo_dir,
            });
            defer res.deinit(alloc);
            if (res.stdout.len > 0) term.writeStdout(res.stdout);
            if (res.stderr.len > 0) term.writeStderr(res.stderr);
            if (res.exit_code != 0) return error.DocsGenerationFailed;
        }

        return .{
            .order_index = mod_ref.order_index,
            .module_name = try alloc.dupe(u8, meta.name),
            .repo_dir = try alloc.dupe(u8, mod_ref.repo_dir),
            .out_dir = abs_out,
            .tarball_path = "",
            .package_bundle = mod_ref.package_bundle,
        };
    }
};

fn resolveRootSourceFile(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    repo_dir: []const u8,
    configured: ?[]const u8,
) ?[]u8 {
    if (configured) |c| {
        const p = std.fs.path.join(alloc, &.{ repo_dir, c }) catch return null;
        if (fs.exists(alloc, p)) return p;
        alloc.free(p);
    }
    const candidates = [_][]const u8{ "src/root.zig", "src/main.zig" };
    for (candidates) |cand| {
        const p = std.fs.path.join(alloc, &.{ repo_dir, cand }) catch continue;
        if (fs.exists(alloc, p)) return p;
        alloc.free(p);
    }
    return null;
}
