const std = @import("std");
const parabellum = @import("parabellum");
const platform = @import("parabellum_platform");
const otel = @import("ext_opentelemetry");
const trace_jsonl = @import("ext_trace_jsonl");
const constants = @import("constants.zig");
const catalog = @import("catalog.zig");
const cli = @import("cli.zig");

const ast = parabellum.ast;

pub const CleanOptions = struct {
    target: []const u8 = ".",
    dry_run: bool = false,
    include_out: bool = false,
    include_zig_pkg: bool = false,
    snapshots: bool = false,
    repo_dir: []const u8 = "",
    workers: ?usize = null,
};

pub const InitOptions = struct {
    project_name: []const u8 = "",
    template: []const u8 = "",
    dir: []const u8 = "",
    version: []const u8 = constants.Defaults.initial_version,
    vars_packed: []const u8 = "",
    refresh: bool = false,
    force: []const u8 = "none",
    templates_dir: []const u8 = "",
    workers: ?usize = null,
};

pub const FetchOptions = struct {
    project_dir: []const u8 = ".",
    offline: bool = false,
    refresh: bool = false,
    target: []const u8 = constants.Defaults.native_target,
    artifact_repository_dir: []const u8 = "",
    workers: ?usize = null,
};

pub const BuildOptions = struct {
    project_dir: []const u8 = ".",
    optimize: []const u8 = "Debug",
    target: []const u8 = constants.Defaults.native_target,
    cpu: []const u8 = constants.Defaults.baseline_cpu,
    linkage: []const u8 = "both",
    lto: bool = false,
    bundle_compiler_rt: bool = false,
    verify_abi: bool = true,
    artifact_repository_dir: []const u8 = "",
    module_filter: []const u8 = "",
    extra_args_packed: []const u8 = "",
    workers: ?usize = null,
};

pub const TestOptions = struct {
    project_dir: []const u8 = ".",
    tier: []const u8 = "unit",
    filter: []const u8 = "",
    fail_fast: bool = false,
    optimize: []const u8 = "Debug",
    module_filter: []const u8 = "",
    extra_args_packed: []const u8 = "",
    workers: ?usize = null,
};

pub const AddOptions = struct {
    project_dir: []const u8 = ".",
    target: []const u8 = "",
    version: []const u8 = "latest",
    proto: []const u8 = "artifact",
    repo: []const u8 = "",
    as_alias: []const u8 = "",
    zon: bool = false,
    artifact_repository_dir: []const u8 = "",
    workers: ?usize = null,
};

pub const InstallOptions = struct {
    project_dir: []const u8 = ".",
    snapshot: bool = true,
    release: bool = false,
    force: bool = false,
    target: []const u8 = constants.Defaults.native_target,
    artifact_repository_dir: []const u8 = "",
    module_filter: []const u8 = "",
    workers: ?usize = null,
};

pub const DocsOptions = struct {
    project_dir: []const u8 = ".",
    step: []const u8 = constants.Defaults.docs_step,
    out_dir: []const u8 = "zig-out/docs",
    package_bundle: bool = false,
    optimize: []const u8 = "Debug",
    module_filter: []const u8 = "",
    workers: ?usize = null,
};

pub const ReleaseOptions = struct {
    project_dir: []const u8 = ".",
    version: []const u8 = "",
    bump: []const u8 = "",
    sync_downstream: bool = true,
    publish_after: bool = false,
    dry_run: bool = false,
    module_filter: []const u8 = "",
    workers: ?usize = null,
};

pub const PublishOptions = struct {
    project_dir: []const u8 = ".",
    repo: []const u8 = "",
    snapshot: bool = false,
    release: bool = true,
    version: []const u8 = "",
    target: []const u8 = constants.Defaults.native_target,
    force: bool = false,
    dry_run: bool = false,
    ecc: bool = false,
    module_filter: []const u8 = "",
    workers: ?usize = null,
};

pub const PackageOptions = struct {
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
    workers: ?usize = null,
};

pub const PlanOptions = struct {
    clean: CleanOptions = .{},
    init: InitOptions = .{},
    add: AddOptions = .{},
    fetch: FetchOptions = .{},
    build: BuildOptions = .{},
    @"test": TestOptions = .{},
    package: PackageOptions = .{},
    install: InstallOptions = .{},
    docs: DocsOptions = .{},
    release: ReleaseOptions = .{},
    publish: PublishOptions = .{},
    workers: ?usize = null,
};

