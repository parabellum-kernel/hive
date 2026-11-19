# Goal: `docs`

## 1. Purpose

The `docs` goal generates static HTML API documentation from Zig's native doc-comments (`///` and `//!`) using Zig's built-in `autodoc` compiler support — requiring zero custom comment parsers.

Optionally, it can bundle the generated site into `<name>-docs.tar.gz` (analogous to Maven's `-javadoc.jar`) so documentation can be installed and published alongside `.so`, `.a`, and `-sources.tar.gz` in any Artifact Repository.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace repos to document. |
| `--step` | `string` | `docs` | Custom `build.zig` step name to invoke if present (falls back to `zig build-lib -femit-docs` when no `docs` step is defined). |
| `--out-dir` | `path` | `zig-out/docs` | Output directory for the generated static HTML documentation. |
| `--package` | `bool` | `false` | Bundle `<out-dir>` into `zig-out/dist/<name>-docs.tar.gz` for `install` / `publish`. |
| `--optimize` | `Debug \| ReleaseSafe` | `Debug` | Optimization mode passed to the Zig compiler. |

---

## 3. Execution Logic

1. **Detect `build.zig` `docs` Step**:
   - Inspect `zig build --help` (or `hive.json` `docs.step`) to check whether the project exposes a `docs` build step (using `getEmittedDocs()`).
2. **Generate Documentation (`autodoc`)**:
   - If a `docs` step exists: run `zig build <step> -Doptimize=<optimize>`.
   - Otherwise, resolve the primary root source file from `build.zig` / `hive.json` and invoke `zig build-lib -femit-docs=<out-dir>` (producing the standard Zig `autodoc` HTML bundle without custom comment parsing).
3. **Optional Archive (`--package`)**:
   - When `--package` is set (or when invoked via `hive package --docs`), compress `<out-dir>` into `zig-out/dist/<name>-docs.tar.gz` and record its `sha256` in `manifest.json`.
4. **Summary Output**:
   - Print the output path (`zig-out/docs/index.html` and optional tarball path).

---

## 4. Invariants

- **Workspace-only output**: `docs` only writes under `<repo>/zig-out/docs/` and `<repo>/zig-out/dist/`. It never mutates `~/.hive/packages/` directly (use `hive install` or `hive publish`).
- **Native Zig `autodoc`**: Relies strictly on Zig's compiler AST doc-comment extraction (`///`, `//!`).
