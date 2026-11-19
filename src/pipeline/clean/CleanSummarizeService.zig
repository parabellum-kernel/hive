const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (deterministic ordered reduce): Sorts results by `(order_index, path)`, prints
/// per-directory lines in deterministic order, and emits the summary.
pub const CleanSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *CleanSummarizeService, alloc: std.mem.Allocator, inputs: types.CleanSummarizeInputs) !types.CleanOutputs {
        const term = self.services.terminal;

        const sorted = try alloc.dupe(types.CleanTargetResult, inputs.results.items);
        defer alloc.free(sorted);
        std.mem.sort(types.CleanTargetResult, sorted, {}, types.lessThanCleanResult);

        var total_bytes: u64 = 0;
        var dry_run = false;
        var size_buf: [64]u8 = undefined;
        var line_buf: [1024]u8 = undefined;

        for (sorted) |item| {
            const sz: u64 = if (item.bytes > 0) @intCast(item.bytes) else 0;
            total_bytes += sz;
            dry_run = item.dry_run;
            const human = types.formatBytes(&size_buf, sz);
            const tag = if (item.dry_run) "DRY-RUN" else "DELETED";
            const line = std.fmt.bufPrint(&line_buf, "[{s}] {s:>10} -> {s}\n", .{ tag, human, item.path }) catch continue;
            term.writeStdout(line);
        }

        const total_human = types.formatBytes(&size_buf, total_bytes);
        const verb = if (dry_run) "reclaimable" else "freed";
        const summary = std.fmt.bufPrint(
            &line_buf,
            "hive clean: {d} director{s} processed, {s} {s}.\n",
            .{ sorted.len, if (sorted.len == 1) "y" else "ies", total_human, verb },
        ) catch "";
        term.writeStdout(summary);

        return .{
            .directories_cleaned = @intCast(sorted.len),
            .bytes_freed = @intCast(total_bytes),
            .dry_run = dry_run,
        };
    }
};
