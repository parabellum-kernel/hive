# Goal: `release`

## 1. Purpose

The `release` goal manages **source-level Git releases**: it bumps versions in `hive.json` / `build.zig.zon`, cuts verified annotated Git tags (`v<version>`), pushes commits and tags to `origin` via [libgit](../docs/libgit.md), and synchronizes `build.zig.zon` dependency URLs and Zig package hashes across downstream repositories.

Unlike `publish` (which strictly uploads compiled/packaged artifacts to an artifact repository), `release` is an **opt-in source release orchestrator** (equivalent to `mvn release:prepare` / `release-please`). It can optionally invoke `publish` after tagging.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Repository or workspace to release. |
| `--version` | `SemVer` | Read from `hive.json` / `build.zig.zon` | Explicit release version (e.g., `2.1.0`). Must NOT contain `-snapshot`. |
| `--bump` | `patch \| minor \| major` | `null` | Automatically increment version in `hive.json` / `build.zig.zon` before tagging. |
| `--sync-downstream` | `bool` | `true` | Update downstream repos' `build.zig.zon` `.url` and `.hash` entries (via `zig fetch`) after releasing upstream libraries. |
| `--publish` | `bool` | `false` | Also run `hive publish` after tagging and pushing to upload binary/package assets. |
| `--dry-run` (`-n`) | `bool` | `false` | Validate git state, run build/test, and print every git tag and `build.zig.zon` update without committing or pushing. |
| `--force-untested` | `bool` | `false` | Dangerous override to bypass the mandatory `test` gate. |

---

## 3. Execution Logic

1. **Pre-Flight Git & Version Checks (via `libgit`)**:
   - Verify the repository has a clean working tree (`libgit.isClean`) unless `--dry-run`.
   - Verify the current branch is the configured release branch (default `main`) and is up to date with `origin`.
   - Verify that the release version is valid SemVer **without** `-snapshot` and that tag `v<version>` does not already exist locally or on `origin`.
   - Verify that `build.zig.zon` does **not** contain local `.path = "../..."` dependencies for any dependency not being released in the same workspace wave.
2. **Quality Gate**:
   - Run `build (ReleaseSafe) → test` (abort on any failure unless `--force-untested` is set).
3. **Version Bump & Commit (if `--bump` or `--version` changed metadata)**:
   - Update version in `hive.json` (via `std.json`) and/or `build.zig.zon` (parsed/validated via `std.zon` with targeted edits to preserve formatting).
   - Commit the version bump (`chore(release): v<version>`) via `libgit`.
4. **Tag & Push (via `libgit`)**:
   - Create annotated Git tag `v<version>`.
   - Push branch and tag to `origin` (`--follow-tags`).
5. **Downstream `build.zig.zon` Synchronization (`--sync-downstream`, workspace mode)**:
   - For upstream Zig source packages just released at `v<version>`:
     - Compute the canonical Zig package hash via `zig fetch`.
     - Rewrite every downstream repository's `build.zig.zon` entry from `.path = "../<dep>"` (or old `.url`/`.hash`) to the new `.url` and `.hash`.
     - Re-run `test` in each downstream repository before continuing the topological release wave.
6. **Optional Artifact Publish (`--publish`)**:
   - If `--publish` is passed, invoke `hive publish` for the newly tagged version.

---

## 4. Failure Modes & Recovery

- **No broken `.path` leaks**: `release` refuses to tag a repository whose `build.zig.zon` still points to a local filesystem `.path = "../..."`, guaranteeing every tagged release is reproducible.
- **Dry-run parity**: `--dry-run` executes all pre-flight checks, builds, and tests so release issues are caught before touching `origin`.
