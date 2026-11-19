# Environment Variables

`hive` reads environment variables for configuration, authentication, build scripts, and kernel telemetry (OpenTelemetry and JSON Lines tracing).

---

## 1. Core & Runtime

| Variable | Default | Description |
|---|---|---|
| `HIVE_HOME` | `~/.hive` | Base directory for `packages/`, `templates/`, `trusted-keys/`, and `credentials.json`. Overridden by `--artifact-repository-dir` and `--templates-dir`. |
| `HIVE_WORKERS` | CPU core count | Maximum number of parallel DAG workers. Overridden by `--parallel` / `-j`. |
| `HIVE_GIT_BIN` | `git` (from `PATH`) | Explicit path to the `git` binary used by [libgit](libgit.md). |
| `GIT_TERMINAL_PROMPT` | `"0"` (internal override) | `hive` sets `GIT_TERMINAL_PROMPT=0` when spawning `git` subprocesses to prevent interactive credential prompts from hanging CI/non-interactive runs. |
| `NO_COLOR` | Unset | Disables ANSI color output when set to any non-empty value (equivalent to `--no-color`). |

---

## 2. Authentication & Providers

| Variable | Default | Description |
|---|---|---|
| `HIVE_GITHUB_TOKEN` | Unset | GitHub personal access token used by the GitHub provider (`fetch` / `publish`). Takes precedence over `GITHUB_TOKEN`. |
| `GITHUB_TOKEN` | Unset | Fallback GitHub token when `HIVE_GITHUB_TOKEN` is not set. |
| `HIVE_HTTP_TOKEN` | Unset | Fallback Bearer token for HTTP artifact repositories when a repository-specific `auth_env` variable is not configured or unset. |

---

## 3. Telemetry & Tracing (OTEL / JSONL)

`hive` registers the `ext_opentelemetry` and `ext_trace_jsonl` kernel extensions at runtime (`src/runtime.zig`). Both are configured via environment variables:

| Variable | Default | Description |
|---|---|---|
| `PARABELLUM_OTEL_FILE` | Unset (console) | File path where OpenTelemetry trace lines (`[OTEL] ...`) are written in append mode (`"a"`). Setting this disables console OTEL output unless `PARABELLUM_OTEL_CONSOLE` is enabled. |
| `PARABELLUM_OTEL_CONSOLE` | `false` (or `true` when `PARABELLUM_OTEL_FILE` is unset) | Set to `1` or `true` to print `[OTEL]` lines to the console even when `PARABELLUM_OTEL_FILE` is set. |
| `PARABELLUM_TRACE_OUT` | Unset (disabled) | File path where structured telemetry events are written as JSON Lines (`.jsonl`) in append mode (`"a"`). |

### Example

```bash
PARABELLUM_OTEL_FILE=./otel.log PARABELLUM_TRACE_OUT=./trace.jsonl hive build
```

To emit both OTEL to a file and keep OTEL output in the terminal:

```bash
PARABELLUM_OTEL_FILE=./otel.log PARABELLUM_OTEL_CONSOLE=1 PARABELLUM_TRACE_OUT=./trace.jsonl hive build
```

---

## 4. Build Scripts (`scripts/`)

Used by `scripts/build-linux.sh`, `scripts/build-macos.sh`, and `scripts/build-windows.ps1`:

| Variable | Default | Description |
|---|---|---|
| `HIVE_TARGET` | `native` | Zig target triple passed via `-Dtarget=...` (overridden by `--target` / `-Target`). |
| `HIVE_OPTIMIZE` | `ReleaseSafe` | Zig optimize mode passed via `-Doptimize=...` (overridden by `--optimize` / `-Optimize`). |
| `HIVE_PREFIX` | `~/.local` (Linux/macOS), `%LOCALAPPDATA%\hive` (Windows) | Installation prefix when `--install` / `--prefix` is used. |
