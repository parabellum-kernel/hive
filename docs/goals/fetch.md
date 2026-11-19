# Goal: `fetch`

## 1. Purpose

The `fetch` goal resolves and downloads external compiled artifacts (`.so`, `.a`, binaries, and `manifest.json`) declared in `hive.json` from any configured **Artifact Repository** into the default local Artifact Repository (`~/.hive/packages/<name>/<version>/<target>/`), ensuring every required dependency is available locally before `build`, `package`, or runtime execution.

`fetch` comes with a closed set of built-in transport providers (`local`, `github`, `http`, `git` via [libgit](../docs/libgit.md)) so `hive` remains stable without loading userspace plugins.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace whose dependencies should be resolved. |
| `--offline` | `bool` | `false` | Resolve strictly from `~/.hive/packages/` without performing any network requests; fail if any required artifact is missing. |
| `--refresh` | `bool` | `false` | Re-validate remote metadata / checksums even if an artifact is already cached locally. |
| `--target` | `string` (Zig target triple) | `native` | Target platform triple to fetch compatible binary artifacts for. |
| `--artifact-repository-dir` | `path` | `~/.hive/packages` | Override the local artifact repository root. |

---

## 3. Built-In Transport Modes

Remote repositories and dependencies are declared declaratively in `hive.json`:

```json
{
  "repositories": [
    { "name": "local", "type": "local", "path": "~/.hive/packages" },
    { "name": "org-releases", "type": "github", "owner": "my-org" },
    { "name": "corp-mirror", "type": "http", "url": "https://artifacts.corp.internal/hive" }
  ],
  "dependencies": {
    "libgit": { "version": "1.0.0", "repo": "org-releases" }
  }
}
```

| Provider | Scheme / Type | Behavior |
|---|---|---|
| `fetch-local` | `local` | Resolves directly from `~/.hive/packages/` or a configured filesystem path. |
| `fetch-github` | `github` | Downloads platform-qualified assets (e.g. `<name>-<version>-<target>.tar.gz`, `SHA256SUMS.txt`) from GitHub Releases for tag `v<version>` and unpacks them into `<version>/<target>/`. |
| `fetch-http` | `http` | Fetches artifacts from any static HTTP/HTTPS Maven-style layout (`<base>/<name>/<version>/<target>/<file>`). |
| `fetch-git` | `git` | Clones/fetches Git-backed artifacts or sources (including private `git+ssh://` repos) via [libgit](../docs/libgit.md). |

---

## 4. Execution Logic

1. **Read `hive.json` Dependencies**:
   - Parse declared dependencies and repository endpoints. If no external dependencies are declared, succeed as a fast no-op.
2. **Check Local Cache (`~/.hive/packages/`)**:
   - Resolve `--target` (`native` → canonical Zig host triple, e.g. `x86_64-linux-gnu`).
   - For each `<name>@<version>`:
     - If `<version>` ends in `-snapshot`, prefer the local `~/.hive/packages/<name>/<version>/<target>/` first; only download from a remote repository if missing locally (and a remote `repo` is configured) or when `--refresh` is explicitly passed.
     - If a stable `<version>/<target>/` already exists locally with a valid `manifest.json` and matching SHA-256 (and `--refresh` is `false`), skip download.
3. **Authenticate, Download & Verify**:
   - If `--offline` is set and an artifact is missing, abort with a clear error.
   - Resolve transport credentials without storing plaintext secrets in `hive.json`:
     - `git`: delegated to `libgit` / OpenSSH (`~/.ssh/config`, `ssh-agent`, credential helpers).
     - `github`: `GITHUB_TOKEN` / `HIVE_GITHUB_TOKEN` (or `~/.hive/credentials.json`).
     - `http`: TLS + `auth_env` env var / `HIVE_HTTP_TOKEN` / `~/.hive/credentials.json` (`0600`).
   - Fetch the artifact(s) and checksums via the configured provider (`github`, `http`, or `git`).
   - Verify SHA-256 digest (if a mismatch occurs and an opt-in `.ecc` Hamming/ECC sidecar exists remotely, download it temporarily, attempt bit-flip repair, and **re-verify** SHA-256; discard `.ecc` afterwards).
   - If `.sig` is present (or `require_signature: true` in `hive.json`), verify the asymmetric signature against `~/.hive/trusted-keys/` before atomically installing into `~/.hive/packages/<name>/<version>/<target>/` with `0755` permissions.
4. **Summary Output**:
   - Print resolved count (cached vs. downloaded) and total bytes fetched.

---

## 5. Invariants

- **Snapshot precedence**: `*-snapshot` versions resolve local-first so local `hive install` builds are not silently overwritten; remote snapshot pre-releases are fetched when missing locally or with `--refresh`.
- **Integrity first**: Every downloaded artifact is verified against its SHA-256 digest before entering `~/.hive/packages/`.
- **Idempotent**: Re-running `fetch` when all stable dependencies are cached performs zero network I/O.
