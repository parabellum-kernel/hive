# `libgit` — Specification & Design

## 1. Purpose

`libgit` is a lightweight, Zig-native Git client library distributed as a standard `hive` package (`~/.hive/packages/libgit/<version>/`). It does **not** compete with `libgit2` (no C/OpenSSL/libssh2 cross-compilation burden); instead, it provides a **strict, version-tracked Zig wrapper over Git's stable plumbing CLI** (`git`).

By centralizing all Git operations inside `libgit`, `hive` (and any other Zig tool) gains:
- **Native `git+ssh://` & private repo support**: inherits the user's OpenSSH config (`~/.ssh/config`), `ssh-agent`, `ProxyJump`, and corporate credential helpers out of the box (solving `zig fetch`'s limitation with private SSH repos).
- **Isolated contract tracking**: if a future `git` binary version changes a flag, exit code, or output format, the fix happens once in `libgit` without touching `hive`'s goals.
- **Shared reuse across goals**: used by `hive init` (cloning/refreshing templates), `hive add` (cloning private `git+ssh://` deps for hash computation), `hive release` (working-tree checks, tagging, pushing), `hive fetch` (Git-backed artifact resolution), and `hive publish` (`publish-git` artifact-registry pushes).

---

## 2. Package Distribution

`libgit` follows the standard `hive` dual-artifact package model:

```text
~/.hive/packages/libgit/<version>/
├── libgit.so           # Dynamic runtime artifact (when loaded dynamically)
├── libgit.a            # Static archive for monolithic `hive package` linking
└── manifest.json       # Package metadata, target, SHA-256
```

During early bootstrapping of `hive`, `libgit` starts as an internal module (`src/git.zig`) with the exact same public API so it can be extracted into its own repository and published to `~/.hive/packages/libgit/` with zero caller rewrites.

---

## 3. Core Capabilities & Public API

### 3.1 Binary Discovery & Version Guard
- `GitClient.init(allocator)` locates the `git` binary in `PATH` (or `HIVE_GIT_BIN` override).
- `GitClient.version()` parses `git --version` into `{ major, minor, patch }`.
- Enforces a minimum supported Git version (e.g., `>= 2.20.0`) so plumbing flags (`--porcelain=v1`, `--depth`, `--follow-tags`) behave deterministically.

### 3.2 URL Normalization
- Accepts standard Git URLs: `https://...`, `http://...`, `ssh://...`, `git@host:org/repo.git`.
- Normalizes Zig-style `git+ssh://...` and `git+https://...` prefixes automatically to `ssh://...` / `https://...` before invoking `git`.
- Extracts repository short name (e.g., `git@github.com:org/parabellum-plugin.git` → `parabellum-plugin`) for template caching.

### 3.3 Repository Operations

| Operation | Underlying Plumbing Command | Used By |
|---|---|---|
| `clone(url, dest, opts)` | `git clone [--depth N] [--branch ref] -- <url> <dest>` | `hive init`, `hive fetch`, `hive add`, `hive publish` (`publish-git`) |
| `pullFastForward(repo_dir)` | `git -C <dir> pull --ff-only` | `hive init --refresh` |
| `isClean(repo_dir)` | `git -C <dir> status --porcelain=v1` | `hive release` |
| `currentBranch(repo_dir)` | `git -C <dir> rev-parse --abbrev-ref HEAD` | `hive release` |
| `isUpToDateWithRemote(repo_dir, remote, branch)` | `git -C <dir> fetch <remote> <branch>` + `rev-list --count HEAD..@{u}` | `hive release` |
| `tagExists(repo_dir, tag)` | `git -C <dir> rev-parse --verify refs/tags/<tag>` | `hive release` |
| `remoteTagExists(repo_dir, remote, tag)` | `git -C <dir> ls-remote --tags <remote> refs/tags/<tag>` | `hive release` |
| `commit(repo_dir, message)` | `git -C <dir> commit -m <message>` | `hive release`, `hive publish` (`publish-git`) |
| `createAnnotatedTag(repo_dir, tag, msg)` | `git -C <dir> tag -a <tag> -m <msg>` | `hive release` |
| `pushWithTags(repo_dir, remote, branch)` | `git -C <dir> push <remote> <branch> --follow-tags` | `hive release`, `hive publish` (`publish-git`) |

---

## 4. Error Model & Safety Invariants

- **Typed Zig errors**: `GitNotFound`, `UnsupportedGitVersion`, `CommandFailed`, `DirtyWorkingTree`, `TagAlreadyExists`, `AuthenticationFailed`, `NetworkError`.
- **No shell interpolation**: every command is spawned via `argv` arrays (`std.process.Child`), never via `/bin/sh -c`, eliminating shell-injection risks from URLs, branch names, or paths.
- **Explicit `--` argument separators**: user-provided URLs and paths are passed after `--` so crafted strings starting with `-` cannot be interpreted as Git flags.
- **Non-interactive safety**: supports `GIT_TERMINAL_PROMPT=0` in CI/non-interactive runs so commands fail cleanly instead of hanging indefinitely on missing credentials.
