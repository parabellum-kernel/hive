# Goal: `test`

## 1. Purpose

The `test` goal executes unit tests and optional integration (`e2e`) test suites across one or more Zig repositories. Within the master linear lifecycle (`build → test → package → install → publish`), `test` acts as the **quality gate** before packaging and distribution.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace repos to test. |
| `--tier` | `unit \| e2e \| all` | `unit` | `unit` runs `zig build test`; `e2e` runs `zig build test-e2e` (when defined by the project); `all` runs both. |
| `--filter` | `string` | `null` | Optional test name filter forwarded to `zig build test -Dtest-filter=...` (when supported). |
| `--fail-fast` | `bool` | `false` | Stop immediately on the first failing repository instead of collecting results for all repos. |
| `--optimize` | `Debug \| ReleaseSafe` | `Debug` | Optimization mode for test binaries. |
| `--extra-args` | `[]string` | `[]` | Additional flags forwarded verbatim to `zig build test` / `test-e2e`. |

---

## 3. Execution Logic

1. **Master Linear Lifecycle Activation**:
   - Invoking `hive test` activates `build → test` (incremental; does **not** run `clean` or `fetch` unless explicitly requested, e.g. `hive clean test`).
   - Upstream phases can be skipped with `-x build`.
2. **Resolve Test Targets**:
   - In single-project mode, inspect `build.zig` (or `zig build --help`) to verify available test steps (`test`, `test-e2e`).
   - In workspace mode, order repositories topologically so foundational library failures surface before downstream failures.
3. **Execute Tier 1 (`unit`)**:
   - Run `zig build test -Doptimize=<optimize> [extra-args...]` in each target repository.
   - Capture exit code, duration, and stderr/stdout logs.
4. **Execute Tier 2 (`e2e`, when `--tier=e2e` or `all`)**:
   - If the repository defines a `test-e2e` step (and any custom flags configured in `hive.json` under `test.e2e_args`), invoke `zig build test-e2e`.
   - Skip gracefully (with an informational log) for repositories that do not define `test-e2e`.
5. **Aggregate & Report**:
   - Produce a structured pass/fail table per repository and tier, including execution time.
   - Exit with `0` only if every executed test step passed; exit non-zero otherwise.

---

## 4. Integration with Downstream Goals

- `package`, `install`, and `publish` activate `test` automatically as an upstream phase in the master linear pipeline.
- `package` and `install` allow skipping `test` via `-x test` for rapid local iteration (explicitly logged as unverified).
- `publish` **does not** allow `-x test` unless an explicit `--force-untested` override is passed.
