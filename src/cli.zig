const std = @import("std");
const sdk = @import("parabellum_sdk");
const build_options = @import("build_options");
const constants = @import("constants.zig");

pub const sdk_cli = sdk.cli;

pub const GoalCategory = enum {
    standalone,
    opt_in,
    core_linear,
};

pub const Goal = enum {
    config,
    init,
    add,
    clean,
    fetch,
    build,
    @"test",
    docs,
    package,
    install,
    publish,
    release,

    pub fn name(self: Goal) []const u8 {
        return @tagName(self);
    }

    pub fn category(self: Goal) GoalCategory {
        return switch (self) {
            .config, .init, .add => .standalone,
            .clean, .fetch, .docs, .release => .opt_in,
            .build, .@"test", .package, .install, .publish => .core_linear,
        };
    }

    /// 0-based index for core linear lifecycle phases (`build=0 .. publish=4`).
    pub fn linearIndex(self: Goal) ?usize {
        return switch (self) {
            .build => 0,
            .@"test" => 1,
            .package => 2,
            .install => 3,
            .publish => 4,
            else => null,
        };
    }

    pub fn description(self: Goal) []const u8 {
        return switch (self) {
            .config => "Inspect or edit project/global environment configuration",
            .init => "Scaffold a new project from a template",
            .add => "Add a dependency to build.zig.zon or hive.json",
            .clean => "Remove Zig build caches (and optionally zig-out / snapshots)",
            .fetch => "Resolve and download declared dependencies into ~/.hive/packages",
            .build => "Compile Zig targets and validate ABI contracts",
            .@"test" => "Execute unit and integration test suites",
            .docs => "Generate static HTML API documentation via autodoc",
            .package => "Assemble compiled artifacts into final deliverables",
            .install => "Install packaged artifacts into local ~/.hive/packages",
            .publish => "Upload packaged artifacts to a remote repository",
            .release => "Bump versions, tag in Git, and sync downstream build.zig.zon",
        };
    }
};

pub const core_linear_goals = [_]Goal{ .build, .@"test", .package, .install, .publish };

