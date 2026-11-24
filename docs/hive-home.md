# `~/.hive/` — Default Local Artifact Repository & Templates

`~/.hive/` (overridable via `HIVE_HOME` or global `--artifact-repository-dir` / `--templates-dir`) is the **default local artifact repository and template cache** managed by `hive`. In the vast majority of setups it requires no manual configuration, while following the exact same coordinate layout as any remote **Artifact Repository** (`local`, `http`, `github`, `git`). It separates **compiled binary artifacts** (`packages/`) from **project archetypes** (`templates/`).

---

## 1. Directory Structure

```text
~/.hive/
├── packages/
│   └── <group>/                            # Publisher group (e.g. org.parabellum, default: local)
│       └── <artifact>/
│           ├── <version>/                  # Stable release (immutable per target)
│           │   ├── <artifact>-sources.tar.gz   # Target-agnostic source tarball for `build.zig.zon` (optional)
│           │   ├── <artifact>-docs.tar.gz      # Target-agnostic HTML autodoc bundle (optional)
│           │   ├── manifest.json               # Optional index for target-agnostic bundles (sha256, zon_hash)
│           │   └── <target>/                   # Canonical Zig target triple (e.g. x86_64-linux-gnu)
│           │       ├── <artifact>.so           # Dynamic shared library (.so / .dylib / .dll, optional)
│           │       ├── <artifact>.a            # Static archive (.a / .lib) for `hive package` (optional)
│           │       ├── <binary>                # Standalone executable (optional)
│           │       └── manifest.json           # Target metadata, build_config, dependencies, sha256 & artifact index
│           └── <version>-snapshot/             # Local dev snapshot (mutable, local-first)
│               ├── <artifact>-sources.tar.gz
│               ├── <artifact>-docs.tar.gz
│               └── <target>/
│                   ├── <artifact>.so
│                   ├── <artifact>.a
│                   └── manifest.json
└── templates/
    └── <template-name>/                    # Cached Git or local project archetype (`hive init`)
        ├── template.json                   # Variable declarations & defaults
        └── files/                          # Skeleton tree with {{var}} placeholders
├── credentials.json                        # Local repo tokens (`chmod 0600`, never committed)
└── trusted-keys/                           # Public keys for `.sig` artifact verification (optional)
```

---

## 2. `packages/` Rules & `manifest.json`

### Semantics
- **Publisher-scoped flat coordinates with target isolation**: No artificial type subdirectories (`drivers/`, `extensions/`, `engines/`). Every artifact lives uniformly at `~/.hive/packages/<group>/<artifact>/<version>[-snapshot]/<target>/` (with `<group>` defaulting to `local` when omitted in `hive.json`), where `<target>` is the resolved canonical Zig target triple (e.g. `x86_64-linux-gnu`, `aarch64-macos`, `x86_64-windows-gnu`).
- **Standard filenames per target**: Inside `<target>/`, binaries keep their standard platform names (`lib<name>.so`/`.dylib`/`.dll`, `lib<name>.a`/`.lib`, `<binary>`), allowing linkers and `dlopen` to consume `<target>/` directly without renaming.
- **Target-agnostic bundles**: `-sources.tar.gz` and `-docs.tar.gz` live at the `<version>[-snapshot]/` root so they are not duplicated across architectures.
- **Dual artifacts**: A single `<target>/` directory may contain both `.so` (for dynamic loading) and `.a` (for monolithic static linking in `hive package`), plus binaries if applicable.
- **Immutability (per target)**:
  - `<version>/<target>/` (without `-snapshot`) is **immutable**. `hive install --release` refuses to overwrite an existing `<target>` unless `--force` is passed, while allowing additional targets (e.g. `aarch64-linux-gnu`) to be added to the same `<version>/`. `hive clean --snapshots` never touches it.
  - `<version>-snapshot` is **mutable and local-first** (overwritable by `hive install`; remote snapshot pre-releases published via `hive publish --snapshot` are only fetched by `hive fetch` when missing locally or with `--refresh`).
- **Atomic writes & permissions**: Files are copied to `*.tmp`, `chmod`'d (`0755` for `.so`/executables, `0644` for `.a`/`manifest.json`), and atomically renamed into place.

### `manifest.json` Schema

```json
{
  "group": "org.parabellum",
  "name": "libgit",
  "version": "1.0.0",
  "target": "x86_64-linux-gnu",
  "installed_at": "2026-11-24T13:00:00Z",
  "build_config": {
    "zig_version": "0.17.1",
    "optimize": "ReleaseFast",
    "cpu": "baseline",
    "lto": false,
    "bundle_compiler_rt": false,
    "config_hash": "ffebb1234b21765c000b9b69bfe1aaf26612084e530b0adbf5b7690c0c7f1c0d"
  },
  "dependencies": [
    { "name": "org.parabellum:core", "version": "1.0.0" }
  ],
  "artifacts": [
    {
      "file": "libgit.so",
      "kind": "dynamic",
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "size_bytes": 184320
    },
    {
      "file": "libgit.a",
      "kind": "static",
      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      "size_bytes": 245760
    },
    {
      "file": "libgit-sources.tar.gz",
      "kind": "sources",
      "sha256": "4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a",
      "zon_hash": "libgit-1.0.0-46CU-l70AwDuJMyGFHH83-NUVjMx9fCVkR0PsEXHyiVK",
      "size_bytes": 49152
    }
  ]
}
```

---

## 3. `templates/` Rules & `template.json`

### Semantics
- Populated automatically when `hive init <name> --template <git-url>` clones a template repository via [libgit](libgit.md) (supporting `https://`, `ssh://`, `git@`, and `git+ssh://`).
- Once cached in `~/.hive/templates/<template-name>/`, subsequent runs can reference it offline by short name (`--template <template-name>`), or update it with `--refresh`.
- Local path templates (`--template ./my-template`) are used directly without copying into `~/.hive/templates/`.

### `template.json` Schema

```json
{
  "name": "zig-plugin",
  "version": "1.0.0",
  "description": "Minimal starter template",
  "variables": {
    "project_name": { "required": true },
    "version": { "default": "0.1.0" },
    "author": { "default": "" }
  }
}
```

---

## 4. `credentials.json` & `trusted-keys/`

- **`~/.hive/credentials.json`** (`0600` permissions, refused if group/world-readable): stores per-repository HTTP/GitHub tokens for local developer workflows when environment variables (`GITHUB_TOKEN`, `HIVE_HTTP_TOKEN`, `auth_env`) are not set.
- **`~/.hive/trusted-keys/`**: stores public keys (e.g. Ed25519 / Minisign / Cosign) used by `hive fetch` to verify optional `.sig` signatures on `manifest.json` / `SHA256SUMS.txt`.
