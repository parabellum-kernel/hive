const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 3 (parallel elemental flat-map): Lists files in a single `zig-out/{lib,bin,dist}`
/// directory and emits `[]const InstallRawEntry` for classification.
pub const InstallScanDirService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(self: *InstallScanDirService, alloc: std.mem.Allocator, scan: types.InstallDirScanTask) ![]const types.InstallRawEntry {
        const fs = self.services.filesystem;

        const entries = fs.listDir(alloc, scan.src_dir) catch return &.{};
        defer platform.PlatformFs.freeDirEntries(alloc, entries);

        var out: std.ArrayListUnmanaged(types.InstallRawEntry) = .empty;
        for (entries) |ent| {
            if (ent.kind != .file) continue;
            try out.append(alloc, .{
                .order_index = scan.order_index,
                .module_name = try alloc.dupe(u8, scan.module_name),
                .effective_version = try alloc.dupe(u8, scan.effective_version),
                .target = try alloc.dupe(u8, scan.target),
                .src_dir = try alloc.dupe(u8, scan.src_dir),
                .dest_target_dir = try alloc.dupe(u8, scan.dest_target_dir),
                .dest_ver_dir = try alloc.dupe(u8, scan.dest_ver_dir),
                .bucket = try alloc.dupe(u8, scan.bucket),
                .file_name = try alloc.dupe(u8, ent.name),
            });
        }
        return try out.toOwnedSlice(alloc);
    }
};