/// Resolves DAG worker count: CLI `--parallel` / `-j` > `HIVE_WORKERS` env var > CPU count.
pub fn resolveWorkers(alloc: std.mem.Allocator, env: platform.PlatformEnv, cli_workers: ?usize) usize {
    if (cli_workers) |w| return @max(w, 1);
    if (env.getEnv(alloc, constants.EnvVar.HIVE_WORKERS.key())) |raw| {
        defer alloc.free(raw);
        if (std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n\t"), 10)) |w| {
            return @max(w, 1);
        } else |_| {}
    }
    const cpus = std.Thread.getCpuCount() catch 1;
    return @max(cpus, 1);
}

pub fn runPipeline(allocator: std.mem.Allocator, pipeline_ast: *const ast.PipelineAST) !parabellum.ExecutionSummary {
    var kernel_ctx = try parabellum.KernelContext.init(allocator);
    defer kernel_ctx.deinit();

    const otel_ext = try parabellum.kernel.AbiExtensionBridge.initExtension(allocator, &otel.manifest);
    try kernel_ctx.use(otel_ext);

    const trace_ext = try parabellum.kernel.AbiExtensionBridge.initExtension(allocator, &trace_jsonl.manifest);
    try kernel_ctx.use(trace_ext);

    var registry = parabellum.ModuleRegistry.init(allocator);
    defer registry.deinit();
    try registry.registerStaticModule("hive", &catalog.manifest);

    var repos = parabellum.RepositoryRegistry.init(allocator);
    defer repos.deinit();

    var engine = parabellum.PipelineEngine.init(allocator, pipeline_ast.*, &registry, &repos);
    defer engine.deinit();
    engine.withKernel(&kernel_ctx);

    const EmptyInput = struct {};
    const empty: EmptyInput = .{};
    return try engine.run(parabellum.PayloadHandle.fromScalar(EmptyInput, &empty));
}

fn makeLinearSubPipeline(
    arena: std.mem.Allocator,
    name: []const u8,
    task_names: []const []const u8,
    params: []const ast.KeyValueParam,
) !ast.PipelineDecl {
    const owned_params = try arena.dupe(ast.KeyValueParam, params);
    const steps = try arena.alloc(ast.StepNode, task_names.len);
    for (task_names, 0..) |tname, idx| {
        if (idx == 0) {
            steps[idx] = .{
                .task = .{
                    .id = tname,
                    .module = "hive",
                    .task = tname,
                    .static_params = owned_params,
                },
            };
        } else {
            const prev = task_names[idx - 1];
            const param_key = if (idx == task_names.len - 1) "results" else "primary";
            const inputs = try arena.alloc(ast.InputBindingSpec, 1);
            inputs[0] = .{ .param_name = param_key, .expr = ast.InboundStreamExpr.direct(prev) };
            const after = try arena.alloc([]const u8, 1);
            after[0] = prev;
            steps[idx] = .{
                .task = .{
                    .id = tname,
                    .module = "hive",
                    .task = tname,
                    .inputs = inputs,
                    .after = after,
                },
            };
        }
    }
    return .{
        .name = name,
        .steps = steps,
    };
}

