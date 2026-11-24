const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const config = @import("../../config/mod.zig");
const build_types = @import("../build/types.zig");
const types = @import("types.zig");

const Logger = sdk.task.Logger;

/// Step 4 (parallel elemental filter-map): Classifies each discovered file into an
/// `InstallArtifactTask` (returns `null` to filter out non-artifact files).
pub const InstallClassifyArtifactService = struct {
    logger: Logger,
    services: platform.PlatformServices,

    pub fn execute(_: *InstallClassifyArtifactService, alloc: std.mem.Allocator, entry: types.InstallRawEntry) !?types.InstallArtifactTask {
        const bucket = std.meta.stringToEnum(types.InstallBucket, entry.bucket) orelse return null;
        const classified = classifyEntry(bucket, entry.file_name) orelse return null;
        const dest_base = if (classified.target_agnostic) entry.dest_ver_dir else entry.dest_target_dir;

        return .{
            .order_index = entry.order_index,
            .repo_dir = try alloc.dupe(u8, entry.repo_dir),
            .module_name = try alloc.dupe(u8, entry.module_name),
            .effective_version = try alloc.dupe(u8, entry.effective_version),
            .target = try alloc.dupe(u8, entry.target),
            .src_path = try std.fs.path.join(alloc, &.{ entry.src_dir, entry.file_name }),
            .dest_dir = try alloc.dupe(u8, entry.dest_target_dir),
            .dest_path = try std.fs.path.join(alloc, &.{ dest_base, entry.file_name }),
            .file_name = try alloc.dupe(u8, entry.file_name),
            .kind = classified.kind,
            .executable = classified.executable,
        };
    }
};

const ClassifiedArtifact = struct {
    kind: []const u8,
    executable: bool,
    target_agnostic: bool,
};

fn classifyEntry(bucket: types.InstallBucket, name: []const u8) ?ClassifiedArtifact {
    return switch (bucket) {
        .lib => {
            const k = build_types.classifyLibArtifact(name) orelse return null;
            return .{ .kind = @tagName(k), .executable = (k == .dynamic), .target_agnostic = false };
        },
        .bin => {
            const k = build_types.classifyBinArtifact(name);
            return .{ .kind = @tagName(k), .executable = true, .target_agnostic = false };
        },
        .dist => {
            if (std.mem.endsWith(u8, name, "-sources.tar.gz")) {
                return .{ .kind = @tagName(config.hive_home.ArtifactKind.sources), .executable = false, .target_agnostic = true };
            }
            if (std.mem.endsWith(u8, name, "-docs.tar.gz")) {
                return .{ .kind = @tagName(config.hive_home.ArtifactKind.docs), .executable = false, .target_agnostic = true };
            }
            return null;
        },
    };
}
