# `hive` — Native Artifact & Workspace Build Tool

## 1. Why `hive` Exists

Traditional Zig (and systems-language) tooling assumes that the end deliverable of an application is a **single monolithic binary** built from a single repo. Modern modular ecosystems (like Parabellum, where each app is a collaborative hive of plugins, libs, drivers, and extensions running on a deterministic engine) need both:

- **Dynamic runtime composition**: independent shared libraries (`.so` / `.dylib` / `.dll`) loaded at runtime by the engine.
- **Static monolithic assembly**: linking the engine + plugins + drivers + extensions + libs (`.a` static archives) into a single self-contained deliverable binary or monolithic `.so` via `hive package`.

Because `zig build` alone only compiles a single repository into `zig-out/`, `hive` standardizes the full Maven-style artifact lifecycle (`clean`, `build`, `test`, `package`, `install`, `publish`, `fetch`) around a **flat local & remote artifact repository** (`~/.hive/packages/`), while staying 100% aligned with Zig's native build system.

---

## 2. Closed Monolith on the Microkernel

`hive` is itself a **closed, monolithic application built on top of the Parabellum microkernel**:
- The microkernel (`parabellum`) is embedded directly inside the `hive` binary, with its task catalog (`clean`, `build`, `test`, `package`, `install`, `publish`, `fetch`) registered statically in-process and pipelines constructed in pure Zig (`PipelineAST`).
- **Stability first**: `hive` does **not** load arbitrary userspace plugins at runtime. Customization is strictly declarative via `hive.json` and CLI flags.

---

## 3. Artifact Repository Model & Templates (`~/.hive/`)

`hive` treats both local and remote stores uniformly under a single **Artifact Repository** abstraction. By default, `~/.hive/packages/` acts as the **default local Artifact Repository** (and `~/.hive/templates/` as the local archetype cache) — requiring no configuration in typical setups, while using the exact same flat coordinate layout as remote repositories (`http`, `github`, `git`):

```text
~/.hive/
├── packages/
│   └── <artifact-name>/
│       ├── <version>/                      # Stable release (immutable per target)
│       │   ├── <artifact>-sources.tar.gz   # Target-agnostic source tarball (optional)
│       │   ├── <artifact>-docs.tar.gz      # Target-agnostic autodoc bundle (optional)
│       │   └── <target>/                   # Canonical Zig target triple (e.g. x86_64-linux-gnu)
│       │       ├── lib<artifact>.so        # Dynamic runtime artifact
│       │       ├── lib<artifact>.a         # Static archive (.o bundle) for `hive package`
│       │       └── manifest.json           # Metadata (artifacts, sha256, target)
│       └── <version>-snapshot/             # Local development snapshot (overwritable)
│           └── <target>/
│               ├── lib<artifact>.so
│               ├── lib<artifact>.a
│               └── manifest.json
└── templates/
    └── <template-name>/                    # External Git/local project archetype (`hive init`)
        ├── template.json
        └── files/
```

### Key Principles
1. **Uniform Flat Coordinates**: Plugins, drivers, extensions, libs, and the engine all live under `~/.hive/packages/<name>/<version>[-snapshot]/<target>/`.
2. **Dual Representation (`.so` + `.a`)**: Each versioned coordinate can store both the dynamic `.so` (for runtime loading) and the static `.a` (for monolithic assembly via `hive package`), declared in `manifest.json`.
3. **Strict Separation of Workspace vs. Repository**:
   - `build` and `package` **never** write to `~/.hive/packages/`. They only produce outputs inside `<repo>/zig-out/`.
   - Only `install` (local) and `publish` (remote + optional local mirror) write to `~/.hive/packages/`.
4. **Snapshot vs. Stable Semantics**:
   - Local development installs target `<version>-snapshot` by default.
   - Stable `<version>` directories are immutable (reserved for `--release` installs or remote `fetch`).
5. **Source Dependencies Stay in `build.zig.zon`**:
   - `~/.hive/packages/` stores **compiled artifacts** (`.so`, `.a`, binaries).
   - Compile-time Zig source dependencies continue to be managed by `build.zig.zon` and Zig's global package cache.

---

## 4. Lifecycle Goals & Master Execution Graph

