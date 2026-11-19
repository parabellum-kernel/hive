const sdk = @import("parabellum_sdk");
const container = @import("container.zig");

pub const HiveContext = container.HiveContext;
pub const HiveContainer = container.HiveContainer;

pub const pipeline_clean = @import("pipeline/clean/mod.zig");
pub const pipeline_init = @import("pipeline/init/mod.zig");
pub const pipeline_fetch = @import("pipeline/fetch/mod.zig");
pub const pipeline_build = @import("pipeline/build/mod.zig");
pub const pipeline_test = @import("pipeline/test/mod.zig");
pub const pipeline_add = @import("pipeline/add/mod.zig");
pub const pipeline_install = @import("pipeline/install/mod.zig");
pub const pipeline_docs = @import("pipeline/docs/mod.zig");
pub const pipeline_release = @import("pipeline/release/mod.zig");
pub const pipeline_publish = @import("pipeline/publish/mod.zig");
pub const pipeline_package = @import("pipeline/package/mod.zig");

pub const tasks = [_]sdk.abi.task.TaskDescriptor_ABI{
    HiveContainer.defineTaskService(pipeline_clean.CleanDiscoverRootsService, .{ .name = "clean_roots" }),
    HiveContainer.defineTaskService(pipeline_clean.CleanScanRootService, .{ .name = "clean_scan", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_clean.CleanExecuteService, .{ .name = "clean_execute", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_clean.CleanSummarizeService, .{ .name = "clean_summarize" }),
    HiveContainer.defineTaskService(pipeline_init.InitResolveTemplateService, .{ .name = "init_resolve" }),
    HiveContainer.defineTaskService(pipeline_init.InitWipeEntryService, .{ .name = "init_wipe_entry", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_init.InitDiscoverFilesService, .{ .name = "init_discover_files" }),
    HiveContainer.defineTaskService(pipeline_init.InitRenderFileService, .{ .name = "init_render", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_init.InitSummarizeService, .{ .name = "init_summarize" }),
    HiveContainer.defineTaskService(pipeline_fetch.FetchResolveService, .{ .name = "fetch_resolve" }),
    HiveContainer.defineTaskService(pipeline_fetch.FetchPrepareService, .{ .name = "fetch_prepare", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_fetch.FetchTransferService, .{ .name = "fetch_transfer", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_fetch.FetchSummarizeService, .{ .name = "fetch_summarize" }),
    HiveContainer.defineTaskService(pipeline_build.BuildDiscoverModulesService, .{ .name = "build_discover" }),
    HiveContainer.defineTaskService(pipeline_build.BuildCompileService, .{ .name = "build_compile", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_build.BuildVerifyArtifactService, .{ .name = "build_verify", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_build.BuildSummarizeService, .{ .name = "build_summarize" }),
    HiveContainer.defineTaskService(pipeline_test.TestDiscoverModulesService, .{ .name = "test_discover" }),
    HiveContainer.defineTaskService(pipeline_test.TestPlanModuleService, .{ .name = "test_plan", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_test.TestExecuteService, .{ .name = "test_execute", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_test.TestSummarizeService, .{ .name = "test_summarize" }),
    HiveContainer.defineTaskService(pipeline_add.AddResolveService, .{ .name = "add_resolve" }),
    HiveContainer.defineTaskService(pipeline_add.AddApplyService, .{ .name = "add_apply" }),
    HiveContainer.defineTaskService(pipeline_install.InstallDiscoverService, .{ .name = "install_discover" }),
    HiveContainer.defineTaskService(pipeline_install.InstallPrepareModuleService, .{ .name = "install_prepare", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_install.InstallScanDirService, .{ .name = "install_scan_dir", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_install.InstallClassifyArtifactService, .{ .name = "install_classify", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_install.InstallCopyArtifactService, .{ .name = "install_copy", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_install.InstallWriteManifestService, .{ .name = "install_manifest" }),
    HiveContainer.defineTaskService(pipeline_docs.DocsDiscoverService, .{ .name = "docs_discover" }),
    HiveContainer.defineTaskService(pipeline_docs.DocsGenerateService, .{ .name = "docs_generate", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_docs.DocsArchiveService, .{ .name = "docs_archive", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_docs.DocsSummarizeService, .{ .name = "docs_summarize" }),
    HiveContainer.defineTaskService(pipeline_release.ReleaseDiscoverService, .{ .name = "release_discover" }),
    HiveContainer.defineTaskService(pipeline_release.ReleasePreflightService, .{ .name = "release_preflight", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_release.ReleaseExecuteService, .{ .name = "release_execute", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_release.ReleaseSummarizeService, .{ .name = "release_summarize" }),
    HiveContainer.defineTaskService(pipeline_publish.PublishDiscoverService, .{ .name = "publish_discover" }),
    HiveContainer.defineTaskService(pipeline_publish.PublishPrepareService, .{ .name = "publish_prepare", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_publish.PublishUploadService, .{ .name = "publish_upload", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_publish.PublishSummarizeService, .{ .name = "publish_summarize" }),
    HiveContainer.defineTaskService(pipeline_package.PackageDiscoverService, .{ .name = "package_discover" }),
    HiveContainer.defineTaskService(pipeline_package.PackageResolveProfileService, .{ .name = "package_resolve", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_package.PackageAssembleService, .{ .name = "package_assemble", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_package.PackagePostProcessService, .{ .name = "package_postprocess", .lift = .elemental }),
    HiveContainer.defineTaskService(pipeline_package.PackageWriteManifestService, .{ .name = "package_manifest" }),
};

pub const manifest: sdk.abi.task.ModuleManifest_ABI = .{
    .abi_version = sdk.abi.task.ABI_VERSION,
    .module_name = "hive",
    .module_version = .{ .major = 0, .minor = 1, .patch = 0 },
    .tasks_ptr = &tasks,
    .tasks_len = tasks.len,
};
