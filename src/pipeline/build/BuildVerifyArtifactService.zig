const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Verifies binary format & ABI contract and computes
/// SHA-256 digest for each individual artifact in parallel.
pub const BuildVerifyArtifactService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *BuildVerifyArtifactService, alloc: std.mem.Allocator, task: types.BuildArtifactTask) !types.BuildArtifactResult {
        const fs = self.services.filesystem;
        const data = try fs.readFileAlloc(alloc, task.artifact_path, 256 * 1024 * 1024);
        defer alloc.free(data);

        const is_dynamic = std.mem.eql(u8, task.kind, @tagName(types.ArtifactKind.dynamic));
        if (task.verify_abi and is_dynamic) {
            if (!types.hasValidBinaryMagic(data)) {
                self.logger.err("Invalid binary header in dynamic artifact: {s}", .{task.artifact_path});
                return error.InvalidBinaryArtifact;
            }
            if (task.validator_packed.len > 0) {
                try runExternalValidator(alloc, self.services.runner, task.validator_packed, task.artifact_path);
            }
        }

        const sha = types.computeSha256Hex(data);

        return .{
            .order_index = task.order_index,
            .module_name = try alloc.dupe(u8, task.module_name),
            .artifact_path = try alloc.dupe(u8, task.artifact_path),
            .kind = try alloc.dupe(u8, task.kind),
            .sha256 = try alloc.dupe(u8, &sha),
            .bytes = @intCast(data.len),
        };
    }
};

fn runExternalValidator(
    alloc: std.mem.Allocator,
    runner: platform.ProcessRunner,
    validator_packed: []const u8,
    artifact_path: []const u8,
) !void {
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(alloc);

    var it = std.mem.splitScalar(u8, validator_packed, '\n');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (std.mem.eql(u8, part, "{artifact}")) {
            try argv.append(alloc, artifact_path);
        } else {
            try argv.append(alloc, part);
        }
    }
    if (argv.items.len == 0) return;

    var res = try runner.run(alloc, .{ .argv = argv.items });
    defer res.deinit(alloc);
    if (res.exit_code != 0) return error.AbiValidationFailed;
}
