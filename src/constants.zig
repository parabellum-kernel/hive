const std = @import("std");

/// Converts an enum tag name at comptime, replacing `_` with `-` (for CLI flags).
pub fn enumToKebab(comptime tag: anytype) []const u8 {
    const raw = @tagName(tag);
    return comptime blk: {
        var buf: [raw.len]u8 = undefined;
        for (raw, 0..) |ch, i| {
            buf[i] = if (ch == '_') '-' else ch;
        }
        const final = buf;
        break :blk &final;
    };
}

/// Centralized environment variable names used across `hive`.
pub const EnvVar = enum {
    HIVE_HOME,
    HIVE_GIT_BIN,
    HIVE_WORKERS,
    GIT_TERMINAL_PROMPT,
    NO_COLOR,
    GITHUB_TOKEN,
    HIVE_GITHUB_TOKEN,
    HIVE_HTTP_TOKEN,

    pub fn key(self: EnvVar) []const u8 {
        return @tagName(self);
    }
};

/// Centralized file and directory names for `~/.hive/` and project roots.
pub const HivePaths = struct {
    pub const hive_dir = ".hive";
    pub const packages_dir = "packages";
    pub const templates_dir = "templates";
    pub const trusted_keys_dir = "trusted-keys";
    pub const credentials_file = "credentials.json";
    pub const manifest_file = "manifest.json";
    pub const template_file = "template.json";
    pub const hive_json = "hive.json";
    pub const build_zig = "build.zig";
    pub const build_zig_zon = "build.zig.zon";
    pub const checksums_file = "SHA256SUMS.txt";
    pub const snapshot_suffix = "-snapshot";

    pub const project_markers = [_][]const u8{
        build_zig,
        hive_json,
        "hive.yaml",
        "workspace.yaml",
    };
};

/// Centralized Zig workspace & VCS directory names.
pub const ZigDirs = struct {
    pub const dot_git = ".git";
    pub const dot_zig_cache = ".zig-cache";
    pub const zig_cache = "zig-cache";
    pub const zig_out = "zig-out";
    pub const zig_pkg = "zig-pkg";
    pub const dist = "dist";
    pub const docs = "docs";
    pub const lib = "lib";
    pub const bin = "bin";
};

/// Centralized default values.
pub const Defaults = struct {
    pub const app_name = "hive";
    pub const app_description = "native artifact & workspace build tool";
    pub const initial_version = "0.1.0";
    pub const release_branch = "main";
    pub const docs_step = "docs";
    pub const git_bin = "git";
    pub const native_target = "native";
};

/// Centralized binary/library file extensions.
pub const ArtifactExts = struct {
    pub const so = ".so";
    pub const dylib = ".dylib";
    pub const dll = ".dll";
    pub const static_exts = [_][]const u8{ ".a", ".lib" };
    pub const dynamic_exts = [_][]const u8{ so, dylib, dll };
};

/// Centralized `build.zig.zon` field names.
pub const ZonFields = struct {
    pub const name = "name";
    pub const version = "version";
};

/// Centralized Zig test step and flag names.
pub const TestSteps = struct {
    pub const unit = "test";
    pub const e2e = "test-e2e";
    pub const filter_prefix = "-Dtest-filter=";
    pub const optimize_prefix = "-Doptimize=";
    pub const target_prefix = "-Dtarget=";
    pub const zig_bin = "zig";
    pub const zig_build_cmd = "build";
    pub const help_flag = "--help";
};

/// Centralized Git URL schemes and plumbing tokens for `libgit`.
pub const GitPlumbing = struct {
    pub const version_prefix = "git version ";
    pub const git_suffix = ".git";
    pub const refs_tags_prefix = "refs/tags/";

    pub const schemes = struct {
        pub const git_ssh = "git+ssh://";
        pub const git_https = "git+https://";
        pub const git_http = "git+http://";
        pub const ssh = "ssh://";
        pub const https = "https://";
        pub const http = "http://";
        pub const git_at = "git@";
        pub const git_prefix = "git+";
    };

    pub const cmd = struct {
        pub const version = "--version";
        pub const clone = "clone";
        pub const pull = "pull";
        pub const status = "status";
        pub const rev_parse = "rev-parse";
        pub const commit = "commit";
        pub const tag = "tag";
        pub const push = "push";
    };

    pub const flag = struct {
        pub const end_of_opts = "--";
        pub const depth = "--depth";
        pub const branch = "--branch";
        pub const ff_only = "--ff-only";
        pub const porcelain_v1 = "--porcelain=v1";
        pub const abbrev_ref = "--abbrev-ref";
        pub const verify = "--verify";
        pub const message = "-m";
        pub const annotated = "-a";
        pub const follow_tags = "--follow-tags";
        pub const head = "HEAD";
    };
};
