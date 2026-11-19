const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 5 (deterministic ordered reduce): Sorts packaged deliverables, writes `SHA256SUMS.txt`
/// and `manifest.json` in `zig-out/dist/`, and prints summary.
pub const PackageWriteManifestService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PackageWriteManifestService, alloc: std.mem.Allocator, inputs: types.PackageSummarizeInputs) !types.PackageOutputs {
        const fs = self.services.filesystem;
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.PackageResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.PackageResult, sorted, {}, types.lessThanPackageResult);

        var total_bytes: i64 = 0;
        var line_buf: [512]u8 = undefined;

        for (sorted) |item| {
            total_bytes += item.size_bytes;

            const fname = std.fs.path.basename(item.output_path);
            const sums_line = try std.fmt.allocPrint(alloc, "{s}  {s}\n", .{ item.sha256, fname });
            defer alloc.free(sums_line);
            const sums_path = try std.fs.path.join(alloc, &.{ item.dist_dir, constants.HivePaths.checksums_file });
            defer alloc.free(sums_path);
            try fs.atomicWriteFile(alloc, sums_path, sums_line, false);

            const art = [_]config.hive_home.ManifestArtifact{.{
                .file = fname,
                .kind = .bin,
                .sha256 = item.sha256,
                .size_bytes = @intCast(item.size_bytes),
            }};
            const manifest = config.PackageManifest{
                .name = item.module_name,
                .version = item.version,
                .target = item.target,
                .installed_at = "2026-11-19T00:00:00Z",
                .artifacts = &art,
            };
            const json_bytes = try std.json.Stringify.valueAlloc(alloc, manifest, .{ .whitespace = .indent_2 });
            defer alloc.free(json_bytes);
            const manifest_path = try std.fs.path.join(alloc, &.{ item.dist_dir, constants.HivePaths.manifest_file });
            defer alloc.free(manifest_path);
            try fs.atomicWriteFile(alloc, manifest_path, json_bytes, false);

            const msg = std.fmt.bufPrint(
                &line_buf,
                "hive package: {s}@{s} -> {s} ({d} bytes)\n",
                .{ item.module_name, item.version, item.output_path, item.size_bytes },
            ) catch continue;
            term.writeStdout(msg);
        }

        return .{
            .packages_created = @intCast(sorted.len),
            .total_bytes = total_bytes,
        };
    }
};
