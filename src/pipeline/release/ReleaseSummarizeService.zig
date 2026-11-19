const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts release results and emits summary.
pub const ReleaseSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *ReleaseSummarizeService, alloc: std.mem.Allocator, inputs: types.ReleaseSummarizeInputs) !types.ReleaseOutputs {
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.ReleaseResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.ReleaseResult, sorted, {}, types.lessThanReleaseResult);

        var dry_run = false;
        var line_buf: [512]u8 = undefined;
        for (sorted) |item| {
            dry_run = item.dry_run;
            const prefix = if (item.dry_run) "[DRY-RUN] " else "";
            const line = std.fmt.bufPrint(
                &line_buf,
                "{s}hive release: {s}@{s} (tag {s})\n",
                .{ prefix, item.name, item.target_version, item.tag_name },
            ) catch continue;
            term.writeStdout(line);
        }

        return .{
            .releases_completed = @intCast(sorted.len),
            .dry_run = dry_run,
        };
    }
};
