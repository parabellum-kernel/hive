# Architectural Review & Engineering Improvements: `hive` & `package` Goal

This document consolidates the structural flaws, linker edge cases, and architectural improvements identified across the `hive` workspace model and the `package` goal specification.

---

## 1. Repository & ABI Granularity (`~/.hive/packages/`)

### Issue: Insufficient Coordinate Resolution for Systems Artifacts
Currently, repository coordinates are keyed by `<artifact-name>/<version>[-snapshot]/<target>/`. Unlike JVM bytecode, compiled static archives (`.a`) and shared libraries (`.so` / `.dylib` / `.dll`) in Zig/C do not have a universal ABI across compiler versions or build configurations unless strictly constrained to C-ABI boundaries (`export fn`, `extern struct`).
- **Failure Mode:** Linking a `Debug` archive with a `ReleaseFast` archive, or mixing `.a` files compiled with different Zig versions, CPU feature flags (`-Dcpu`), or allocator conventions will either fail at link time or cause silent memory corruption at runtime.
- **Improvement:**
  - Introduce a **build configuration fingerprint** (hashing `zig_version`, `optimize_mode`, `cpu_model`, `abi_flags`, and `lto` state) into `manifest.json` and either nest artifacts under `<target>/<config-hash>/` or enforce strict compatibility validation during `fetch` and `package` before invoking the linker.

---

## 2. Transitive Dependency Mediation

### Issue: Undefined Conflict Resolution in Flat Layouts
In a flat artifact store (`~/.hive/packages/<name>/<version>/`), if `plugin-a` depends on `driver-x:1.0.0` and `plugin-b` depends on `driver-x:1.1.0`, static assembly (`hive package --format bin|so`) cannot link both versions into the same address space without duplicate symbol collisions.
- **Failure Mode:** Silent symbol shadowing or linker crashes during static assembly. Unlike Gradle's "highest version wins" heuristic, automatic version promotion in C/Zig is unsafe if struct layouts changed across minor versions.
- **Improvement:**
  - Enforce **fail-fast conflict detection** during `fetch` and `package` when multiple versions of the same artifact appear in the dependency graph.
  - Support explicit dependency overrides/pins in the root `hive.json` to force graph convergence intentionally.

---

## 3. Link-Time Optimization (`--lto`) Lifecycle Mismatch

### Issue: `--lto` Cannot Be Applied Retroactively in `package`
The `package` spec defines `--lto` as an assembly-time flag (`Enable link-time optimization when assembling the deliverable`). In LLVM/Zig, LTO requires upstream `.a` archives to be compiled as LLVM bitcode (`.bc`) during `hive build`, rather than standard native machine object files (ELF/Mach-O/COFF).
- **Failure Mode:** Passing `-flto` to `zig cc` during `package` over standard object archives silently skips cross-module optimization or fails due to bitcode version mismatches between the compiler that built a fetched dependency and the local toolchain.
- **Improvement:**
  - Move `--lto` to `hive build` and record `"lto": true|false` in `manifest.json`.
  - In `package`, either derive LTO automatically from the collected manifests or validate that every input `.a` has `"lto": true` before passing `-flto` to `zig cc`, failing fast on mixed bitcode/native inputs.

---

## 4. Static Symbol Collisions & `compiler-rt` Duplication

### Issue: `--whole-archive` Exposes Internal Runtime Symbols
Wrapping plugin/module archives in `-Wl,--whole-archive` (or `-force_load`) is necessary to preserve unreferenced `export fn` and `linksection` registrations. However, standalone Zig static libraries (`addStaticLibrary`) bundle `compiler-rt` symbols and internal Zig runtime helpers by default unless explicitly disabled.
- **Failure Mode:** Linking multiple `.a` archives under `--whole-archive` triggers `ld.lld: error: duplicate symbol` errors across shared runtime primitives (`__aeabi_*`, panic handlers, etc.) or unprefixed plugin entry hooks.
- **Improvement:**
  - Establish a `hive build` invariant: all `.a` artifacts built for composition must set `bundle_compiler_rt = false`, letting the final `package` link step supply a single `compiler-rt` instance.
  - Enforce symbol hygiene during `build` (e.g., `objcopy --localize-hidden` or `-fvisibility=hidden` by default) so only explicitly exported ABI symbols remain global.

---

## 5. Dynamic Symbol Visibility & `--strip` in `--format so`

