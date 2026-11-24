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
            var sums_buf: std.ArrayListUnmanaged(u8) = .empty;
            defer sums_buf.deinit(alloc);

            const primary_sum = try std.fmt.allocPrint(alloc, "{s}  {s}\n", .{ item.sha256, fname });
            defer alloc.free(primary_sum);
            try sums_buf.appendSlice(alloc, primary_sum);

            var arts_list: std.ArrayListUnmanaged(config.hive_home.ManifestArtifact) = .empty;
            defer arts_list.deinit(alloc);

            const primary_kind: config.hive_home.ArtifactKind = if (std.mem.eql(u8, item.format, "so")) .dynamic else .bin;
            try arts_list.append(alloc, .{
                .file = fname,
                .kind = primary_kind,
                .sha256 = item.sha256,
                .size_bytes = @intCast(item.size_bytes),
            });

            var sc_it = std.mem.splitScalar(u8, item.sidecars_packed, '\n');
            while (sc_it.next()) |line| {
                if (line.len == 0) continue;
                var fields = std.mem.splitScalar(u8, line, '\t');
                const sc_name = fields.next() orelse continue;
                const sc_sha = fields.next() orelse continue;
                const sc_size_str = fields.next() orelse continue;
                const sc_size = std.fmt.parseInt(u64, sc_size_str, 10) catch continue;

                const sc_sum = try std.fmt.allocPrint(alloc, "{s}  {s}\n", .{ sc_sha, sc_name });
                defer alloc.free(sc_sum);
                try sums_buf.appendSlice(alloc, sc_sum);

                try arts_list.append(alloc, .{
                    .file = sc_name,
                    .kind = .sidecar,
                    .sha256 = sc_sha,
                    .size_bytes = sc_size,
                });
            }

            const sums_path = try std.fs.path.join(alloc, &.{ item.dist_dir, constants.HivePaths.checksums_file });
            defer alloc.free(sums_path);
            try fs.atomicWriteFile(alloc, sums_path, sums_buf.items, false);

            var build_meta = config.hive_home.LoadedBuildMeta.loadFromRepo(alloc, fs, item.repo_dir);
            defer build_meta.deinit();
            const deps = try config.hive_home.collectManifestDependencies(alloc, fs, item.repo_dir);
            defer config.hive_home.freeManifestDependencies(alloc, deps);

            const installed_at = try config.hive_home.formatUtcIso8601Now(alloc);
            defer alloc.free(installed_at);

            const manifest = config.PackageManifest{
                .name = item.module_name,
                .version = item.version,
                .target = item.target,
                .installed_at = installed_at,
                .build_config = build_meta.value(),
                .dependencies = deps,
                .artifacts = arts_list.items,
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
