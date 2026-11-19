const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../constants.zig");

pub const ArtifactKind = enum {
    dynamic,
    static,
    bin,
    sources,
    docs,
};

pub const ManifestArtifact = struct {
    file: []const u8,
    kind: ArtifactKind,
    sha256: []const u8,
    size_bytes: u64,
    zon_hash: ?[]const u8 = null,
};

pub const PackageManifest = struct {
    name: []const u8,
    version: []const u8,
    target: []const u8,
    installed_at: []const u8,
    artifacts: []const ManifestArtifact = &.{},
};

pub const TemplateVarSpec = struct {
    required: bool = false,
    default: ?[]const u8 = null,
};

pub const TemplateJson = struct {
    name: []const u8,
    version: []const u8 = "0.1.0",
    description: []const u8 = "",
    variables: std.json.ArrayHashMap(TemplateVarSpec) = .{},
};

/// Resolves `~/.hive/` (or `HIVE_HOME` / CLI overrides) and builds uniform flat artifact coordinates.
pub const HiveHome = struct {
    base_dir: []u8,
    packages_dir: []u8,
    templates_dir: []u8,

    pub const Overrides = struct {
        artifact_repository_dir: ?[]const u8 = null,
        templates_dir: ?[]const u8 = null,
    };

    pub fn resolve(alloc: std.mem.Allocator, env: platform.PlatformEnv, overrides: Overrides) !HiveHome {
        const base_dir = if (env.getEnv(alloc, constants.EnvVar.HIVE_HOME.key())) |hh|
            hh
        else if (env.homeDir(alloc)) |home| blk: {
            defer alloc.free(home);
            break :blk try std.fs.path.join(alloc, &.{ home, constants.HivePaths.hive_dir });
        } else try alloc.dupe(u8, constants.HivePaths.hive_dir);
        errdefer alloc.free(base_dir);

        const packages_dir = if (overrides.artifact_repository_dir) |p|
            try alloc.dupe(u8, p)
        else
            try std.fs.path.join(alloc, &.{ base_dir, constants.HivePaths.packages_dir });
        errdefer alloc.free(packages_dir);

        const templates_dir = if (overrides.templates_dir) |t|
            try alloc.dupe(u8, t)
        else
            try std.fs.path.join(alloc, &.{ base_dir, constants.HivePaths.templates_dir });

        return .{
            .base_dir = base_dir,
            .packages_dir = packages_dir,
            .templates_dir = templates_dir,
        };
    }

    pub fn deinit(self: *HiveHome, alloc: std.mem.Allocator) void {
        alloc.free(self.base_dir);
        alloc.free(self.packages_dir);
        alloc.free(self.templates_dir);
    }

    pub fn effectiveVersion(alloc: std.mem.Allocator, version: []const u8, is_snapshot: bool) ![]u8 {
        if (is_snapshot and !std.mem.endsWith(u8, version, constants.HivePaths.snapshot_suffix)) {
            return try std.fmt.allocPrint(alloc, "{s}{s}", .{ version, constants.HivePaths.snapshot_suffix });
        }
        return try alloc.dupe(u8, version);
    }

    /// `<packages_dir>/<name>/<version>[-snapshot]/`
    pub fn packageVersionDir(self: *const HiveHome, alloc: std.mem.Allocator, name: []const u8, version: []const u8) ![]u8 {
        return try std.fs.path.join(alloc, &.{ self.packages_dir, name, version });
    }

    /// `<packages_dir>/<name>/<version>[-snapshot]/<target>/`
    pub fn packageTargetDir(
        self: *const HiveHome,
        alloc: std.mem.Allocator,
        name: []const u8,
        version: []const u8,
        target: []const u8,
    ) ![]u8 {
        return try std.fs.path.join(alloc, &.{ self.packages_dir, name, version, target });
    }

    /// `<templates_dir>/<template-name>/`
    pub fn templateDir(self: *const HiveHome, alloc: std.mem.Allocator, template_name: []const u8) ![]u8 {
        return try std.fs.path.join(alloc, &.{ self.templates_dir, template_name });
    }

    pub fn credentialsPath(self: *const HiveHome, alloc: std.mem.Allocator) ![]u8 {
        return try std.fs.path.join(alloc, &.{ self.base_dir, constants.HivePaths.credentials_file });
    }

    pub fn trustedKeysDir(self: *const HiveHome, alloc: std.mem.Allocator) ![]u8 {
        return try std.fs.path.join(alloc, &.{ self.base_dir, constants.HivePaths.trusted_keys_dir });
    }
};
