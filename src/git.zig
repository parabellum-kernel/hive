const std = @import("std");
const platform = @import("parabellum_platform");
const constants = @import("constants.zig");

pub const GitError = error{
    GitNotFound,
    UnsupportedGitVersion,
    CommandFailed,
    DirtyWorkingTree,
    TagAlreadyExists,
    AuthenticationFailed,
    NetworkError,
    OutOfMemory,
};

pub const GitVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn parse(raw: []const u8) ?GitVersion {
        // Expected: "git version 2.43.0" (or similar)
        const prefix = constants.GitPlumbing.version_prefix;
        const idx = std.mem.indexOf(u8, raw, prefix) orelse return null;
        const rest = std.mem.trim(u8, raw[idx + prefix.len ..], " \r\n\t");
        var it = std.mem.splitScalar(u8, rest, '.');
        const maj_s = it.next() orelse return null;
        const min_s = it.next() orelse return null;
        const pat_s = it.next() orelse "0";

        const maj = std.fmt.parseInt(u32, maj_s, 10) catch return null;
        const min = std.fmt.parseInt(u32, min_s, 10) catch return null;
        const pat_clean = std.mem.sliceTo(pat_s, ' ');
        const pat = std.fmt.parseInt(u32, pat_clean, 10) catch 0;

        return .{ .major = maj, .minor = min, .patch = pat };
    }

    pub fn atLeast(self: GitVersion, min_ver: GitVersion) bool {
        if (self.major != min_ver.major) return self.major > min_ver.major;
        if (self.minor != min_ver.minor) return self.minor > min_ver.minor;
        return self.patch >= min_ver.patch;
    }
};

pub const CloneOptions = struct {
    depth: ?u32 = null,
    branch: ?[]const u8 = null,
};

