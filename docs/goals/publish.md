# Goal: `publish`

## 1. Purpose

The `publish` goal uploads packaged artifacts (`.so`, `.a`, binaries, `manifest.json`, and `SHA256SUMS.txt`) to a configured **Artifact Repository** declared in `hive.json` — the exact remote counterpart to `hive install` (which targets the default local Artifact Repository `~/.hive/packages/`) and the symmetric producer for `hive fetch`, analogous to `mvn deploy` or `gradle publish`.

`publish` **never** modifies your Git history, creates commits/tags, or rewrites `build.zig.zon` (for source-level Git releases, see [goals/release.md](release.md)).

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `target` | `path \| repo-name \| all` | Current directory | Project or workspace repos to publish. |
| `--repo` (`-r`) | `string` | First remote repo in `hive.json` | Target repository name declared under `repositories` in `hive.json`. |
| `--snapshot` | `bool` | `false` | Publish as a mutable `<version>-snapshot` pre-release for remote testing/staging (overwritable). |
| `--release` | `bool` | `true` (unless `--snapshot`) | Publish as an immutable `<version>` release (fails if version already exists remotely unless `--force`). |
| `--version` | `SemVer` | Read from `hive.json` / `build.zig.zon` | Explicit version override for the published artifact coordinates. |
| `--targets` | `[]string` | Host native target | Zig target triples to build, package, and publish (e.g., `x86_64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`). |
| `--force` | `bool` | `false` | Overwrite existing remote stable version assets (if permitted by the remote repository). |
| `--dry-run` (`-n`) | `bool` | `false` | Run upstream lifecycle phases and print target repository, coordinates, and files that would be uploaded without network writes. |
| `--force-untested` | `bool` | `false` | Dangerous override allowing `-x test` during `publish`. |
| `--ecc` | `bool` | `false` | Opt-in: generate a sidecar `<artifact>.ecc` (Hamming/ECC parity) alongside the unmodified binary for unreliable/air-gapped links. |

---

## 3. Supported Remote Transports

`publish` uses the same closed set of built-in repository providers as `hive fetch` (declared in `hive.json`):

| Provider | Type | Behavior |
|---|---|---|
| `publish-http` | `http` | Uploads `<artifact>`, `manifest.json`, and `SHA256SUMS.txt` via HTTP `PUT`/`POST` to `<url>/<name>/<version>[-snapshot]/<target>/` (and target-agnostic `-sources`/`-docs` tarballs to `<url>/<name>/<version>[-snapshot]/`). |
| `publish-github` | `github` | Creates/updates a GitHub Release (`v<version>` or `prerelease: true` for `-snapshot`) and uploads target-qualified assets (`<name>-<version>-<target>.tar.gz`, etc.) + `SHA256SUMS.txt`. |
| `publish-git` | `git` | Commits & pushes artifacts into a dedicated artifact-registry Git repository via [libgit](../docs/libgit.md) (does **not** touch the source repo's Git history). |

---

## 4. Execution Logic

1. **Master Linear Lifecycle Activation**:
   - `hive/publish` itself is single-responsibility and does **not** compile, test, or package directly.
   - Invoking `hive publish` activates the core linear lifecycle up to `publish`:
     - `build` → `test` → `package` → `install` → `publish` (skipping any excluded phase, though `-x test` is rejected unless `--force-untested` is set).
2. **Resolve Coordinates & Remote Repository**:
   - Read `<name>` and `<version>` from `hive.json` / `build.zig.zon` (applying `--version` and appending `-snapshot` if `--snapshot` is set).
   - Resolve the target repository entry from `hive.json` `repositories`.
3. **Prepare Upload Bundle**:
   - Collect packaged artifacts from `zig-out/dist/` (or `zig-out/lib/` + `zig-out/bin/`), `manifest.json`, and generate `SHA256SUMS.txt` (and optional `.sig` / opt-in `--ecc` sidecar without altering the binary).
4. **Authenticate, Immutability Check & Upload**:
   - Authenticate via transport infrastructure (`libgit`/SSH for `git`, `GITHUB_TOKEN`/`HIVE_GITHUB_TOKEN` for `github`, `auth_env`/`HIVE_HTTP_TOKEN`/`~/.hive/credentials.json` `0600` for `http`).
   - Unless `--snapshot` or `--force`, verify the target `<name>/<version>/<target>` does not already exist remotely.
   - Upload all assets via the configured provider (`http`, `github`, or `git`), or print the upload plan if `--dry-run`.
5. **Summary Output**:
   - Print published coordinates (`<name>@<effective_version> -> <repo-name> (<url>)`) and uploaded asset list.

---

## 5. Invariants

- **Zero source-repo Git side effects**: `publish` never runs `git commit`, `git tag`, or `git push` on the project's source repository.
- **Symmetric with `fetch` and `install`**: Anything uploaded by `hive publish` can be resolved directly by `hive fetch` using the exact same `hive.json` `repositories` layout.
- **Immutable stable releases**: Stable `<version>` uploads fail if already present unless `--force` is explicitly passed; `--snapshot` uploads are mutable for rapid staging/testing.
