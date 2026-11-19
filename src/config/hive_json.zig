const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../constants.zig");

pub const RepositoryType = enum {
    local,
    github,
    http,
    git,
};

pub const RepositorySpec = struct {
    name: []const u8,
    type: RepositoryType,
    path: ?[]const u8 = null,
    owner: ?[]const u8 = null,
    url: ?[]const u8 = null,
    auth_env: ?[]const u8 = null,
    require_signature: bool = false,
};

pub const DependencySpec = struct {
    version: []const u8,
    repo: ?[]const u8 = null,
};

pub const AbiSpec = struct {
    required_symbols: []const []const u8 = &.{},
    any_of_symbols: []const []const u8 = &.{},
    validator: []const []const u8 = &.{},
};

pub const DocsSpec = struct {
    step: []const u8 = constants.Defaults.docs_step,
    root_source_file: ?[]const u8 = null,
};

pub const TestSpec = struct {
    e2e_args: []const []const u8 = &.{},
};

pub const ReleaseSpec = struct {
    branch: []const u8 = constants.Defaults.release_branch,
};

pub const PackageFormat = enum {
    bin,
    so,
    tar,
};

pub const PackagerSpec = struct {
    command: []const []const u8 = &.{},
};

pub const ProfileSpec = struct {
    format: ?PackageFormat = null,
    strip: ?bool = null,
    lto: ?bool = null,
    sources: ?bool = null,
    docs: ?bool = null,
    packagers: []const []const u8 = &.{},
};

pub const PackagingSpec = struct {
    default_format: PackageFormat = .so,
    sources: bool = false,
    docs: bool = false,
    entrypoint: ?[]const u8 = null,
    link_libs: []const []const u8 = &.{},
    packagers: std.json.ArrayHashMap(PackagerSpec) = .{},
    profiles: std.json.ArrayHashMap(ProfileSpec) = .{},
};

pub const HiveJsonSchema = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    modules: []const []const u8 = &.{},
    repositories: []const RepositorySpec = &.{},
    dependencies: std.json.ArrayHashMap(DependencySpec) = .{},
    abi: ?AbiSpec = null,
    docs: ?DocsSpec = null,
    @"test": ?TestSpec = null,
    release: ?ReleaseSpec = null,
    packaging: ?PackagingSpec = null,
};

pub const LoadedHiveConfig = struct {
    parsed: ?std.json.Parsed(HiveJsonSchema) = null,
    raw_bytes: ?[]u8 = null,
    alloc: std.mem.Allocator,

    pub fn value(self: *const LoadedHiveConfig) HiveJsonSchema {
        if (self.parsed) |p| return p.value;
        return .{};
    }

    pub fn deinit(self: *LoadedHiveConfig) void {
        if (self.parsed) |*p| p.deinit();
        if (self.raw_bytes) |b| self.alloc.free(b);
    }

    pub fn loadFromDir(alloc: std.mem.Allocator, fs: platform.PlatformFs, project_dir: []const u8) !LoadedHiveConfig {
        const path = try std.fs.path.join(alloc, &.{ project_dir, constants.HivePaths.hive_json });
        defer alloc.free(path);

        if (!fs.exists(alloc, path)) {
            return .{ .alloc = alloc };
        }

        const bytes = try fs.readFileAlloc(alloc, path, 2 * 1024 * 1024);
        errdefer alloc.free(bytes);

        const parsed = try std.json.parseFromSlice(HiveJsonSchema, alloc, bytes, .{
            .ignore_unknown_fields = true,
        });

        return .{
            .parsed = parsed,
            .raw_bytes = bytes,
            .alloc = alloc,
        };
    }
};
