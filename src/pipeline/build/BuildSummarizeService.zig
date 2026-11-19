const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts verified artifacts by `(order_index, artifact_path)`
/// and emits the build summary.
pub const BuildSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *BuildSummarizeService, alloc: std.mem.Allocator, inputs: types.BuildSummarizeInputs) !types.BuildOutputs {
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.BuildArtifactResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.BuildArtifactResult, sorted, {}, types.lessThanArtifactResult);

        var total_bytes: i64 = 0;
        for (sorted) |item| {
            total_bytes += item.bytes;
        }

        var line_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &line_buf,
            "hive build: {d} artifact{s} verified ({d} bytes).\n",
            .{
                sorted.len,
                if (sorted.len == 1) "" else "s",
                total_bytes,
            },
        ) catch "";
        term.writeStdout(msg);

        return .{
            .total_artifacts = @intCast(sorted.len),
            .total_bytes = total_bytes,
        };
    }
};
