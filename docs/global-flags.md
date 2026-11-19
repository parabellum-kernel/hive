# Global Flags & Environment Variables

Global flags apply across `hive` commands and are parsed before or alongside goal-specific options.

---

## 1. Global CLI Flags

| Flag | Short | Argument | Default | Description |
|---|---|---|---|---|
| `--help` | `-h` | — | — | Print usage information for `hive` or a specific goal (`hive <goal> --help`). |
| `--version` | `-v` | — | — | Print `hive` version and exit (when passed at top level). *Note: inside `hive add`, `-v` / `--version` specifies the dependency version.* |
| `--exclude` | `-x` | `<goal>` (repeatable) | `[]` | Skip an upstream phase in the linear lifecycle (e.g. `hive install -x test -x package`). |
| `--artifact-repository-dir` | — | `<path>` | `~/.hive/packages` | Override the local Artifact Repository root (takes precedence over `HIVE_HOME`). |
| `--templates-dir` | — | `<path>` | `~/.hive/templates` | Override the local template cache root (takes precedence over `HIVE_HOME`). |
| `--module` | — | `<name>` | All modules | Target a specific module in workspace mode (equivalent to `hive :<name>:<goal>`). |
| `--cwd` | `-C` | `<path>` | Current directory | Run `hive` as if invoked inside `<path>`. |
| `--verbose` | — | — | `false` | Emit detailed diagnostic logs (underlying `zig` and `git` commands). |
| `--quiet` | `-q` | — | `false` | Suppress non-essential output; only print errors and final summary. |
| `--json` | — | — | `false` | Emit machine-readable JSON output for CI and tooling integration. |
| `--no-color` | — | — | `false` | Disable ANSI colors in terminal output (also respects `NO_COLOR`). |

---

## 2. Common Multi-Goal Flags

These flags are not strictly global to every goal, but share identical semantics across the goals that support them:

| Flag | Short | Supported Goals | Description |
|---|---|---|---|
| `--dry-run` | `-n` | `clean`, `publish`, `release` | Run checks/builds without mutating files, Git history, or remote repositories. |
| `--offline` | — | `fetch` | Disallow network requests; resolve strictly from `--artifact-repository-dir`. |
| `--refresh` | — | `init`, `fetch` | Re-validate or pull latest remote state even when cached locally. |
| `--force` | — | `init`, `install`, `publish` | Override immutability or non-empty directory guards (see each goal's spec for exact policies). |

---

## 3. Environment Variables

See [env-vars.md](env-vars.md) for the complete reference (including authentication, OpenTelemetry/JSONL tracing, and build script variables).

| Variable | Default | Description |
|---|---|---|
| `HIVE_HOME` | `~/.hive` | Base directory for `packages/` and `templates/`. Overridden by `--artifact-repository-dir` and `--templates-dir`. |
| `HIVE_GIT_BIN` | `git` (from `PATH`) | Explicit path to the `git` binary used by [libgit](libgit.md). |
| `NO_COLOR` | Unset | Disables ANSI color output when set to any non-empty value. |
