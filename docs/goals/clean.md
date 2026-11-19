# Goal: `clean`

## 1. Purpose

The `clean` goal removes Zig build caches and (optionally) compiled output directories across a single repository or an entire multi-repository workspace, reclaiming disk space and guaranteeing a fresh build state.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory / workspace root | Scope to clean. |
| `--dry-run` (`-n`) | `bool` | `false` | Report directories that would be deleted and total reclaimable disk space without deleting anything. |
| `--include-out` | `bool` | `false` | Also delete `zig-out/` directories (compiled `.so` libraries and binaries). |
| `--include-zig-pkg` | `bool` | `false` | Also delete nested `.zig-cache/` directories inside `zig-pkg/` vendor folders. |
| `--snapshots` | `bool` | `false` | Also purge `*-snapshot` directories inside `~/.hive/packages/`. Never touches stable release versions. |

---

## 3. Execution Logic

1. **Resolve Canonical Root**:
   - Resolve `target` to an absolute canonical path (`realpath`).
   - **Safety Guard**: Abort immediately with a non-zero exit code if the resolved root is `/`, `$HOME`, `/tmp`, `/usr`, or any directory that does not contain a `build.zig` or workspace descriptor.
2. **Discover Target Directories**:
   - Walk the canonical root (pruning matched directories so nested caches are not double-counted).
   - Always match: `.zig-cache`, `zig-cache`.
   - If `--include-out`: also match `zig-out`.
   - If `--include-zig-pkg`: descend into `zig-pkg/` for nested `.zig-cache` directories; otherwise skip `zig-pkg/` or prune at first match.
   - If `--snapshots`: scan `~/.hive/packages/*/*-snapshot` and append matching directories.
3. **Measure Disk Usage**:
   - For each discovered directory, compute its disk usage in bytes (`du -sb` / recursive stat) before deletion.
   - Accumulate `total_bytes`.
4. **Execute or Simulate**:
   - If `--dry-run`: emit structured log/output listing `[DRY-RUN] <human-size> -> <path>` for each directory.
   - Otherwise: recursively remove each directory (`rm -rf` / `std.fs.deleteTreeAbsolute`) and emit `[DELETED] <human-size> -> <path>`.
5. **Summary Output**:
   - Emit count of directories processed and total space freed (or reclaimable in dry-run mode) in human-readable IEC units (`MiB`, `GiB`).

---

## 4. Failure Modes & Invariants

- **Never deletes source files or `.git` directories**: Only exact directory name matches (`.zig-cache`, `zig-cache`, `zig-out`) or explicit `*-snapshot` package directories are eligible.
- **Never deletes stable artifacts**: `~/.hive/packages/<name>/<version>/` (without `-snapshot`) is strictly off-limits to `clean`.
- **Idempotent**: Running `clean` on an already clean workspace succeeds with exit code `0` and reports `0 directories cleaned`.