/// `libgit` — Lightweight Git plumbing client backed by `PlatformServices.runner` (`ProcessRunner` VTable).
pub const GitClient = struct {
    git_bin: []const u8,
    runner: platform.ProcessRunner,

    pub const min_supported_version = GitVersion{ .major = 2, .minor = 20, .patch = 0 };

    pub fn init(alloc: std.mem.Allocator, env: platform.PlatformEnv, runner: platform.ProcessRunner) !GitClient {
        const bin = env.getEnv(alloc, constants.EnvVar.HIVE_GIT_BIN.key()) orelse
            try alloc.dupe(u8, constants.Defaults.git_bin);
        return .{
            .git_bin = bin,
            .runner = runner,
        };
    }

    pub fn deinit(self: *GitClient, alloc: std.mem.Allocator) void {
        alloc.free(self.git_bin);
    }

    /// Normalizes Zig-style `git+ssh://` and `git+https://` prefixes for `git`.
    pub fn normalizeUrl(url: []const u8) []const u8 {
        const s = constants.GitPlumbing.schemes;
        if (std.mem.startsWith(u8, url, s.git_ssh)) return url[s.git_prefix.len..];
        if (std.mem.startsWith(u8, url, s.git_https)) return url[s.git_prefix.len..];
        if (std.mem.startsWith(u8, url, s.git_http)) return url[s.git_prefix.len..];
        return url;
    }

    /// Extracts canonical repository short name (e.g. `git@github.com:org/parabellum-plugin.git` -> `parabellum-plugin`).
    pub fn extractRepoName(url: []const u8) []const u8 {
        const trimmed = std.mem.trimEnd(u8, url, "/");
        const last_slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
        const last_colon = std.mem.lastIndexOfScalar(u8, trimmed, ':');
        const split_idx = if (last_slash) |s|
            (if (last_colon) |c| @max(s, c) else s)
        else
            last_colon;

        const base = if (split_idx) |idx| trimmed[idx + 1 ..] else trimmed;
        if (std.mem.endsWith(u8, base, constants.GitPlumbing.git_suffix)) {
            return base[0 .. base.len - constants.GitPlumbing.git_suffix.len];
        }
        return base;
    }

    fn runGit(self: *const GitClient, alloc: std.mem.Allocator, cwd: ?[]const u8, args: []const []const u8) !platform.process.ProcessResult {
        var argv = try alloc.alloc([]const u8, args.len + 1);
        defer alloc.free(argv);
        argv[0] = self.git_bin;
        @memcpy(argv[1..], args);

        return self.runner.run(alloc, .{
            .argv = argv,
            .cwd = cwd,
            .env_overrides = &.{.{ .key = constants.EnvVar.GIT_TERMINAL_PROMPT.key(), .value = "0" }},
        }) catch return error.GitNotFound;
    }

    pub fn version(self: *const GitClient, alloc: std.mem.Allocator) GitError!GitVersion {
        var res = try self.runGit(alloc, null, &.{constants.GitPlumbing.cmd.version});
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
        const v = GitVersion.parse(res.stdout) orelse return error.UnsupportedGitVersion;
        if (!v.atLeast(min_supported_version)) return error.UnsupportedGitVersion;
        return v;
    }

    pub fn clone(self: *const GitClient, alloc: std.mem.Allocator, url: []const u8, dest: []const u8, opts: CloneOptions) GitError!void {
        var args: std.ArrayListUnmanaged([]const u8) = .empty;
        defer args.deinit(alloc);

        try args.append(alloc, constants.GitPlumbing.cmd.clone);
        var depth_buf: [32]u8 = undefined;
        if (opts.depth) |d| {
            try args.append(alloc, constants.GitPlumbing.flag.depth);
            const d_str = std.fmt.bufPrint(&depth_buf, "{d}", .{d}) catch "1";
            try args.append(alloc, d_str);
        }
        if (opts.branch) |b| {
            try args.append(alloc, constants.GitPlumbing.flag.branch);
            try args.append(alloc, b);
        }
        try args.append(alloc, constants.GitPlumbing.flag.end_of_opts);
        try args.append(alloc, normalizeUrl(url));
        try args.append(alloc, dest);

        var res = try self.runGit(alloc, null, args.items);
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
    }

    pub fn pullFastForward(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8) GitError!void {
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.pull, constants.GitPlumbing.flag.ff_only });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
    }

    pub fn isClean(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8) GitError!bool {
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.status, constants.GitPlumbing.flag.porcelain_v1 });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
        return std.mem.trim(u8, res.stdout, " \r\n\t").len == 0;
    }

    pub fn currentBranch(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8) GitError![]u8 {
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.rev_parse, constants.GitPlumbing.flag.abbrev_ref, constants.GitPlumbing.flag.head });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
        return try alloc.dupe(u8, std.mem.trim(u8, res.stdout, " \r\n\t"));
    }

    pub fn tagExists(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8, tag: []const u8) GitError!bool {
        const ref = try std.fmt.allocPrint(alloc, "{s}{s}", .{ constants.GitPlumbing.refs_tags_prefix, tag });
        defer alloc.free(ref);
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.rev_parse, constants.GitPlumbing.flag.verify, ref });
        defer res.deinit(alloc);
        return res.exit_code == 0;
    }

    pub fn commit(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8, message: []const u8) GitError!void {
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.commit, constants.GitPlumbing.flag.message, message });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
    }

    pub fn createAnnotatedTag(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8, tag: []const u8, message: []const u8) GitError!void {
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.tag, constants.GitPlumbing.flag.annotated, tag, constants.GitPlumbing.flag.message, message });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
    }

    pub fn pushWithTags(self: *const GitClient, alloc: std.mem.Allocator, repo_dir: []const u8, remote: []const u8, branch: []const u8) GitError!void {
        var res = try self.runGit(alloc, repo_dir, &.{ constants.GitPlumbing.cmd.push, remote, branch, constants.GitPlumbing.flag.follow_tags });
        defer res.deinit(alloc);
        if (res.exit_code != 0) return error.CommandFailed;
    }
};