pub const GlobalFlag = enum {
    help,
    version,
    exclude,
    artifact_repository_dir,
    templates_dir,
    module,
    cwd,
    parallel,
    verbose,
    quiet,
    json,
    no_color,

    pub fn flagName(comptime self: GlobalFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const CommonFlag = enum {
    dry_run,
    offline,
    refresh,
    force,
    force_untested,

    pub fn flagName(comptime self: CommonFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const CleanFlag = enum {
    include_out,
    include_zig_pkg,
    snapshots,
    repo_dir,

    pub fn flagName(comptime self: CleanFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const InitFlag = enum {
    template,
    dir,
    version,
    @"var",
    refresh,
    force,

    pub fn flagName(comptime self: InitFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const FetchFlag = enum {
    offline,
    refresh,
    target,

    pub fn flagName(comptime self: FetchFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const BuildFlag = enum {
    optimize,
    target,
    linkage,
    verify_abi,
    no_verify_abi,

    pub fn flagName(comptime self: BuildFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const TestFlag = enum {
    tier,
    filter,
    fail_fast,
    optimize,

    pub fn flagName(comptime self: TestFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const AddFlag = enum {
    version,
    proto,
    repo,
    as,
    zon,

    pub fn flagName(comptime self: AddFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const InstallFlag = enum {
    snapshot,
    release,
    force,
    target,

    pub fn flagName(comptime self: InstallFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const DocsFlag = enum {
    step,
    out_dir,
    package,
    optimize,

    pub fn flagName(comptime self: DocsFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const ReleaseFlag = enum {
    version,
    bump,
    sync_downstream,
    publish,

    pub fn flagName(comptime self: ReleaseFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const PublishFlag = enum {
    repo,
    snapshot,
    release,
    version,
    targets,
    ecc,

    pub fn flagName(comptime self: PublishFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const PackageFlag = enum {
    format,
    strip,
    lto,
    sources,
    docs,
    packager,
    profile,
    verify_abi,
    no_verify_abi,

    pub fn flagName(comptime self: PackageFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const ConfigFlag = enum {
    global,
    set,
    unset,

    pub fn flagName(comptime self: ConfigFlag) []const u8 {
        return constants.enumToKebab(self);
    }
};

pub const GlobalOptions = struct {
    artifact_repository_dir: ?[]const u8 = null,
    templates_dir: ?[]const u8 = null,
    module: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    parallel: ?usize = null,
    verbose: bool = false,
    quiet: bool = false,
    json: bool = false,
    no_color: bool = false,
    excludes: []const Goal = &.{},

    pub fn fromParsed(alloc: std.mem.Allocator, parsed: *const sdk_cli.ParsedCli) !GlobalOptions {
        const raw_excludes = parsed.getValues(GlobalFlag.exclude.flagName());
        var excl_list: std.ArrayListUnmanaged(Goal) = .empty;
        errdefer excl_list.deinit(alloc);

        for (raw_excludes) |ex| {
            const g = std.meta.stringToEnum(Goal, ex) orelse return error.UnknownExcludedGoal;
            try excl_list.append(alloc, g);
        }

        const parallel_val: ?usize = if (parsed.getValue(GlobalFlag.parallel.flagName())) |p_str|
            std.fmt.parseInt(usize, p_str, 10) catch return error.InvalidParallelCount
        else
            null;

        return .{
            .artifact_repository_dir = parsed.getValue(GlobalFlag.artifact_repository_dir.flagName()),
            .templates_dir = parsed.getValue(GlobalFlag.templates_dir.flagName()),
            .module = parsed.getValue(GlobalFlag.module.flagName()),
            .cwd = parsed.getValue(GlobalFlag.cwd.flagName()),
            .parallel = parallel_val,
            .verbose = parsed.hasFlag(GlobalFlag.verbose.flagName()),
            .quiet = parsed.hasFlag(GlobalFlag.quiet.flagName()),
            .json = parsed.hasFlag(GlobalFlag.json.flagName()),
            .no_color = parsed.hasFlag(GlobalFlag.no_color.flagName()),
            .excludes = try excl_list.toOwnedSlice(alloc),
        };
    }

    pub fn deinit(self: *GlobalOptions, alloc: std.mem.Allocator) void {
        if (self.excludes.len > 0) {
            alloc.free(self.excludes);
        }
    }
};

pub fn buildCliApp(alloc: std.mem.Allocator) !sdk_cli.CliApp {
    var builder = sdk_cli.CliBuilder.init(alloc, constants.Defaults.app_name, build_options.version);
    errdefer builder.deinit();

    _ = builder.withDescription(constants.Defaults.app_description);

    _ = try builder.addGlobalOptions(&.{
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.help, 'h', .flag, null, "Print usage information"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.version, 'v', .flag, null, "Print hive version and exit"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.exclude, 'x', .multi_value, "<goal>", "Skip an upstream phase in the linear lifecycle"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.artifact_repository_dir, null, .value, "<path>", "Override local Artifact Repository root"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.templates_dir, null, .value, "<path>", "Override local template cache root"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.module, null, .value, "<name>", "Target a specific module in workspace mode"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.cwd, 'C', .value, "<path>", "Run hive as if invoked inside <path>"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.parallel, 'j', .value, "<n>", "Worker thread count (overrides HIVE_WORKERS)"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.verbose, null, .flag, null, "Emit detailed diagnostic logs"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.quiet, 'q', .flag, null, "Suppress non-essential output"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.json, null, .flag, null, "Emit machine-readable JSON output"),
        sdk_cli.OptionSpec.fromEnum(GlobalFlag.no_color, null, .flag, null, "Disable ANSI colors in terminal output"),
    });

    inline for (std.enums.values(Goal)) |g| {
        const opts: []const sdk_cli.OptionSpec = comptime switch (g) {
            .config => &.{
                sdk_cli.OptionSpec.fromEnum(ConfigFlag.global, 'g', .flag, null, "Target global ~/.hive/.env instead of project .env"),
                sdk_cli.OptionSpec.fromEnum(ConfigFlag.set, null, .multi_value, "<KEY=VALUE>", "Set or update an environment variable in .env"),
                sdk_cli.OptionSpec.fromEnum(ConfigFlag.unset, null, .multi_value, "<KEY>", "Remove an environment variable from .env"),
            },
            .init => &.{
                sdk_cli.OptionSpec.fromEnum(InitFlag.template, 't', .value, "<tpl>", "Template name, local path, or Git URL"),
                sdk_cli.OptionSpec.fromEnum(InitFlag.dir, null, .value, "<path>", "Destination directory (default: ./<name>)"),
                sdk_cli.OptionSpec.fromEnum(InitFlag.version, null, .value, "<semver>", "Initial project version (default: 0.1.0)"),
                sdk_cli.OptionSpec.fromEnum(InitFlag.@"var", null, .multi_value, "<k=v>", "Custom template variable override"),
                sdk_cli.OptionSpec.fromEnum(InitFlag.refresh, null, .flag, null, "Pull latest changes if template is cached"),
                sdk_cli.OptionSpec.fromEnum(InitFlag.force, null, .value, "<policy>", "Conflict policy: none | overlay | wipe"),
            },
            .fetch => &.{
                sdk_cli.OptionSpec.fromEnum(FetchFlag.offline, null, .flag, null, "Resolve strictly from local repository without network"),
                sdk_cli.OptionSpec.fromEnum(FetchFlag.refresh, null, .flag, null, "Re-validate remote metadata / checksums"),
                sdk_cli.OptionSpec.fromEnum(FetchFlag.target, null, .value, "<triple>", "Target Zig triple (default: native)"),
            },
            .build => &.{
                sdk_cli.OptionSpec.fromEnum(BuildFlag.optimize, null, .value, "<mode>", "Debug | ReleaseSafe | ReleaseFast | ReleaseSmall"),
                sdk_cli.OptionSpec.fromEnum(BuildFlag.target, null, .value, "<triple>", "Cross-compilation Zig target triple"),
                sdk_cli.OptionSpec.fromEnum(BuildFlag.linkage, null, .value, "<kind>", "static | dynamic | both"),
                sdk_cli.OptionSpec.fromEnum(BuildFlag.verify_abi, null, .flag, null, "Verify ABI binary format & contracts (default: true)"),
                sdk_cli.OptionSpec.fromEnum(BuildFlag.no_verify_abi, null, .flag, null, "Skip ABI contract verification"),
            },
            .@"test" => &.{
                sdk_cli.OptionSpec.fromEnum(TestFlag.tier, null, .value, "<tier>", "unit | e2e | all (default: unit)"),
                sdk_cli.OptionSpec.fromEnum(TestFlag.filter, null, .value, "<expr>", "Optional test name filter"),
                sdk_cli.OptionSpec.fromEnum(TestFlag.fail_fast, null, .flag, null, "Stop immediately on first failing repo"),
                sdk_cli.OptionSpec.fromEnum(TestFlag.optimize, null, .value, "<mode>", "Debug | ReleaseSafe"),
            },
            .install => &.{
                sdk_cli.OptionSpec.fromEnum(InstallFlag.snapshot, null, .flag, null, "Install under <version>-snapshot (default: true)"),
                sdk_cli.OptionSpec.fromEnum(InstallFlag.release, null, .flag, null, "Install under immutable <version>"),
                sdk_cli.OptionSpec.fromEnum(InstallFlag.force, null, .flag, null, "Overwrite existing stable <version> target"),
                sdk_cli.OptionSpec.fromEnum(InstallFlag.target, null, .value, "<triple>", "Target Zig triple (default: native)"),
            },
            .docs => &.{
                sdk_cli.OptionSpec.fromEnum(DocsFlag.step, null, .value, "<step>", "Custom build.zig step name (default: docs)"),
                sdk_cli.OptionSpec.fromEnum(DocsFlag.out_dir, null, .value, "<path>", "Output HTML directory (default: zig-out/docs)"),
                sdk_cli.OptionSpec.fromEnum(DocsFlag.package, null, .flag, null, "Bundle into zig-out/dist/<name>-docs.tar.gz"),
                sdk_cli.OptionSpec.fromEnum(DocsFlag.optimize, null, .value, "<mode>", "Debug | ReleaseSafe"),
            },
            .package => &.{
                sdk_cli.OptionSpec.fromEnum(PackageFlag.format, null, .value, "<fmt>", "bin | so | tar"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.strip, null, .flag, null, "Strip debug symbols from deliverable"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.lto, null, .flag, null, "Enable link-time optimization"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.sources, null, .flag, null, "Also produce <name>-sources.tar.gz"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.docs, null, .flag, null, "Also bundle zig-out/docs into <name>-docs.tar.gz"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.packager, null, .value, "<name>", "External packager from hive.json"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.profile, null, .value, "<name>", "Packaging profile from hive.json"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.verify_abi, null, .flag, null, "Verify ABI contract when --format=so"),
                sdk_cli.OptionSpec.fromEnum(PackageFlag.no_verify_abi, null, .flag, null, "Skip ABI verification"),
            },
            .clean => &.{
                sdk_cli.OptionSpec.fromEnum(CommonFlag.dry_run, 'n', .flag, null, "Report what would be deleted without deleting"),
                sdk_cli.OptionSpec.fromEnum(CleanFlag.include_out, null, .flag, null, "Also remove zig-out/ directories"),
                sdk_cli.OptionSpec.fromEnum(CleanFlag.include_zig_pkg, null, .flag, null, "Also remove nested caches inside zig-pkg/"),
                sdk_cli.OptionSpec.fromEnum(CleanFlag.snapshots, null, .flag, null, "Also purge *-snapshot packages in local repo"),
                sdk_cli.OptionSpec.fromEnum(CleanFlag.repo_dir, null, .value, "<path>", "Legacy alias for --artifact-repository-dir"),
            },
            .add => &.{
                sdk_cli.OptionSpec.fromEnum(AddFlag.version, 'v', .value, "<ver>", "Requested dependency version (default: latest)"),
                sdk_cli.OptionSpec.fromEnum(AddFlag.proto, null, .value, "<proto>", "artifact | git+https | git+ssh | http"),
                sdk_cli.OptionSpec.fromEnum(AddFlag.repo, 'r', .value, "<name>", "Repository name from hive.json"),
                sdk_cli.OptionSpec.fromEnum(AddFlag.as, null, .value, "<alias>", "Alias key in build.zig.zon or hive.json"),
                sdk_cli.OptionSpec.fromEnum(AddFlag.zon, null, .flag, null, "Force adding as build.zig.zon source dependency"),
            },
            .publish => &.{
                sdk_cli.OptionSpec.fromEnum(PublishFlag.repo, 'r', .value, "<name>", "Target repository name in hive.json"),
                sdk_cli.OptionSpec.fromEnum(PublishFlag.snapshot, null, .flag, null, "Publish as mutable <version>-snapshot"),
                sdk_cli.OptionSpec.fromEnum(PublishFlag.release, null, .flag, null, "Publish as immutable <version> release"),
                sdk_cli.OptionSpec.fromEnum(PublishFlag.version, null, .value, "<semver>", "Explicit version override"),
                sdk_cli.OptionSpec.fromEnum(PublishFlag.targets, null, .value, "<triples>", "Target Zig triple (default: native)"),
                sdk_cli.OptionSpec.fromEnum(PublishFlag.ecc, null, .flag, null, "Generate .ecc parity sidecar"),
                sdk_cli.OptionSpec.fromEnum(CommonFlag.dry_run, 'n', .flag, null, "Run checks without network writes"),
                sdk_cli.OptionSpec.fromEnum(CommonFlag.force, null, .flag, null, "Overwrite existing remote stable assets"),
                sdk_cli.OptionSpec.fromEnum(CommonFlag.force_untested, null, .flag, null, "Allow -x test during publish"),
            },
            .release => &.{
                sdk_cli.OptionSpec.fromEnum(ReleaseFlag.version, null, .value, "<semver>", "Explicit release SemVer (no -snapshot)"),
                sdk_cli.OptionSpec.fromEnum(ReleaseFlag.bump, null, .value, "<kind>", "patch | minor | major"),
                sdk_cli.OptionSpec.fromEnum(ReleaseFlag.sync_downstream, null, .flag, null, "Update downstream build.zig.zon hashes"),
                sdk_cli.OptionSpec.fromEnum(ReleaseFlag.publish, null, .flag, null, "Also publish binary assets after tagging"),
                sdk_cli.OptionSpec.fromEnum(CommonFlag.dry_run, 'n', .flag, null, "Validate without committing or pushing"),
                sdk_cli.OptionSpec.fromEnum(CommonFlag.force_untested, null, .flag, null, "Bypass mandatory test gate"),
            },
        };

        _ = try builder.addCommand(.{
            .name = g.name(),
            .description = g.description(),
            .positional_name = "target",
            .options = opts,
            .allow_unknown_options = (g != .clean),
        });
    }

    return try builder.build();
}
