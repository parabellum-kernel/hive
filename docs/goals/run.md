# `hive run` — Generic Execution & External Runner Proposal

> **Status**: Draft / Design Proposal

## 1. Motivation & Design Principle

`hive` is a generic build and artifact repository tool (analogous to Maven/Gradle). Its core **must remain 100% decoupled** from any specific application runtime (e.g. `parabellum-engine`, `pipeline.yaml` semantics, drivers, or extensions).

At the same time, `hive` already resolves the project's dependency graph against `~/.hive/packages/` and produces local build outputs in `zig-out/`. Just like `exec-maven-plugin` or Gradle's `JavaExec` / `application` plugin, `hive run` provides a **generic execution primitive** that:

1. Works with **zero configuration** for standard Zig/C executable projects (`zig-out/bin/<name>`).
2. Supports **declarative external runners** (`~/.hive/runners/<name>.json` and/or `hive.json`) for plugin-based or runtime-hosted applications without hardcoding domain logic in `hive`.
3. Eliminates per-project OS-specific wrapper scripts (`run.sh`, `run.ps1`, `run.cmd`) while keeping dynamic iteration fast (no monolithic binary required during development).

---

## 2. Three-Tier Resolution Model

When `hive run [args...]` (or `hive run -- <runner_args...>`) is invoked:

### Tier 1 — Zero-Config Standard Zig/C Project (no `run` block in `hive.json`)
- Chains `build` first (unless `-x build` is passed).
- Locates the project's executable in `zig-out/bin/<name>` (or the single binary under `zig-out/bin/`).
- Resolves shared library dependencies (`.so` / `.dylib` / `.dll`) from `~/.hive/packages/` and `./zig-out/lib/`, injects them into `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` / `PATH`, and executes the binary with the forwarded CLI arguments.

### Tier 2 — Inline Command in `hive.json`
For Zig/C projects that need custom flags or a specific entrypoint:

```json
{
  "name": "my-app",
  "dependencies": {
    "my-lib": { "version": "1.0.0" }
  },
  "run": {
    "command": ["{project_bin}", "--config", "app.conf", "{args}"]
  }
}
```

### Tier 3 — Reusable External Runner (`~/.hive/runners/<name>.json`)
For ecosystems where multiple applications share the same external runtime (e.g. Parabellum apps), a runner descriptor lives outside the project in `~/.hive/runners/<name>.json`:

```json
{
  "build_first": true,
  "stage_libs": true,
  "stage_assets": true,
  "command": ["{pkg:parabellum-engine:bin}", "run", "{args}"],
  "env": {
    "PARABELLUM_PLUGIN_DIR": "{stage_lib_dir}",
    "PARABELLUM_SPECS_DIR": "{stage_assets_dir}"
  }
}
```

And the project's `hive.json` only references it declaratively:

```json
{
  "name": "vault",
  "version": "0.1.0",
  "dependencies": {
    "parabellum-engine": { "version": "0.2.0" },
    "driver-sqlite": { "version": "1.0.0" },
    "driver-yaml": { "version": "1.0.0" },
    "driver-file_store": { "version": "1.0.0" },
    "ext-inbound_http": { "version": "1.0.0" },
    "ext-inbound_fs": { "version": "1.0.0" },
    "ext-inbound_cli": { "version": "1.0.0" },
    "lib-gdrive-vfs": { "version": "0.1.0" },
    "parabellum-apis": { "version": "1.0.0" }
  },
  "run": {
    "runner": "parabellum",
    "args": ["configs/pipeline.yaml"]
  }
}
```

### CLI Usage Examples
- `hive run` — builds local module, resolves dependencies from `~/.hive/packages/`, stages libs/assets, and runs the configured command with default `args`.
- `hive run -x build` — skips `zig build` (useful when only editing config/YAML files).
- `hive run -- --serve --pipeline configs/pipeline.yaml` — overrides/passes explicit arguments to `{args}`.

---

## 3. Generic Placeholders

Following the same declarative pattern as `packaging.packagers` (`{input}`, `{output}`), `hive run` only expands domain-agnostic placeholders:

| Placeholder | Resolved Value |
|---|---|
| `{project_bin}` | Executable built by the current project in `zig-out/bin/` |
| `{project_lib_dir}` | `./zig-out/lib` of the current project |
| `{pkg:<name>:bin}` | Executable artifact of dependency `<name>` in `~/.hive/packages/<name>/<ver>/<target>/` |
| `{pkg:<name>:dir}` | Target/package directory of dependency `<name>` in `~/.hive/packages/` |
| `{stage_lib_dir}` | Cached staging directory (e.g. `.zig-cache/hive-run/lib/`) containing symlinks to all resolved `.so`/`.dylib`/`.dll` dependencies plus `zig-out/lib` |
| `{stage_assets_dir}` | Cached staging directory containing symlinks to non-binary asset files (e.g. `.yaml`, `.json` specs) from resolved dependencies |
| `{args}` | CLI arguments forwarded to `hive run` (falls back to `run.args` in `hive.json` if omitted) |
| `{cwd}` | Project working directory |

---

## 4. Shared Assets & Declarative API Specs

Because `hive` treats non-binary files (such as shared `api.*.yaml` autoclients) as regular versioned package contents, a shared specs package (e.g. `parabellum-apis`) can be installed/fetched into `~/.hive/packages/` and referenced via `{stage_assets_dir}` or `{pkg:<name>:dir}` in the runner's `env` without `hive` parsing or understanding YAML.

---

## 5. Lifecycle Integration

- `run` is an **opt-in / standalone** execution goal (not part of `package -> install -> publish`).
- By default, `hive run` chains `build -> run` when `build_first` is enabled (the default), and respects `-x build` to skip compilation.
