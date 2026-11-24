const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (parallel elemental map): Runs declarative `packaging.packagers` sequentially
/// per deliverable (`transform` vs `sidecar` semantics) and computes final SHA-256.
pub const PackagePostProcessService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PackagePostProcessService, alloc: std.mem.Allocator, item: types.PackageAssembled) !types.PackageResult {
        const fs = self.services.filesystem;

        var active_path = try alloc.dupe(u8, item.output_path);
        errdefer alloc.free(active_path);

        var sidecars_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer sidecars_buf.deinit(alloc);

        if (item.packagers_packed.len > 0) {
            var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, item.repo_dir);
            defer loaded_cfg.deinit();
            if (loaded_cfg.value().packaging) |pkg| {
                var p_it = std.mem.splitScalar(u8, item.packagers_packed, '\n');
                var step_idx: usize = 0;
                while (p_it.next()) |pname| {
                    if (pname.len == 0) continue;
                    const pspec = pkg.packagers.map.get(pname) orelse {
                        self.logger.err("Unknown packager '{s}' in hive.json", .{pname});
                        return error.UnknownPackager;
                    };

                    const next_path = try runPackagerStep(
                        alloc,
                        fs,
                        self.services.runner,
                        pspec,
                        active_path,
                        step_idx,
                        &sidecars_buf,
                    );
                    if (next_path) |np| {
                        alloc.free(active_path);
                        active_path = np;
                    }
                    step_idx += 1;
                }
            }
        }

        const data = try fs.readFileAlloc(alloc, active_path, 256 * 1024 * 1024);
        defer alloc.free(data);
        const sha = build_types.computeSha256Hex(data);

        return .{
            .order_index = item.order_index,
            .repo_dir = try alloc.dupe(u8, item.repo_dir),
            .module_name = try alloc.dupe(u8, item.module_name),
            .version = try alloc.dupe(u8, item.version),
            .target = try alloc.dupe(u8, item.target),
            .format = try alloc.dupe(u8, item.format),
            .dist_dir = try alloc.dupe(u8, item.dist_dir),
            .output_path = active_path,
            .sha256 = try alloc.dupe(u8, &sha),
            .size_bytes = @intCast(data.len),
            .sidecars_packed = try alloc.dupe(u8, sidecars_buf.items),
        };
    }
};

pub fn substitutePlaceholders(
    alloc: std.mem.Allocator,
    template: []const u8,
    input_path: []const u8,
    output_path: []const u8,
) ![]u8 {
    const with_in = try std.mem.replaceOwned(u8, alloc, template, "{input}", input_path);
    defer alloc.free(with_in);
    return try std.mem.replaceOwned(u8, alloc, with_in, "{output}", output_path);
}

fn commandUsesPlaceholder(cmd: []const []const u8, needle: []const u8) bool {
    for (cmd) |part| {
        if (std.mem.indexOf(u8, part, needle) != null) return true;
    }
    return false;
}

fn runPackagerStep(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    runner: platform.ProcessRunner,
    pspec: config.hive_json.PackagerSpec,
    active_path: []const u8,
    step_idx: usize,
    sidecars_buf: *std.ArrayListUnmanaged(u8),
) !?[]u8 {
    if (pspec.command.len == 0) return null;

    const uses_output = commandUsesPlaceholder(pspec.command, "{output}");
    const staged_output: ?[]u8 = if (pspec.mode == .transform and uses_output)
        try std.fmt.allocPrint(alloc, "{s}.step{d}", .{ active_path, step_idx })
    else
        null;
    errdefer if (staged_output) |s| alloc.free(s);

    const out_arg = staged_output orelse active_path;

    var argv = try alloc.alloc([]const u8, pspec.command.len);
    defer {
        for (argv) |a| alloc.free(a);
        alloc.free(argv);
    }
    for (pspec.command, 0..) |part, i| {
        argv[i] = try substitutePlaceholders(alloc, part, active_path, out_arg);
    }

    var res = try runner.run(alloc, .{ .argv = argv });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.PackagerFailed;

    if (pspec.mode == .sidecar) {
        for (pspec.outputs) |out_tmpl| {
            const sidecar_path = try substitutePlaceholders(alloc, out_tmpl, active_path, out_arg);
            defer alloc.free(sidecar_path);
            if (!fs.exists(alloc, sidecar_path)) return error.MissingSidecarOutput;
            const sdata = try fs.readFileAlloc(alloc, sidecar_path, 64 * 1024 * 1024);
            defer alloc.free(sdata);
            const ssha = build_types.computeSha256Hex(sdata);
            const line = try std.fmt.allocPrint(alloc, "{s}\t{s}\t{d}\n", .{
                std.fs.path.basename(sidecar_path),
                ssha,
                sdata.len,
            });
            defer alloc.free(line);
            try sidecars_buf.appendSlice(alloc, line);
        }
        if (staged_output) |s| alloc.free(s);
        return null;
    }

    return staged_output;
}
