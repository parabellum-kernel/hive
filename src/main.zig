const std = @import("std");
const hive = @import("hive");
const build_options = @import("build_options");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var std_term = hive.platform.io.StdTerminal{};
    const term = std_term.terminal();

    var app = try hive.cli.buildCliApp(arena);
    defer app.deinit();

    var parsed = app.parse(arena, args) catch |err| {
        const msg = std.fmt.allocPrint(arena, "hive: {s}. Run 'hive --help' for usage.\n", .{@errorName(err)}) catch "hive: invalid arguments\n";
        term.writeStderr(msg);
        return 2;
    };
    defer parsed.deinit();

    var global_opts = hive.cli.GlobalOptions.fromParsed(arena, &parsed) catch {
        term.writeStderr("hive: unknown goal in --exclude (-x).\n");
        return 2;
    };
    defer global_opts.deinit(arena);

    std_term.opts.quiet = global_opts.quiet;
    std_term.opts.no_color = global_opts.no_color;

    switch (parsed.action) {
        .help => {
            const help_text = try app.formatHelp(arena, parsed.help_command);
            term.writeStdout(help_text);
            return 0;
        },
        .version => {
            const out = try std.fmt.allocPrint(arena, "hive {s}\n", .{build_options.version});
            term.writeStdout(out);
            return 0;
        },
        .run => {},
    }

    var requested_goals: std.ArrayListUnmanaged(hive.cli.Goal) = .empty;
    defer requested_goals.deinit(arena);
    for (parsed.commands.items) |cmd_name| {
        if (std.meta.stringToEnum(hive.cli.Goal, cmd_name)) |g| {
            try requested_goals.append(arena, g);
        }
    }

    const target_dir = if (parsed.positionals.items.len > 0)
        parsed.positionals.items[0]
    else
        (global_opts.cwd orelse ".");

    const native_fs = hive.platform.fs.nativeFs();
    const native_env = hive.platform.env.nativeEnv();
    const project_dotenv = try hive.config.dotenv.loadDotEnvFile(arena, native_fs, target_dir);
    var resolved_home_for_env = try hive.config.HiveHome.resolve(arena, native_env, .{
        .artifact_repository_dir = global_opts.artifact_repository_dir,
        .templates_dir = global_opts.templates_dir,
    });
    defer resolved_home_for_env.deinit(arena);
    const global_dotenv = try hive.config.dotenv.loadDotEnvFile(arena, native_fs, resolved_home_for_env.base_dir);

    if (!std_term.opts.no_color) {
        if (native_env.getEnv(arena, hive.constants.EnvVar.NO_COLOR.key())) |nc| {
            defer arena.free(nc);
            if (nc.len > 0) std_term.opts.no_color = true;
        }
    }

    for (requested_goals.items) |g| {
        if (g == .config) {
            return try hive.config.inspect.runConfigCommand(arena, term, target_dir, global_opts, .{
                .global = parsed.hasFlag(hive.cli.ConfigFlag.global.flagName()),
                .set_vars = parsed.getValues(hive.cli.ConfigFlag.set.flagName()),
                .unset_keys = parsed.getValues(hive.cli.ConfigFlag.unset.flagName()),
                .project_dotenv = project_dotenv,
                .global_dotenv = global_dotenv,
            });
        }
    }

    const plan = hive.pipeline.planExecution(
        arena,
        requested_goals.items,
        global_opts.excludes,
        parsed.hasFlag(hive.cli.CommonFlag.force_untested.flagName()),
    ) catch |err| {
        const msg = std.fmt.allocPrint(arena, "hive: cannot plan execution ({s}).\n", .{@errorName(err)}) catch "hive: planning error\n";
        term.writeStderr(msg);
        return 2;
    };
    defer arena.free(plan);

    var packed_vars: std.ArrayListUnmanaged(u8) = .empty;
    defer packed_vars.deinit(arena);
    for (parsed.getValues(hive.cli.InitFlag.@"var".flagName())) |kv| {
        try packed_vars.appendSlice(arena, kv);
        try packed_vars.append(arena, '\n');
    }

    for (plan) |g| {
        if (g == .init) {
            if (parsed.positionals.items.len == 0) {
                term.writeStderr("hive init: missing project <name>. Run 'hive init --help' for usage.\n");
                return 2;
            }
            if (parsed.getValue(hive.cli.InitFlag.template.flagName()) == null) {
                term.writeStderr("hive init: missing required --template (-t) option.\n");
                return 2;
            }
        } else if (g == .add) {
            if (parsed.positionals.items.len == 0) {
                term.writeStderr("hive add: missing dependency <target>. Run 'hive add --help' for usage.\n");
                return 2;
            }
        }
    }

    const plan_opts = hive.runtime.PlanOptions{
        .workers = global_opts.parallel,
        .clean = .{
            .target = target_dir,
            .dry_run = parsed.hasFlag(hive.cli.CommonFlag.dry_run.flagName()),
            .include_out = parsed.hasFlag(hive.cli.CleanFlag.include_out.flagName()),
            .include_zig_pkg = parsed.hasFlag(hive.cli.CleanFlag.include_zig_pkg.flagName()),
            .snapshots = parsed.hasFlag(hive.cli.CleanFlag.snapshots.flagName()),
            .repo_dir = parsed.getValue(hive.cli.CleanFlag.repo_dir.flagName()) orelse (global_opts.artifact_repository_dir orelse ""),
            .workers = global_opts.parallel,
        },
        .init = .{
            .project_name = if (parsed.positionals.items.len > 0) parsed.positionals.items[0] else "",
            .template = parsed.getValue(hive.cli.InitFlag.template.flagName()) orelse "",
            .dir = parsed.getValue(hive.cli.InitFlag.dir.flagName()) orelse "",
            .version = parsed.getValue(hive.cli.InitFlag.version.flagName()) orelse hive.constants.Defaults.initial_version,
            .vars_packed = packed_vars.items,
            .refresh = parsed.hasFlag(hive.cli.InitFlag.refresh.flagName()),
            .force = parsed.getValue(hive.cli.InitFlag.force.flagName()) orelse "none",
            .templates_dir = global_opts.templates_dir orelse "",
            .workers = global_opts.parallel,
        },
        .add = .{
            .project_dir = global_opts.cwd orelse ".",
            .target = if (parsed.positionals.items.len > 0) parsed.positionals.items[0] else "",
            .version = parsed.getValue(hive.cli.AddFlag.version.flagName()) orelse "latest",
            .proto = parsed.getValue(hive.cli.AddFlag.proto.flagName()) orelse "artifact",
            .repo = parsed.getValue(hive.cli.AddFlag.repo.flagName()) orelse "",
            .as_alias = parsed.getValue(hive.cli.AddFlag.as.flagName()) orelse "",
            .zon = parsed.hasFlag(hive.cli.AddFlag.zon.flagName()),
            .artifact_repository_dir = global_opts.artifact_repository_dir orelse "",
            .workers = global_opts.parallel,
        },
        .fetch = .{
            .project_dir = target_dir,
            .offline = parsed.hasFlag(hive.cli.FetchFlag.offline.flagName()),
            .refresh = parsed.hasFlag(hive.cli.FetchFlag.refresh.flagName()),
            .target = parsed.getValue(hive.cli.FetchFlag.target.flagName()) orelse hive.constants.Defaults.native_target,
            .artifact_repository_dir = global_opts.artifact_repository_dir orelse "",
            .workers = global_opts.parallel,
        },
        .build = .{
            .project_dir = target_dir,
            .optimize = parsed.getValue(hive.cli.BuildFlag.optimize.flagName()) orelse "Debug",
            .target = parsed.getValue(hive.cli.BuildFlag.target.flagName()) orelse hive.constants.Defaults.native_target,
            .cpu = parsed.getValue(hive.cli.BuildFlag.cpu.flagName()) orelse hive.constants.Defaults.baseline_cpu,
            .linkage = parsed.getValue(hive.cli.BuildFlag.linkage.flagName()) orelse "both",
            .lto = parsed.hasFlag(hive.cli.BuildFlag.lto.flagName()),
            .bundle_compiler_rt = parsed.hasFlag(hive.cli.BuildFlag.bundle_compiler_rt.flagName()),
            .verify_abi = !parsed.hasFlag(hive.cli.BuildFlag.no_verify_abi.flagName()),
            .artifact_repository_dir = global_opts.artifact_repository_dir orelse "",
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
        .@"test" = .{
            .project_dir = target_dir,
            .tier = parsed.getValue(hive.cli.TestFlag.tier.flagName()) orelse "unit",
            .filter = parsed.getValue(hive.cli.TestFlag.filter.flagName()) orelse "",
            .fail_fast = parsed.hasFlag(hive.cli.TestFlag.fail_fast.flagName()),
            .optimize = parsed.getValue(hive.cli.TestFlag.optimize.flagName()) orelse "Debug",
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
        .install = .{
            .project_dir = target_dir,
            .snapshot = !parsed.hasFlag(hive.cli.InstallFlag.release.flagName()),
            .release = parsed.hasFlag(hive.cli.InstallFlag.release.flagName()),
            .force = parsed.hasFlag(hive.cli.InstallFlag.force.flagName()),
            .target = parsed.getValue(hive.cli.InstallFlag.target.flagName()) orelse hive.constants.Defaults.native_target,
            .artifact_repository_dir = global_opts.artifact_repository_dir orelse "",
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
        .docs = .{
            .project_dir = target_dir,
            .step = parsed.getValue(hive.cli.DocsFlag.step.flagName()) orelse hive.constants.Defaults.docs_step,
            .out_dir = parsed.getValue(hive.cli.DocsFlag.out_dir.flagName()) orelse "zig-out/docs",
            .package_bundle = parsed.hasFlag(hive.cli.DocsFlag.package.flagName()),
            .optimize = parsed.getValue(hive.cli.DocsFlag.optimize.flagName()) orelse "Debug",
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
        .release = .{
            .project_dir = target_dir,
            .version = parsed.getValue(hive.cli.ReleaseFlag.version.flagName()) orelse "",
            .bump = parsed.getValue(hive.cli.ReleaseFlag.bump.flagName()) orelse "",
            .sync_downstream = parsed.hasFlag(hive.cli.ReleaseFlag.sync_downstream.flagName()),
            .publish_after = parsed.hasFlag(hive.cli.ReleaseFlag.publish.flagName()),
            .dry_run = parsed.hasFlag(hive.cli.CommonFlag.dry_run.flagName()),
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
        .publish = .{
            .project_dir = target_dir,
            .repo = parsed.getValue(hive.cli.PublishFlag.repo.flagName()) orelse "",
            .snapshot = parsed.hasFlag(hive.cli.PublishFlag.snapshot.flagName()),
            .release = !parsed.hasFlag(hive.cli.PublishFlag.snapshot.flagName()),
            .version = parsed.getValue(hive.cli.PublishFlag.version.flagName()) orelse "",
            .target = parsed.getValue(hive.cli.PublishFlag.targets.flagName()) orelse hive.constants.Defaults.native_target,
            .force = parsed.hasFlag(hive.cli.CommonFlag.force.flagName()),
            .dry_run = parsed.hasFlag(hive.cli.CommonFlag.dry_run.flagName()),
            .ecc = parsed.hasFlag(hive.cli.PublishFlag.ecc.flagName()),
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
        .package = .{
            .project_dir = target_dir,
            .format = parsed.getValue(hive.cli.PackageFlag.format.flagName()) orelse "",
            .target = parsed.getValue(hive.cli.PackageFlag.target.flagName()) orelse hive.constants.Defaults.native_target,
            .strip = parsed.hasFlag(hive.cli.PackageFlag.strip.flagName()),
            .lto = parsed.hasFlag(hive.cli.PackageFlag.lto.flagName()),
            .sources = parsed.hasFlag(hive.cli.PackageFlag.sources.flagName()),
            .docs = parsed.hasFlag(hive.cli.PackageFlag.docs.flagName()),
            .packager = parsed.getValue(hive.cli.PackageFlag.packager.flagName()) orelse "",
            .profile = parsed.getValue(hive.cli.PackageFlag.profile.flagName()) orelse "",
            .verify_abi = !parsed.hasFlag(hive.cli.PackageFlag.no_verify_abi.flagName()),
            .artifact_repository_dir = global_opts.artifact_repository_dir orelse "",
            .module_filter = global_opts.module orelse "",
            .workers = global_opts.parallel,
        },
    };

    _ = hive.runtime.runPlan(allocator, plan, plan_opts) catch |err| {
        const msg = std.fmt.allocPrint(arena, "hive execution failed: {s}\n", .{@errorName(err)}) catch "hive execution failed\n";
        term.writeStderr(msg);
        return 1;
    };

    return 0;
}
