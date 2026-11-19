# Goal: `add`

## 1. Purpose

The `add` goal adds a dependency to the current project — either as a **Zig source dependency** in `build.zig.zon` (with its canonical Zig BLAKE3 multihash `.hash` computed automatically) or as a **compiled artifact dependency** in `hive.json` (`.so` / `.a` resolved from an Artifact Repository).

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `string` (package name or URL) | Required | Dependency name or URL to add. |
| `--version` (`-v`) | `string` | `latest` | Requested version (e.g., `1.0.0`, `1.0.0-snapshot`) when resolving from an Artifact Repository. |
| `--proto` | `artifact \| git+https \| git+ssh \| http` | `artifact` | Transport/resolution protocol: `artifact` (default, resolves from `hive.json` repositories), `git+https`, `git+ssh`, or `http`. |
| `--repo` (`-r`) | `string` | Auto | Specific repository name from `hive.json` to resolve from. |
| `--as` | `string` | Inferred package name | Alias key used inside `build.zig.zon` or `hive.json`. |
| `--zon` | `bool` | `false` | Force adding as a `build.zig.zon` source dependency (automatically enabled for `git+*` or when the artifact contains `-sources.tar.gz`). |
| `-x fetch` | `flag` | `false` | Skip the automatic post-`add` `fetch` step (only update `hive.json` / `build.zig.zon`). |

---

## 3. Execution Logic

1. **Git Source Dependencies (`--proto git+https` / `git+ssh`)**:
   - **`git+https` / `https`**: invoke `zig fetch --save[=<as>] <url>` directly to compute the Zig BLAKE3 package hash and update `build.zig.zon`.
   - **`git+ssh` / `git@`** (private repositories): clone into a temporary cache directory via [libgit](../docs/libgit.md), compute the Zig `.hash` via `zig fetch` against the local checkout, and update `build.zig.zon` (validated via `std.zon`) with the original `git+ssh://...` `.url` and `.hash`.
2. **Artifact Repository Dependencies (`--proto artifact` / `http`)**:
   - Query configured Artifact Repositories (`~/.hive/packages/` first, then `hive.json` `repositories`).
   - Read `manifest.json` and verify `sha256` integrity.
   - If the package provides `-sources.tar.gz` (and `--zon` is set or inferred): write/update the dependency entry in `build.zig.zon` using its `zon_hash` (or `zig fetch` on the tarball).
   - If the package provides `.so` / `.a` binary artifacts: record `<name>: { "version": "<ver>", "repo": "<repo>" }` in `hive.json` `dependencies`.
3. **Automatic `fetch` Chaining**:
   - Unless `-x fetch` is passed, `hive add` chains `hive/fetch` immediately after updating `hive.json` / `build.zig.zon` so the new dependency's artifacts (`.so`, `.a`, `-sources.tar.gz`, `-docs.tar.gz`) are hydrated into `~/.hive/packages/` without duplicating download logic.
4. **Summary Output**:
   - Print whether `build.zig.zon` and/or `hive.json` was updated, along with the resolved version and hash.
