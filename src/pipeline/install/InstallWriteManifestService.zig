const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts installed artifacts by `(order_index, file_name)`,
/// writes `manifest.json` per `(module, target)`, and prints installed coordinates.
pub const InstallWriteManifestService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InstallWriteManifestService, alloc: std.mem.Allocator, inputs: types.InstallSummarizeInputs) !types.InstallOutputs {
        const fs = self.services.filesystem;
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.InstallArtifactResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.InstallArtifactResult, sorted, {}, types.lessThanInstallResult);

        var total_bytes: i64 = 0;
        var i: usize = 0;
        while (i < sorted.len) {
            const first = sorted[i];
            var end = i + 1;
            while (end < sorted.len and sorted[end].order_index == first.order_index) : (end += 1) {}

            const group = sorted[i..end];
            var arts = try alloc.alloc(config.hive_home.ManifestArtifact, group.len);
            defer alloc.free(arts);

            for (group, 0..) |item, idx| {
                total_bytes += item.size_bytes;
                arts[idx] = .{
                    .file = item.file_name,
                    .kind = std.meta.stringToEnum(config.hive_home.ArtifactKind, item.kind) orelse .static,
                    .sha256 = item.sha256,
                    .size_bytes = @intCast(item.size_bytes),
                };
            }

            var build_meta = config.hive_home.LoadedBuildMeta.loadFromRepo(alloc, fs, first.repo_dir);
            defer build_meta.deinit();
            const deps = try config.hive_home.collectManifestDependencies(alloc, fs, first.repo_dir);
            defer config.hive_home.freeManifestDependencies(alloc, deps);

            const installed_at = try config.hive_home.formatUtcIso8601Now(alloc);
            defer alloc.free(installed_at);

            const manifest = config.PackageManifest{
                .name = first.module_name,
                .version = first.effective_version,
                .target = first.target,
                .installed_at = installed_at,
                .build_config = build_meta.value(),
                .dependencies = deps,
                .artifacts = arts,
            };

            const json_bytes = try std.json.Stringify.valueAlloc(alloc, manifest, .{ .whitespace = .indent_2 });
            defer alloc.free(json_bytes);

            const manifest_path = try std.fs.path.join(alloc, &.{ first.dest_dir, constants.HivePaths.manifest_file });
            defer alloc.free(manifest_path);
            try fs.atomicWriteFile(alloc, manifest_path, json_bytes, false);

            var line_buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &line_buf,
                "hive install: {s}@{s} ({s}) -> {s}/ ({d} artifact{s})\n",
                .{
                    first.module_name,
                    first.effective_version,
                    first.target,
                    first.dest_dir,
                    group.len,
                    if (group.len == 1) "" else "s",
                },
            ) catch "";
            term.writeStdout(msg);

            i = end;
        }

        return .{
            .artifacts_installed = @intCast(sorted.len),
            .bytes_installed = total_bytes,
        };
    }
};