| Goal | Spec | Summary |
|---|---|---|
| `init` | [goals/init.md](goals/init.md) | Standalone. Scaffolds a new project from an external template (`~/.hive/templates/`, local path, or Git/SSH repo via [libgit](docs/libgit.md)). |
| `add` | [goals/add.md](goals/add.md) | Standalone. Adds a dependency to `build.zig.zon` (auto-computing Zig BLAKE3 hashes for `git+https`/`git+ssh`/source tarballs) or `hive.json`. |
| `clean` | [goals/clean.md](goals/clean.md) | Opt-in pre-phase. Removes `.zig-cache`, `zig-cache`, and optionally `zig-out` / `*-snapshot` entries with safety guards and dry-run reporting. |
| `fetch` | [goals/fetch.md](goals/fetch.md) | Resolves and downloads declared binary/archive dependencies into `~/.hive/packages/` using built-in providers (`local`, `github`, `http`, `git`). |
| `build` | [goals/build.md](goals/build.md) | Compiles Zig targets into `.a` (static archives) and/or `.so` / binaries inside `zig-out/`, and validates declared `abi` contracts from `hive.json`. |
| `test` | [goals/test.md](goals/test.md) | Executes unit and optional integration test suites (`zig build test`, `test-e2e`) and acts as the quality gate. |
| `docs` | [goals/docs.md](goals/docs.md) | Opt-in. Generates static HTML API documentation via Zig's native `autodoc` (`///`, `//!`) and optionally bundles `<name>-docs.tar.gz`. |
| `package` | [goals/package.md](goals/package.md) | Assembles `.a` / `.so` artifacts into a final deliverable (`--format bin\|so\|tar`) with optional hardening (`--strip`) and declarative packagers (`--packager` / `--profile`) in `zig-out/dist/`. |
| `install` | [goals/install.md](goals/install.md) | Publishes packaged artifacts (`.so`, `.a`, binaries, `manifest.json`) into the local repository (`~/.hive/packages/<name>/<version>[-snapshot]/`). |
| `publish` | [goals/publish.md](goals/publish.md) | Uploads packaged artifacts (stable or `--snapshot`) to a remote repository declared in `hive.json` without touching source Git history. |
| `release` | [goals/release.md](goals/release.md) | Opt-in source release orchestrator: bumps versions, creates Git tags via `libgit`, pushes to `origin`, and syncs downstream `build.zig.zon` hashes. |

### Master Linear Lifecycle Graph

`hive` separates goals into two categories and constructs the `PipelineAST` dynamically in Zig:

1. **Opt-in / Standalone goals** (only added to the graph when explicitly requested):
   - `init` (standalone scaffolding)
   - `add` (standalone dependency addition to `build.zig.zon` / `hive.json`)
   - `clean` (opt-in pre-phase)
   - `fetch` (opt-in dependency resolution)
   - `docs` (opt-in HTML `autodoc` generation)
   - `release` (opt-in source Git tag/bump/downstream sync)
2. **Core Linear Lifecycle Phases** (strictly ordered):
   ```text
   build ──▶ test ──▶ package ──▶ install ──▶ publish
   ```

When invoking any core phase, `hive` activates **only** phases `0 ..= target` (never phases after `target`), and never auto-triggers `init`, `clean`, `fetch`, or `release`:

- `hive` (no goal): prints version / usage; 0 steps executed.
- `hive init ...`: `[init]`
- `hive clean`: `[clean]`
- `hive fetch`: `[fetch]`
- `hive build`: `[build]`
- `hive test`: `[build → test]`
- `hive package`: `[build → test → package]`
- `hive install`: `[build → test → package → install]`
- `hive publish`: `[build → test → package → install → publish]`
- `hive release`: `[build → test → release]` (outside the linear chain; `--publish` additionally chains `package → install → publish`)
- **Multi-goal chaining**: `hive clean fetch install` → `[clean → fetch → build → test → package → install]`
- **Gradle-style exclusions (`-x` / `--exclude`, repeatable)**:
  - `hive install -x test` → `[build → package → install]`
  - `hive install -x test -x package` → `[build → install]`
  - `hive package -x build -x test` → `[package]`
  - `hive publish -x test` requires explicit `--force-untested`.

---

## 5. Single-Project & Multi-Module (Workspace) Scope

`hive` supports single-project execution out of the box and leaves a lightweight, forward-compatible design for multi-module workspaces (similar to Gradle subprojects / Maven reactor):

- **Single-project mode** (default): Invoked inside any directory containing `hive.json` and/or `build.zig` + `build.zig.zon`.
- **Multi-module / Workspace mode** (planned phase): Invoked from a root directory whose `hive.json` declares `"modules": [...]`.
  - Runs the requested lifecycle across modules in **topological dependency order**, leveraging the embedded microkernel's DAG scheduler to build independent branches in parallel.
  - Supports targeting specific modules (e.g., `hive :mod:install` or `hive install --module mod`) and propagating `-x <goal>` across the reactor.

---

## 6. Reference Specs

- [docs/global-flags.md](docs/global-flags.md) — Global CLI flags, shared multi-goal flags, and environment variables.
- [docs/hive-json.md](docs/hive-json.md) — `hive.json` project & workspace descriptor schema.
- [docs/hive-home.md](docs/hive-home.md) — `~/.hive/{packages,templates}` layout, `manifest.json`, and `template.json` schemas.
- [docs/libgit.md](docs/libgit.md) — `libgit` Git plumbing library specification.
