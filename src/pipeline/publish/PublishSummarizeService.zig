const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts published assets and emits summary.
pub const PublishSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *PublishSummarizeService, alloc: std.mem.Allocator, inputs: types.PublishSummarizeInputs) !types.PublishOutputs {
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.PublishAssetResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.PublishAssetResult, sorted, {}, types.lessThanPublishResult);

        var total_bytes: i64 = 0;
        var dry_run = false;
        var line_buf: [512]u8 = undefined;

        for (sorted) |item| {
            total_bytes += item.bytes;
            dry_run = item.dry_run;
            const prefix = if (item.dry_run) "[DRY-RUN] " else "";
            const line = std.fmt.bufPrint(
                &line_buf,
                "{s}hive publish: {s}@{s} -> {s} ({s}, {d} bytes)\n",
                .{ prefix, item.module_name, item.effective_version, item.repo_name, item.file_name, item.bytes },
            ) catch continue;
            term.writeStdout(line);
        }

        return .{
            .assets_published = @intCast(sorted.len),
            .bytes_uploaded = total_bytes,
            .dry_run = dry_run,
        };
    }
};
