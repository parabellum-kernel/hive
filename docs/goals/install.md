# Goal: `install`

## 1. Purpose

The `install` goal writes packaged artifacts (`.so` dynamic libraries, `.a` static archives, and/or executables + `manifest.json`) from a project's local `zig-out/` into the **default local Artifact Repository** (`~/.hive/packages/`, overridable via `--artifact-repository-dir` or `HIVE_HOME`), making them immediately consumable by other local projects and `hive package` assemblies.

Just like remote artifact repositories used by `publish` and `fetch`, `~/.hive/packages/` is a standard **Artifact Repository** following the exact same coordinate layout.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace repos to install. |
| `--snapshot` | `bool` | `true` | Install under `<version>-snapshot` (mutable local dev version). |
| `--release` | `bool` | `false` | Install under exact `<version>` (immutable stable version; fails if already exists unless `--force`). |
| `--force` | `bool` | `false` | Overwrite an existing stable `<version>` directory. |
| `-x`, `--exclude` | `<goal>` (repeatable) | `[]` | Exclude specific upstream lifecycle phases (e.g. `-x test`, `-x package`, `-x build`). |
| `--artifact-repository-dir` | `path` | `~/.hive/packages` | Override the local artifact repository root (useful for CI or isolated test environments). |

---

## 3. Target Repository Layout & Coordinates

Every package is installed into a flat, Maven-style coordinate path with **no artificial type subdirectories**:

```text
~/.hive/packages/
└── <name>/
    └── <version>[-snapshot]/
        ├── <artifact>-sources.tar.gz   # Target-agnostic source tarball (if `--sources` was packaged)
        ├── <artifact>-docs.tar.gz      # Target-agnostic HTML autodoc archive (if `--docs` was packaged)
        └── <target>/                   # Canonical Zig target triple (e.g. x86_64-linux-gnu)
            ├── <artifact>.so           # Dynamic runtime artifact (if produced)
            ├── <artifact>.a            # Static archive (.o bundle) for `hive package` (if produced)
            ├── <binary>                # Executable artifact (if produced)
            └── manifest.json           # Target metadata: name, version, target, artifacts[], sha256, installed_at
```

- **Coordinate resolution**: `<name>` and `<version>` are read from `hive.json` (falling back to `.name` and `.version` in `build.zig.zon`).

---

## 4. Execution Logic

1. **Master Linear Lifecycle Activation**:
   - `hive/install` itself is single-responsibility and does **not** compile, test, or package directly.
   - Invoking `hive install` activates the core linear lifecycle up to `install`:
     - `build` → `test` → `package` → `install` (skipping any phase excluded via `-x <goal>`).
   - If any active upstream phase fails, the pipeline halts before `hive/install` runs.
2. **Determine Coordinates**:
   - Read `name` and `version` from `hive.json` / `build.zig.zon`, and resolve the canonical Zig `<target>` triple (defaulting `native` to the host triple, e.g. `x86_64-linux-gnu`).
   - Compute `effective_version = "<version>-snapshot"` if `--snapshot` (and not `--release`), else `"<version>"`.
   - Compute destination directory: `<artifact-repository-dir>/<name>/<effective_version>/<target>/` (with target-agnostic `-sources.tar.gz` / `-docs.tar.gz` placed in `<artifact-repository-dir>/<name>/<effective_version>/`).
3. **Immutability Check**:
   - If installing a stable release (`--release`) and the destination `<target>` directory already exists and `--force` is `false`: abort with a clear error explaining that stable versions are immutable per target.
4. **Atomic Install & Security Permissions**:
   - Create destination directory chain.
   - For each produced artifact (`.so`, `.a`, binary), copy to `<dest>/<file>.tmp`, set safe permissions (`0755` for executables/shared libs, `0644` for static archives), and atomically rename to `<dest>/<file>`.
   - Write `<dest>/manifest.json` indexing all installed files for that target, their kinds (`dynamic`, `static`, `bin`), SHA-256 digests, target triple, and timestamp.
5. **Summary Output**:
   - Print installed coordinates (`<name>@<effective_version> (<target>) -> <dest>/`) and artifact list.

---

## 5. Consuming Installed Artifacts

- Exact stable coordinate (`"1.0.0"`) → resolves `~/.hive/packages/<name>/1.0.0/<target>/` (or downloads via `hive fetch` if missing).
- Snapshot coordinate (`"1.0.0-snapshot"`) → resolves `~/.hive/packages/<name>/1.0.0-snapshot/<target>/` (strictly local-first).
- `"latest"` → resolves the highest installed SemVer (preferring stable over snapshot unless snapshots are explicitly enabled).
