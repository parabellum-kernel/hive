const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental map): Computes SHA-256 and atomically copies each artifact
/// into `~/.hive/packages/` with safe permissions (`0755` exec/shared, `0644` static/archives).
pub const InstallCopyArtifactService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InstallCopyArtifactService, alloc: std.mem.Allocator, task: types.InstallArtifactTask) !types.InstallArtifactResult {
        const fs = self.services.filesystem;

        const data = try fs.readFileAlloc(alloc, task.src_path, 256 * 1024 * 1024);
        defer alloc.free(data);

        const sha = build_types.computeSha256Hex(data);
        try fs.atomicWriteFile(alloc, task.dest_path, data, task.executable);

        return .{
            .order_index = task.order_index,
            .repo_dir = try alloc.dupe(u8, task.repo_dir),
            .module_name = try alloc.dupe(u8, task.module_name),
            .effective_version = try alloc.dupe(u8, task.effective_version),
            .target = try alloc.dupe(u8, task.target),
            .dest_dir = try alloc.dupe(u8, task.dest_dir),
            .file_name = try alloc.dupe(u8, task.file_name),
            .kind = try alloc.dupe(u8, task.kind),
            .sha256 = try alloc.dupe(u8, &sha),
            .size_bytes = @intCast(data.len),
        };
    }
};
