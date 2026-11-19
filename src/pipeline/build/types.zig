const std = @import("std");
const sdk = @import("parabellum_sdk");
const platform = @import("parabellum_platform");
const constants = @import("../../constants.zig");

pub const OptimizeMode = enum {
    Debug,
    ReleaseSafe,
    ReleaseFast,
    ReleaseSmall,
};

pub const LinkageMode = enum {
    static,
    dynamic,
    both,
};

pub const ArtifactKind = enum {
    static,
    dynamic,
    bin,
};

pub const BuildInputs = struct {
    project_dir: []const u8 = ".",
    optimize: []const u8 = @tagName(OptimizeMode.Debug),
    target: []const u8 = constants.Defaults.native_target,
    linkage: []const u8 = @tagName(LinkageMode.both),
    verify_abi: bool = true,
    module_filter: []const u8 = "",
    extra_args_packed: []const u8 = "",
};

pub const BuildModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    optimize: []const u8,
    target: []const u8,
    linkage: []const u8,
    verify_abi: bool,
    extra_args_packed: []const u8,
};

pub const BuildArtifactTask = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    artifact_path: []const u8,
    kind: []const u8,
    verify_abi: bool,
    validator_packed: []const u8,
};

pub const BuildArtifactResult = struct {
    order_index: i64,
    module_name: []const u8,
    artifact_path: []const u8,
    kind: []const u8,
    sha256: []const u8,
    bytes: i64,
};

pub fn lessThanArtifactResult(_: void, a: BuildArtifactResult, b: BuildArtifactResult) bool {
    if (a.order_index != b.order_index) return a.order_index < b.order_index;
    return std.mem.order(u8, a.artifact_path, b.artifact_path) == .lt;
}

pub const BuildSummarizeInputs = struct {
    results: sdk.task.Rows(BuildArtifactResult),
};

pub const BuildOutputs = struct {
    total_artifacts: i64,
    total_bytes: i64,
};

pub fn computeSha256Hex(data: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn classifyLibArtifact(filename: []const u8) ?ArtifactKind {
    for (constants.ArtifactExts.static_exts) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) return .static;
    }
    for (constants.ArtifactExts.dynamic_exts) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) return .dynamic;
    }
    return null;
}

pub fn classifyBinArtifact(filename: []const u8) ArtifactKind {
    if (std.mem.endsWith(u8, filename, constants.ArtifactExts.dll)) return .dynamic;
    return .bin;
}

/// Validates basic binary magic bytes (ELF, Mach-O, PE/COFF) for shared libraries.
pub fn hasValidBinaryMagic(data: []const u8) bool {
    if (data.len < 4) return false;
    // ELF: \x7fELF
    if (std.mem.eql(u8, data[0..4], "\x7fELF")) return true;
    // PE/COFF: MZ
    if (data[0] == 'M' and data[1] == 'Z') return true;
    // Mach-O 32/64/universal magic
    const m = std.mem.readInt(u32, data[0..4], .little);
    return m == 0xfeedface or m == 0xcefaedfe or
        m == 0xfeedfacf or m == 0xcffaedfe or
        m == 0xcafebabe or m == 0xbebafeca;
}

/// Extracts `.name` or `.version` string literal from `build.zig.zon` as a lightweight fallback.
pub fn extractZonField(zon_bytes: []const u8, field_name: []const u8) ?[]const u8 {
    var key_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&key_buf, ".{s}", .{field_name}) catch return null;
    const key_idx = std.mem.indexOf(u8, zon_bytes, needle) orelse return null;
    const eq_idx = std.mem.indexOfPos(u8, zon_bytes, key_idx + needle.len, "=") orelse return null;
    const after_eq = std.mem.trimStart(u8, zon_bytes[eq_idx + 1 ..], " \t\r\n");

    if (after_eq.len > 0 and after_eq[0] == '"') {
        const end_q = std.mem.indexOfScalarPos(u8, after_eq, 1, '"') orelse return null;
        return after_eq[1..end_q];
    }
    if (after_eq.len > 1 and after_eq[0] == '.') {
        // `.name = .hive,` enum literal syntax in Zig 0.14+ ZON
        const rest = after_eq[1..];
        var end: usize = 0;
        while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_' or rest[end] == '-')) : (end += 1) {}
        if (end > 0) return rest[0..end];
    }
    return null;
}

pub fn resolveProjectNameAndVersion(
    alloc: std.mem.Allocator,
    fs: platform.PlatformFs,
    repo_dir: []const u8,
    cfg_name: ?[]const u8,
    cfg_version: ?[]const u8,
) !struct { name: []u8, version: []u8 } {
    var name: ?[]u8 = if (cfg_name) |n| try alloc.dupe(u8, n) else null;
    errdefer if (name) |n| alloc.free(n);
    var version: ?[]u8 = if (cfg_version) |v| try alloc.dupe(u8, v) else null;
    errdefer if (version) |v| alloc.free(v);

    if (name == null or version == null) {
        const zon_path = try std.fs.path.join(alloc, &.{ repo_dir, constants.HivePaths.build_zig_zon });
        defer alloc.free(zon_path);
        if (fs.exists(alloc, zon_path)) {
            if (fs.readFileAlloc(alloc, zon_path, 1024 * 1024)) |zon_bytes| {
                defer alloc.free(zon_bytes);
                if (name == null) {
                    if (extractZonField(zon_bytes, constants.ZonFields.name)) |n| name = try alloc.dupe(u8, n);
                }
                if (version == null) {
                    if (extractZonField(zon_bytes, constants.ZonFields.version)) |v| version = try alloc.dupe(u8, v);
                }
            } else |_| {}
        }
    }

    return .{
        .name = name orelse try alloc.dupe(u8, std.fs.path.basename(repo_dir)),
        .version = version orelse try alloc.dupe(u8, constants.Defaults.initial_version),
    };
}
