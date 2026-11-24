# Goal: `package`

## 1. Purpose

The `package` goal assembles compiled static archives (`.a` / `.o`) and/or shared libraries (`.so`) produced by `hive build` (and optionally resolved from `~/.hive/packages/`) into a **final, self-contained deliverable** inside `<repo>/zig-out/dist/`.

`package` **never** writes to `~/.hive/packages/` or remote repositories — that responsibility belongs strictly to `hive install` and `hive publish`.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace target to package. |
| `--format` | `bin \| so \| tar` | `so` (plugins) / `bin` (apps) | Output deliverable format: monolithic executable (`bin`), monolithic shared library (`so`), or compressed archive (`tar`). |
| `--target` | `string` (Zig target triple) | `native` | Cross-compilation target triple (overrides `profile.target`; determines output filename extensions and target-family linker flags). |
| `--strip` | `bool` | `false` | Strip debug symbols from the assembled binary or shared library. |
| `--lto` | `bool` | `false` | Require LTO bitcode across all collected `.a` manifests (automatically derived when all inputs were built with `hive build --lto`; fails fast on mixed LTO/native inputs). |
| `--sources` | `bool` | `false` | Also produce `<name>-sources.tar.gz` (respecting `.paths` from `build.zig.zon`) and record its `zon_hash` in `manifest.json`. |
| `--docs` | `bool` | `false` | Also bundle generated `autodoc` HTML (`zig-out/docs/`) into `<name>-docs.tar.gz` and record its `sha256` in `manifest.json`. |
| `--packager` | `string` | `null` | Name of an external post-processor/packager declared under `packaging.packagers` in `hive.json`. |
| `--profile` | `string` | `null` | Named packaging profile declared under `packaging.profiles` in `hive.json` (bundles `format`, `strip`, `lto`, and `packager`). |
| `--verify-abi` | `bool` | `true` | Validate exported ABI manifest symbols when `--format=so`. |
| `-x`, `--exclude` | `<goal>` (repeatable) | `[]` | Exclude specific upstream lifecycle phases (e.g. `-x test`, `-x build`). |

---

## 3. Declarative Configuration (`hive.json`)

`hive` remains a **closed, stable monolith** (no userspace plugins loaded into `hive`). Custom corporate or distribution steps (signing, commercial obfuscation, custom packagers) are declared in `hive.json` and invoked via `--packager <name>` or `--profile <name>`:

```json
{
  "packaging": {
    "entrypoint": "libapp.a",
    "link_libs": ["c", "pthread"],
    "packagers": {
      "corp-sign": {
        "mode": "sidecar",
        "outputs": ["{input}.sig"],
        "command": ["cosign", "sign-blob", "--output-signature", "{input}.sig", "{input}"]
      }
    },
    "profiles": {
      "release-corp": {
        "format": "bin",
        "target": "x86_64-linux-gnu",
        "strip": true,
        "packagers": ["corp-sign"]
      }
    }
  }
}
```

---

## 4. Execution Logic

1. **Resolve Profile & Options**:
   - Load `hive.json` if present (parsed with `std.json`). If `--profile <name>` is passed, apply its `format`, `strip`, `lto`, and `packager` defaults (explicit CLI flags override profile values).
2. **Lifecycle Goal Chaining (DAG)**:
   - `hive/package` itself is single-responsibility and does **not** compile or execute tests directly.
   - Instead, invoking `hive package` activates the core linear lifecycle up to `package`:
     - `build` → `test` → `package` (skipping any phase excluded via `-x <goal>`).
   - If any active upstream goal fails, the pipeline halts before `hive/package` runs.
3. **Assemble Deliverable (Post-Build Link / Bundle Stage)**:
   - `package` never re-invokes `zig build`; it operates strictly on already-compiled outputs from `zig-out/` and `~/.hive/packages/<group>/<artifact>/<version>/<target>/`.
   - Resolve the transitive dependency closure (honoring `dependency_overrides` in `hive.json` and failing fast on `DependencyVersionConflict`), validate `build_config` / `lto` compatibility across collected manifests, and collect `.a` (or `.lib`) archives from `zig-out/lib/` and resolved dependency directories.
   - **`--format bin`**: when more than one `.a` is present, require `packaging.entrypoint` in `hive.json` (single-archive builds auto-use that archive; if no `.a`s exist and `zig-out/bin/` already contains an executable, copy it directly) and link via `zig cc` (passing `-target <target>` for cross-compilation) into a single monolithic executable (`zig-out/dist/<name>` or `<name>.exe` on Windows), wrapping archives with target-family whole-archive flags:
     - **ELF (Linux/BSD)**: `-Wl,--whole-archive ... -Wl,--no-whole-archive`
     - **Mach-O (macOS)**: `-Wl,-force_load,<archive>` (per archive)
     - **COFF/PE (Windows)**: `-Wl,/WHOLEARCHIVE:<archive>` (per archive)
   - **`--format so`**: link via `zig cc -shared` with target-family whole-archive flags into a single monolithic shared library (`lib<name>.so`, `lib<name>.dylib`, or `<name>.dll`). When `abi` (`required_symbols` / `any_of_symbols`) is declared in `hive.json`, synthesize a link-time visibility script (`-Wl,--version-script=exports.map` on ELF, `-Wl,-exported_symbols_list,exports.txt` on Mach-O) so non-ABI symbols are hidden from `.dynsym`.
   - **`--format tar`**: bundle the compiled binary/libraries (`zig-out/bin/`, `zig-out/lib/`) into `zig-out/dist/<name>-<version>-<target>.tar.gz`.
4. **Hardening & Post-Processing**:
   - Apply `--strip` when requested.
   - If `--packager <name>` or `profile.packagers` is active, execute each configured command sequentially with `{input}` and `{output}` placeholders substituted:
     - `mode: "transform"` (default): updates the active deliverable path to the transformed `{output}` for downstream packagers and `manifest.json`.
     - `mode: "sidecar"`: preserves the active deliverable path and registers declared `outputs` as auxiliary `sidecar` artifacts in `manifest.json` and `SHA256SUMS.txt`.
5. **Verify & Emit Metadata**:
   - When `--format=so` and `--verify-abi=true`: validate the assembled `.so` against the `abi` contract declared in `hive.json` (if any).
   - Compute SHA-256 checksums (`SHA256SUMS.txt`) and write `zig-out/dist/manifest.json`.

---

## 5. Invariants

- **Workspace-only output**: `package` only writes under `<repo>/zig-out/dist/`. It never mutates `~/.hive/packages/`.
- **Clean repository artifacts**: `~/.hive/packages/` always stores clean, verifiable `.so` and `.a` artifacts; custom post-processing happens strictly in `package`.
