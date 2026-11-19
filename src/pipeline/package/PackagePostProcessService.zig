const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (parallel elemental map): Runs declarative `packaging.packagers` sequentially
/// per deliverable (`{input}`, `{output}` placeholders) and computes final SHA-256.
pub const PackagePostProcessService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PackagePostProcessService, alloc: std.mem.Allocator, item: types.PackageAssembled) !types.PackageResult {
        const fs = self.services.filesystem;

        if (item.packagers_packed.len > 0) {
            var loaded_cfg = try config.LoadedHiveConfig.loadFromDir(alloc, fs, item.repo_dir);
            defer loaded_cfg.deinit();
            if (loaded_cfg.value().packaging) |pkg| {
                var p_it = std.mem.splitScalar(u8, item.packagers_packed, '\n');
                while (p_it.next()) |pname| {
                    if (pname.len == 0) continue;
                    const pspec = pkg.packagers.map.get(pname) orelse {
                        self.logger.err("Unknown packager '{s}' in hive.json", .{pname});
                        return error.UnknownPackager;
                    };
                    try runPackagerCommand(alloc, self.services.runner, pspec.command, item.output_path);
                }
            }
        }

        const data = try fs.readFileAlloc(alloc, item.output_path, 256 * 1024 * 1024);
        defer alloc.free(data);
        const sha = build_types.computeSha256Hex(data);

        return .{
            .order_index = item.order_index,
            .module_name = try alloc.dupe(u8, item.module_name),
            .version = try alloc.dupe(u8, item.version),
            .target = try alloc.dupe(u8, item.target),
            .dist_dir = try alloc.dupe(u8, item.dist_dir),
            .output_path = try alloc.dupe(u8, item.output_path),
            .sha256 = try alloc.dupe(u8, &sha),
            .size_bytes = @intCast(data.len),
        };
    }
};

fn runPackagerCommand(
    alloc: std.mem.Allocator,
    runner: platform.ProcessRunner,
    template_cmd: []const []const u8,
    artifact_path: []const u8,
) !void {
    if (template_cmd.len == 0) return;
    var argv = try alloc.alloc([]const u8, template_cmd.len);
    defer alloc.free(argv);
    for (template_cmd, 0..) |part, i| {
        if (std.mem.eql(u8, part, "{input}") or std.mem.eql(u8, part, "{output}")) {
            argv[i] = artifact_path;
        } else {
            argv[i] = part;
        }
    }
    var res = try runner.run(alloc, .{ .argv = argv });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.PackagerFailed;
}