### Issue: Post-Link `strip` Does Not Clean `.dynsym`
In Step 4 of `package`, symbol visibility and `--strip` are applied after linking. On ELF/Mach-O targets, running `strip` removes debug sections (`.symtab`), but **does not remove exported symbols from the dynamic symbol table (`.dynsym`)**. Without link-time visibility filtering, all global symbols from every linked `.a` leak into the public interface of the resulting `.so`.
- **Failure Mode:** Polluted `.dynsym` tables, slower `dlopen` relocation times, and accidental symbol interposition at runtime.
- **Improvement:**
  - Synthesize a temporary linker version script (`exports.map`) directly from the `abi` contract declared in `hive.json` during `--format so` assembly:
    ```ld
    {
      global:
        parabellum_plugin_init;
        /* ...symbols from hive.json abi contract... */
      local:
        *;
    };
    ```
  - Pass `-Wl,--version-script=exports.map` (ELF) or `-Wl,-exported_symbols_list,exports.txt` (Mach-O) directly to `zig cc -shared`. This enforces visibility at link time and makes Step 5 (`--verify-abi`) a deterministic post-condition check.

---

## 6. Entrypoint Detection & Cross-Platform Linker Flags (`--format bin`)

### Issue: Ambiguous `main` Discovery and Non-Portable Linker Flags
1. **Entrypoint ambiguity:** Inspecting `.a` symbol tables for `main` fails across platforms and runtimes (POSIX libc uses `main`, freestanding uses `_start`, Windows uses `main`/`wmain`/`WinMain`/`wWinMainCRTStartup`), and breaks if an upstream `.a` accidentally retains a test `main` symbol.
2. **Windows/COFF flag translation:** `-Wl,--whole-archive` applies to ELF (`ld.lld`), whereas Windows COFF (`lld-link`) expects `/WHOLEARCHIVE:<path>`.
- **Improvement:**
  - Require `packaging.entrypoint` in `hive.json` whenever more than one `.a` is present in a `--format bin` assembly; restrict automatic entrypoint discovery to single-archive builds.
  - Explicitly specify target-family linker flag mapping in the `package` spec:
    - **ELF (Linux/BSD):** `-Wl,--whole-archive <archives> -Wl,--no-whole-archive`
    - **Mach-O (macOS):** `-Wl,-force_load,<archive>` (per archive)
    - **COFF/PE (Windows):** `-Wl,/WHOLEARCHIVE:<archive>` (per archive)

---

## 7. Packager Pipeline Semantics (`transform` vs. `sidecar`)

### Issue: Ambiguous `{input}` / `{output}` Chaining in `packaging.packagers`
In a sequential packager pipeline (e.g., `["obfuscate", "pack-donut", "corp-sign"]`), some tools mutate or replace the primary deliverable (`{output}` becomes the `{input}` for the next step), whereas others (like `cosign sign-blob --output-signature {output}.sig {input}`) emit detached sidecar files while leaving the primary binary untouched.
- **Failure Mode:** If `package` unconditionally swaps `{input} = {output}` after every step, a sidecar-producing tool either breaks the pipeline (pointing the next step to a `.sig` file) or fails because `{output}` was never created as a standalone binary.
- **Improvement:**
  - Add an explicit `mode` field (`"transform"` | `"sidecar"`) to packager definitions in `hive.json`:
    ```json
    "packagers": {
      "donut-pack": {
        "mode": "transform",
        "command": ["donut", "-i", "{input}", "-o", "{output}"]
      },
      "corp-sign": {
        "mode": "sidecar",
        "outputs": ["{input}.sig"],
        "command": ["cosign", "sign-blob", "--output-signature", "{input}.sig", "{input}"]
      }
    }
    ```
  - `"transform"` updates the active deliverable path for downstream packagers and `manifest.json`; `"sidecar"` preserves the active deliverable path and registers declared `outputs` as auxiliary artifacts in `manifest.json` and `SHA256SUMS.txt`.

---

## 8. Single Source of Truth Between `hive.json` and `build.zig`

### Issue: Configuration Drift
Declaring artifact names, ABI contracts, and dependency coordinates in `hive.json` while defining compilation targets and library names in `build.zig` creates dual-maintenance overhead.
- **Improvement:**
  - Have `hive build` generate an ephemeral `.zig-cache/hive_deps.zig` (or pass structured `-D` build options) exposing resolved `~/.hive/packages/` paths, target triples, and version metadata directly to `build.zig`, eliminating hardcoded paths or duplicated metadata in user build scripts.