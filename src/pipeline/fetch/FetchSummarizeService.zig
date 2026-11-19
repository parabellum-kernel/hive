const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (reduce): Summarizes resolved dependencies (cached vs. downloaded) and total bytes.
pub const FetchSummarizeService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *FetchSummarizeService, _: std.mem.Allocator, inputs: types.FetchSummarizeInputs) !types.FetchOutputs {
        const term = self.services.terminal;

        var cached_count: i64 = 0;
        var downloaded_count: i64 = 0;
        var total_bytes: i64 = 0;

        for (inputs.results.items) |item| {
            if (std.mem.eql(u8, item.status, @tagName(types.FetchStatus.cached))) {
                cached_count += 1;
            } else {
                downloaded_count += 1;
            }
            total_bytes += item.bytes;
        }

        var line_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &line_buf,
            "hive fetch: {d} resolved ({d} cached, {d} downloaded, {d} bytes).\n",
            .{ inputs.results.items.len, cached_count, downloaded_count, total_bytes },
        ) catch "";
        term.writeStdout(msg);

        return .{
            .total_resolved = @intCast(inputs.results.items.len),
            .cached_count = cached_count,
            .downloaded_count = downloaded_count,
            .bytes_fetched = total_bytes,
        };
    }
};
