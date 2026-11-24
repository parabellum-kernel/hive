const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("../constants.zig");

pub const ArtifactKind = enum {
    dynamic,
    static,
    bin,
    sources,
    docs,
    sidecar,
};

pub const ManifestArtifact = struct {
    file: []const u8,
    kind: ArtifactKind,
    sha256: []const u8,
    size_bytes: u64,
    zon_hash: ?[]const u8 = null,
};

pub const BuildConfigFingerprint = struct {
    zig_version: []const u8,
    optimize: []const u8,
    cpu: []const u8 = constants.Defaults.baseline_cpu,
    lto: bool = false,
    bundle_compiler_rt: bool = false,
    config_hash: []const u8,
};

pub const ManifestDependency = struct {
    name: []const u8,
    version: []const u8,
};

pub const PackageManifest = struct {
    group: []const u8 = constants.Defaults.default_group,
    name: []const u8,
    version: []const u8,
    target: []const u8,
    installed_at: []const u8,
    build_config: ?BuildConfigFingerprint = null,
    dependencies: []const ManifestDependency = &.{},
    artifacts: []const ManifestArtifact = &.{},
};

pub const Coordinate = struct {
    group: []const u8,
    artifact: []const u8,
};

/// Parses `"<group>:<artifact>"` into `{ group, artifact }`, falling back to `default_group`
/// (typically `"local"`) when no `:` separator is present.
pub fn parseCoordinate(coord: []const u8, default_group: []const u8) Coordinate {
    if (std.mem.indexOfScalar(u8, coord, ':')) |colon| {
        const g = coord[0..colon];
        const a = coord[colon + 1 ..];
        if (g.len > 0 and a.len > 0) {
            return .{ .group = g, .artifact = a };
        }
    }
    return .{ .group = default_group, .artifact = coord };
}

/// Resolves `<packages_dir>/<group>/<artifact>/<version>/<target>` from a `group:artifact` coordinate.
pub fn joinPackageTargetDir(
    alloc: std.mem.Allocator,
    packages_dir: []const u8,
    coord: []const u8,
    version: []const u8,
    target: []const u8,
) ![]u8 {
    const c = parseCoordinate(coord, constants.Defaults.default_group);
    return try std.fs.path.join(alloc, &.{ packages_dir, c.group, c.artifact, version, target });
}

/// Computes the canonical SHA-256 hex fingerprint of a build configuration.
pub fn computeBuildConfigHash(
    zig_version: []const u8,
    optimize: []const u8,
    cpu: []const u8,
    lto: bool,
    bundle_compiler_rt: bool,
) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(zig_version);
    hasher.update("|");
    hasher.update(optimize);
    hasher.update("|");
    hasher.update(cpu);
    hasher.update("|");
    hasher.update(if (lto) "1" else "0");
    hasher.update("|");
    hasher.update(if (bundle_compiler_rt) "1" else "0");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

pub const LoadedBuildMeta = struct {
    parsed: ?std.json.Parsed(BuildConfigFingerprint) = null,

    pub fn value(self: *const LoadedBuildMeta) ?BuildConfigFingerprint {
        if (self.parsed) |p| return p.value;
        return null;
    }

    pub fn deinit(self: *LoadedBuildMeta) void {
        if (self.parsed) |*p| p.deinit();
    }

    pub fn loadFromRepo(alloc: std.mem.Allocator, fs: platform.PlatformFs, repo_dir: []const u8) LoadedBuildMeta {
        const meta_path = std.fs.path.join(alloc, &.{ repo_dir, constants.ZigDirs.dot_zig_cache, constants.HivePaths.hive_build_meta }) catch return .{};
        defer alloc.free(meta_path);
        if (!fs.exists(alloc, meta_path)) return .{};
        const bytes = fs.readFileAlloc(alloc, meta_path, 256 * 1024) catch return .{};
        defer alloc.free(bytes);
        const parsed = std.json.parseFromSlice(BuildConfigFingerprint, alloc, bytes, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return .{};
        return .{ .parsed = parsed };
    }
};

pub fn collectManifestDependencies(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    repo_dir: []const u8,
) ![]ManifestDependency {
    const hive_json = @import("hive_json.zig");
    var loaded_cfg = try hive_json.LoadedHiveConfig.loadFromDir(alloc, fs, repo_dir);
    defer loaded_cfg.deinit();
    const cfg = loaded_cfg.value();

    var deps: std.ArrayListUnmanaged(ManifestDependency) = .empty;
    errdefer {
        for (deps.items) |d| {
            alloc.free(d.name);
            alloc.free(d.version);
        }
        deps.deinit(alloc);
    }

    var it = cfg.dependencies.map.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const eff_ver = if (cfg.dependency_overrides.map.get(name)) |ov| ov.version else entry.value_ptr.version;
        try deps.append(alloc, .{
            .name = try alloc.dupe(u8, name),
            .version = try alloc.dupe(u8, eff_ver),
        });
    }
    return try deps.toOwnedSlice(alloc);
}

pub fn freeManifestDependencies(alloc: std.mem.Allocator, deps: []ManifestDependency) void {
    for (deps) |d| {
        alloc.free(d.name);
        alloc.free(d.version);
    }
    alloc.free(deps);
}

/// Formats the current UTC wall-clock time as an ISO-8601 timestamp (`YYYY-MM-DDTHH:MM:SSZ`).
pub fn formatUtcIso8601Now(alloc: std.mem.Allocator) ![]u8 {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const ts = std.Io.Clock.real.now(threaded.io()).toSeconds();
    const secs: u64 = if (ts >= 0) @intCast(ts) else 0;
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = secs };
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_secs.getDaySeconds();
    return try std.fmt.allocPrint(alloc, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    });
}

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
