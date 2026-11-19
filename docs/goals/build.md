# Goal: `build`

## 1. Purpose

The `build` goal compiles one or more Zig projects using `zig build`, discovers all produced artifacts (`.a` static archives / `.o` objects for `hive package`, `.so` shared libraries, and executables) in `zig-out/`, and validates that compiled `.so` plugins conform to the expected ABI contract when `--verify-abi` is enabled.

`build` **only** writes to each repository's local `zig-out/` directory; it never modifies `~/.hive/packages/`.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace repos to build. |
| `--optimize` | `Debug \| ReleaseSafe \| ReleaseFast \| ReleaseSmall` | `Debug` | Passed through to `zig build -Doptimize=<mode>`. |
| `--target` | `string` (Zig target triple) | `native` | Cross-compilation target (Linux, macOS, Windows across architectures, e.g. `x86_64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`) passed to `zig build -Dtarget=<triple>`. |
| `--linkage` | `static \| dynamic \| both` | `both` | Artifact linkage to produce: `.a` static archives (required by `hive package`), `.so` shared libraries, or both. |
| `--verify-abi` | `bool` | `true` | Inspect produced `.so` files to verify exported manifest symbols and ABI version compatibility. |
| `--parallel` (`-j`) | `uint` | CPU count / `1` | Maximum number of independent repositories built concurrently in workspace mode. |
| `--extra-args` | `[]string` | `[]` | Additional flags forwarded verbatim to `zig build`. |

---

## 3. Execution Logic

1. **Resolve Project Metadata**:
   - Parse `build.zig.zon` (via `std.zon`) in each target repository to extract `.name`, `.version`, and `.dependencies`.
   - In workspace mode, compute a **topological sort** of repositories based on local dependency edges (e.g., `core` → `lib-net`, `lib-db`, `engine` → `app`, `cli`). Detect and abort on dependency cycles.
2. **Invoke `zig build`**:
   - Run `zig build -Doptimize=<optimize> [-Dtarget=<target>] [extra-args...]` in each repository's root directory.
   - Stream stderr/stdout clearly prefixed by repository name in workspace mode.
   - On non-zero exit code, record failure and halt downstream dependent repositories (while optionally letting independent branches finish).
3. **Discover Produced Artifacts**:
   - Scan `<repo>/zig-out/lib/` for static archives (`*.a`, `*.lib`) and shared libraries (`*.so`, `*.dylib`, `*.dll`).
   - Scan `<repo>/zig-out/bin/` for executables (and Windows `*.dll` files, classifying `bin` vs `dynamic` via extension and binary header such as PE `IMAGE_FILE_DLL` / ELF `PT_INTERP` / Mach-O `MH_EXECUTE`).
   - Compute SHA-256 checksum and file size for every discovered artifact.
4. **ABI & Symbol Verification (`--verify-abi`)**:
   - Verification is **100% ecosystem-agnostic** and driven declaratively by an optional `abi` section in `hive.json` (no framework-specific symbols are hardcoded in `hive`):
     ```json
     {
       "abi": {
         "required_symbols": [],
         "any_of_symbols": ["my_module_manifest", "my_driver_manifest"],
         "validator": ["my-abi-check", "{artifact}"]
       }
     }
     ```
   - For each discovered shared library:
     - Always verify the artifact is a valid binary matching the target architecture and OS format (`std.elf` for Linux, `std.macho` for macOS, `std.coff` for Windows).
     - If `abi.required_symbols` or `abi.any_of_symbols` is declared in `hive.json`, inspect the exported symbol table (ELF/Mach-O/PE, or `dlsym` on host) and confirm the declared symbol contract is satisfied.
     - If `abi.validator` is declared in `hive.json` (and building for a host-executable target), invoke the external validator command with `{artifact}` substituted to perform ecosystem-specific struct/version checks.
5. **Emit Build Report**:
   - Output a structured summary (and machine-readable payload for downstream goals like `package`, `install`, and `publish`) listing each built artifact's path, linkage (`static` / `dynamic` / `bin`), name, version, target triple, and SHA-256 digest.

---

## 4. Consuming `~/.hive/packages/` Dependencies

Projects using `hive.json` `dependencies` can consume compiled artifacts from `~/.hive/packages/<name>/<version>/<target>/` in two ways:

1. **Dynamic Runtime Loading (Plugin / Microkernel Hosts)**:
   - `build.zig` does not link against the dependency at compile time; the host binary loads `.so` / `.dylib` / `.dll` artifacts at runtime via `std.DynLib` (while `hive fetch` ensures they are present locally).
2. **Direct Compile-Time Linking (Standard Zig Projects)**:
   - When `build.zig` needs to link `.a` / `.so` libraries or include C headers from `~/.hive/packages/`, projects can use the lightweight `hive` Zig build helper (or pass `-Dhive-artifact-repo=<path>`):
     - Resolves `<artifact-repository-dir>/<name>/<version>/<target>/` from `hive.json` (falling back to `HIVE_HOME` / `~/.hive/packages` when running `zig build` standalone without `hive`).
     - Attaches `addLibraryPath`, `addObjectFile` / `linkSystemLibrary`, and `addIncludePath` directly to the Zig compile step.
   - Pure Zig source dependencies continue to use `build.zig.zon` (`b.dependency(...)`).

---

## 5. Failure Modes & Invariants

- **Strict isolation**: `build` never mutates `~/.hive/packages/` or remote repositories.
- **No silent ABI drift**: If a `.so` compiles but violates the symbol or validator contract declared in `hive.json`, `build` fails early before `package`, `install`, or `publish` can distribute a broken artifact.
