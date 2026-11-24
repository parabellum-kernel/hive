const std = @import("std");
const sdk = @import("parabellum_sdk");
const config = @import("../../config/mod.zig");
const constants = @import("../../constants.zig");

pub const PackageInputs = struct {
    project_dir: []const u8 = ".",
    format: []const u8 = "",
    strip: bool = false,
    lto: bool = false,
    sources: bool = false,
    docs: bool = false,
    packager: []const u8 = "",
    profile: []const u8 = "",
    verify_abi: bool = true,
    target: []const u8 = constants.Defaults.native_target,
    artifact_repository_dir: []const u8 = "",
    module_filter: []const u8 = "",
};

pub const PackageModuleRef = struct {
    order_index: i64,
    repo_dir: []const u8,
    format_override: []const u8,
    strip: bool,
    lto: bool,
    sources: bool,
    docs: bool,
    packager_override: []const u8,
    profile_name: []const u8,
    verify_abi: bool,
    target: []const u8,
    target_explicit: bool = false,
    packages_dir: []const u8,
};

pub const PackagePlanTask = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    version: []const u8,
    target: []const u8,
    format: []const u8,
    strip: bool,
    lto: bool,
    sources: bool,
    docs: bool,
    verify_abi: bool,
    dist_dir: []const u8,
    output_path: []const u8,
    packages_dir: []const u8,
    packagers_packed: []const u8,
};

pub const PackageAssembled = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    version: []const u8,
    target: []const u8,
    format: []const u8,
    dist_dir: []const u8,
    output_path: []const u8,
    sources_tarball: []const u8,
    docs_tarball: []const u8,
    packagers_packed: []const u8,
};

pub const PackageResult = struct {
    order_index: i64,
    repo_dir: []const u8,
    module_name: []const u8,
    version: []const u8,
    target: []const u8,
    format: []const u8,
    dist_dir: []const u8,
    output_path: []const u8,
    sha256: []const u8,
    size_bytes: i64,
    sidecars_packed: []const u8 = "",
};

pub const PackageSummarizeInputs = struct {
    results: sdk.task.Rows(PackageResult),
};

pub const PackageOutputs = struct {
    packages_created: i64,
    total_bytes: i64,
};

pub fn lessThanPackageResult(_: void, a: PackageResult, b: PackageResult) bool {
    return a.order_index < b.order_index;
}

pub const TargetFamily = enum {
    elf,
    macho,
    coff,
};

/// Derives the binary object format family from a Zig target triple.
pub fn targetFamily(target: []const u8) TargetFamily {
    if (target.len == 0 or std.mem.eql(u8, target, constants.Defaults.native_target)) {
        return switch (@import("builtin").os.tag) {
            .macos, .ios, .tvos, .watchos => .macho,
            .windows => .coff,
            else => .elf,
        };
    }
    if (std.mem.indexOf(u8, target, "windows") != null) return .coff;
    if (std.mem.indexOf(u8, target, "macos") != null or
        std.mem.indexOf(u8, target, "darwin") != null or
        std.mem.indexOf(u8, target, "ios") != null) return .macho;
    return .elf;
}

pub fn targetExeExt(target: []const u8) []const u8 {
    return if (targetFamily(target) == .coff) ".exe" else "";
}

pub fn targetSharedLibPrefix(target: []const u8) []const u8 {
    return if (targetFamily(target) == .coff) "" else "lib";
}

pub fn targetSharedLibExt(target: []const u8) []const u8 {
    return switch (targetFamily(target)) {
        .coff => constants.ArtifactExts.dll,
        .macho => constants.ArtifactExts.dylib,
        .elf => constants.ArtifactExts.so,
    };
}

pub fn formatOutputFilename(
    alloc: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    target: []const u8,
    fmt: config.hive_json.PackageFormat,
) ![]u8 {
    return switch (fmt) {
        .bin => try std.fmt.allocPrint(alloc, "{s}{s}", .{ name, targetExeExt(target) }),
        .so => try std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ targetSharedLibPrefix(target), name, targetSharedLibExt(target) }),
        .tar => try std.fmt.allocPrint(alloc, "{s}-{s}-{s}.tar.gz", .{ name, version, target }),
    };
}