fn buildGoalPipelineDecl(arena: std.mem.Allocator, goal: cli.Goal, opts: PlanOptions) !?ast.PipelineDecl {
    return switch (goal) {
        .config => null,
        .clean => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "clean_roots", "clean_scan", "clean_execute", "clean_summarize" },
            &.{
                .{ .key = "target", .value = opts.clean.target },
                .{ .key = "dry_run", .value = if (opts.clean.dry_run) "true" else "false" },
                .{ .key = "include_out", .value = if (opts.clean.include_out) "true" else "false" },
                .{ .key = "include_zig_pkg", .value = if (opts.clean.include_zig_pkg) "true" else "false" },
                .{ .key = "snapshots", .value = if (opts.clean.snapshots) "true" else "false" },
                .{ .key = "repo_dir", .value = opts.clean.repo_dir },
            },
        ),
        .init => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "init_resolve", "init_wipe_entry", "init_discover_files", "init_render", "init_summarize" },
            &.{
                .{ .key = "project_name", .value = opts.init.project_name },
                .{ .key = "template", .value = opts.init.template },
                .{ .key = "dir", .value = opts.init.dir },
                .{ .key = "version", .value = opts.init.version },
                .{ .key = "vars_packed", .value = opts.init.vars_packed },
                .{ .key = "refresh", .value = if (opts.init.refresh) "true" else "false" },
                .{ .key = "force", .value = opts.init.force },
                .{ .key = "templates_dir", .value = opts.init.templates_dir },
            },
        ),
        .add => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "add_resolve", "add_apply" },
            &.{
                .{ .key = "project_dir", .value = opts.add.project_dir },
                .{ .key = "target", .value = opts.add.target },
                .{ .key = "version", .value = opts.add.version },
                .{ .key = "proto", .value = opts.add.proto },
                .{ .key = "repo", .value = opts.add.repo },
                .{ .key = "as_alias", .value = opts.add.as_alias },
                .{ .key = "zon", .value = if (opts.add.zon) "true" else "false" },
                .{ .key = "artifact_repository_dir", .value = opts.add.artifact_repository_dir },
            },
        ),
        .fetch => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "fetch_resolve", "fetch_prepare", "fetch_transfer", "fetch_summarize" },
            &.{
                .{ .key = "project_dir", .value = opts.fetch.project_dir },
                .{ .key = "offline", .value = if (opts.fetch.offline) "true" else "false" },
                .{ .key = "refresh", .value = if (opts.fetch.refresh) "true" else "false" },
                .{ .key = "target", .value = opts.fetch.target },
                .{ .key = "artifact_repository_dir", .value = opts.fetch.artifact_repository_dir },
            },
        ),
        .build => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "build_discover", "build_compile", "build_verify", "build_summarize" },
            &.{
                .{ .key = "project_dir", .value = opts.build.project_dir },
                .{ .key = "optimize", .value = opts.build.optimize },
                .{ .key = "target", .value = opts.build.target },
                .{ .key = "cpu", .value = opts.build.cpu },
                .{ .key = "linkage", .value = opts.build.linkage },
                .{ .key = "lto", .value = if (opts.build.lto) "true" else "false" },
                .{ .key = "bundle_compiler_rt", .value = if (opts.build.bundle_compiler_rt) "true" else "false" },
                .{ .key = "verify_abi", .value = if (opts.build.verify_abi) "true" else "false" },
                .{ .key = "artifact_repository_dir", .value = opts.build.artifact_repository_dir },
                .{ .key = "module_filter", .value = opts.build.module_filter },
                .{ .key = "extra_args_packed", .value = opts.build.extra_args_packed },
            },
        ),
        .@"test" => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "test_discover", "test_plan", "test_execute", "test_summarize" },
            &.{
                .{ .key = "project_dir", .value = opts.@"test".project_dir },
                .{ .key = "tier", .value = opts.@"test".tier },
                .{ .key = "filter", .value = opts.@"test".filter },
                .{ .key = "fail_fast", .value = if (opts.@"test".fail_fast) "true" else "false" },
                .{ .key = "optimize", .value = opts.@"test".optimize },
                .{ .key = "module_filter", .value = opts.@"test".module_filter },
                .{ .key = "extra_args_packed", .value = opts.@"test".extra_args_packed },
            },
        ),
        .install => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "install_discover", "install_prepare", "install_scan_dir", "install_classify", "install_copy", "install_manifest" },
            &.{
                .{ .key = "project_dir", .value = opts.install.project_dir },
                .{ .key = "snapshot", .value = if (opts.install.snapshot) "true" else "false" },
                .{ .key = "release", .value = if (opts.install.release) "true" else "false" },
                .{ .key = "force", .value = if (opts.install.force) "true" else "false" },
                .{ .key = "target", .value = opts.install.target },
                .{ .key = "artifact_repository_dir", .value = opts.install.artifact_repository_dir },
                .{ .key = "module_filter", .value = opts.install.module_filter },
            },
        ),
        .docs => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "docs_discover", "docs_generate", "docs_archive", "docs_summarize" },
            &.{
                .{ .key = "project_dir", .value = opts.docs.project_dir },
                .{ .key = "step", .value = opts.docs.step },
                .{ .key = "out_dir", .value = opts.docs.out_dir },
                .{ .key = "package_bundle", .value = if (opts.docs.package_bundle) "true" else "false" },
                .{ .key = "optimize", .value = opts.docs.optimize },
                .{ .key = "module_filter", .value = opts.docs.module_filter },
            },
        ),
        .release => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "release_discover", "release_preflight", "release_execute", "release_summarize" },
            &.{
                .{ .key = "project_dir", .value = opts.release.project_dir },
                .{ .key = "version", .value = opts.release.version },
                .{ .key = "bump", .value = opts.release.bump },
                .{ .key = "sync_downstream", .value = if (opts.release.sync_downstream) "true" else "false" },
                .{ .key = "publish_after", .value = if (opts.release.publish_after) "true" else "false" },
                .{ .key = "dry_run", .value = if (opts.release.dry_run) "true" else "false" },
                .{ .key = "module_filter", .value = opts.release.module_filter },
            },
        ),
        .publish => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "publish_discover", "publish_prepare", "publish_upload", "publish_summarize" },
            &.{
                .{ .key = "project_dir", .value = opts.publish.project_dir },
                .{ .key = "repo", .value = opts.publish.repo },
                .{ .key = "snapshot", .value = if (opts.publish.snapshot) "true" else "false" },
                .{ .key = "release", .value = if (opts.publish.release) "true" else "false" },
                .{ .key = "version", .value = opts.publish.version },
                .{ .key = "target", .value = opts.publish.target },
                .{ .key = "force", .value = if (opts.publish.force) "true" else "false" },
                .{ .key = "dry_run", .value = if (opts.publish.dry_run) "true" else "false" },
                .{ .key = "ecc", .value = if (opts.publish.ecc) "true" else "false" },
                .{ .key = "module_filter", .value = opts.publish.module_filter },
            },
        ),
        .package => try makeLinearSubPipeline(
            arena,
            goal.name(),
            &.{ "package_discover", "package_resolve", "package_assemble", "package_postprocess", "package_manifest" },
            &.{
                .{ .key = "project_dir", .value = opts.package.project_dir },
                .{ .key = "format", .value = opts.package.format },
                .{ .key = "strip", .value = if (opts.package.strip) "true" else "false" },
                .{ .key = "lto", .value = if (opts.package.lto) "true" else "false" },
                .{ .key = "sources", .value = if (opts.package.sources) "true" else "false" },
                .{ .key = "docs", .value = if (opts.package.docs) "true" else "false" },
                .{ .key = "packager", .value = opts.package.packager },
                .{ .key = "profile", .value = opts.package.profile },
                .{ .key = "verify_abi", .value = if (opts.package.verify_abi) "true" else "false" },
                .{ .key = "target", .value = opts.package.target },
                .{ .key = "artifact_repository_dir", .value = opts.package.artifact_repository_dir },
                .{ .key = "module_filter", .value = opts.package.module_filter },
            },
        ),
    };
}

/// Composes all planned goals into a single `PipelineAST` with a `main` pipeline
/// invoking each goal's sub-pipeline via `RouterStepSpec` under one unified `trace_id`.
pub fn runPlan(allocator: std.mem.Allocator, plan: []const cli.Goal, opts: PlanOptions) !parabellum.ExecutionSummary {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var pipelines: std.ArrayListUnmanaged(ast.PipelineDecl) = .empty;
    var main_steps: std.ArrayListUnmanaged(ast.StepNode) = .empty;

    // Reserve slot 0 for `main`
    try pipelines.append(arena, .{ .name = "main", .steps = &.{} });

    for (plan) |goal| {
        const sub_decl = (try buildGoalPipelineDecl(arena, goal, opts)) orelse return error.GoalNotImplemented;
        try pipelines.append(arena, sub_decl);

        const router_id = try std.fmt.allocPrint(arena, "goal_{s}", .{goal.name()});
        try main_steps.append(arena, .{
            .router = .{
                .id = router_id,
                .default_pipeline = goal.name(),
            },
        });
    }

    pipelines.items[0] = .{
        .name = "main",
        .steps = main_steps.items,
    };

    const worker_count = resolveWorkers(allocator, platform.env.nativeEnv(), opts.workers);

    const pipeline_ast = ast.PipelineAST{
        .runtime = .{
            .workers = worker_count,
            .scheduler = .dag,
            .routing = .directed,
            .retain_all = false,
        },
        .pipelines = pipelines.items,
        .entrypoint = "main",
    };

    return try runPipeline(allocator, &pipeline_ast);
}

pub fn runClean(allocator: std.mem.Allocator, opts: CleanOptions) !parabellum.ExecutionSummary {
    return try runPlan(allocator, &.{.clean}, .{ .clean = opts, .workers = opts.workers });
}

pub fn runInit(allocator: std.mem.Allocator, opts: InitOptions) !parabellum.ExecutionSummary {
    return try runPlan(allocator, &.{.init}, .{ .init = opts, .workers = opts.workers });
}

pub fn runFetch(allocator: std.mem.Allocator, opts: FetchOptions) !parabellum.ExecutionSummary {
    return try runPlan(allocator, &.{.fetch}, .{ .fetch = opts, .workers = opts.workers });
}

pub fn runBuild(allocator: std.mem.Allocator, opts: BuildOptions) !parabellum.ExecutionSummary {
    return try runPlan(allocator, &.{.build}, .{ .build = opts, .workers = opts.workers });
}

pub fn runTest(allocator: std.mem.Allocator, opts: TestOptions) !parabellum.ExecutionSummary {
    return try runPlan(allocator, &.{.@"test"}, .{ .@"test" = opts, .workers = opts.workers });
}
