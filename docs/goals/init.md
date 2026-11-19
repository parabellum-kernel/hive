# Goal: `init`

## 1. Purpose

The `init` goal scaffolds a new project directory from an external **template (archetype)** stored locally in `~/.hive/templates/`, referenced by local filesystem path, or fetched from a Git repository (including private `git+ssh://` / `git@host:org/repo.git` repositories via `libgit`).

`hive` does **not** hardcode ecosystem-specific templates (such as Parabellum plugins) inside the binary — keeping `hive` completely decoupled and allowing users and teams to author and share their own archetypes.

---

## 2. Inputs & Options

| Option | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | Required | Name of the new project (also used as the target directory unless `--dir` is provided). |
| `--template` (`-t`) | `name \| path \| git-url` | Required | Template identifier: a cached name in `~/.hive/templates/<name>`, a local directory path, or a Git URL (`https://...`, `ssh://...`, `git@...`, `git+ssh://...`). |
| `--dir` | `path` | `./<name>` | Destination directory where the project will be created. |
| `--version` | `SemVer` | `0.1.0` | Initial project version substituted into `{{version}}`. |
| `--var` | `key=value` (repeatable) | `[]` | Custom template variable overrides substituted into `{{key}}`. |
| `--refresh` | `bool` | `false` | If the template is already cached in `~/.hive/templates/<name>`, pull the latest upstream changes via `libgit` before rendering. |
| `--force` | `none \| overlay \| wipe` | `none` | Conflict policy when the destination directory is non-empty: `none` (abort), `overlay` (overwrite only colliding template files; also default when `--force` is passed without a value), or `wipe` (clear all existing entries except `.git/` with unsafe-root guards). |
| `--templates-dir` | `path` | `~/.hive/templates` | Override the local template cache root. |

---

## 3. Template (Archetype) Layout

Every template (whether local or cloned from Git into `~/.hive/templates/<template-name>/`) follows a simple, declarative structure:

```text
~/.hive/templates/<template-name>/
├── template.json       # Template metadata, declared variables, and defaults
└── files/              # Directory tree copied and rendered into the new project
    ├── build.zig
    ├── build.zig.zon
    ├── hive.json
    └── src/
        └── ...
```

### `template.json` Schema

```json
{
  "name": "zig-plugin",
  "version": "1.0.0",
  "description": "Starter template for a modular Zig plugin",
  "variables": {
    "project_name": { "required": true },
    "version": { "default": "0.1.0" },
    "author": { "default": "" }
  }
}
```

- Placeholders inside text files under `files/` (and in file/directory names) use double-brace syntax: `{{project_name}}`, `{{version}}`, `{{author}}`, etc.
- Binary files (detected by NUL byte or configured skip list) are copied verbatim without placeholder substitution.

---

## 4. Execution Logic

1. **Resolve Template Source**:
   - **Local path** (starts with `./`, `../`, `/` or exists on disk): use directly without copying into `~/.hive/templates/`.
   - **Git URL** (`https://`, `http://`, `ssh://`, `git+ssh://`, `git@`): derive canonical template name from the repository name, clone into `~/.hive/templates/<name>/` via `libgit` (or pull if `--refresh` is set and it already exists).
   - **Cached name** (e.g. `zig-plugin`): resolve `~/.hive/templates/<name>/`. Fail with a clear message if not found.
2. **Load & Validate `template.json`**:
   - Parse `template.json` using `std.json`.
   - Merge built-in variables (`project_name`, `version`), `template.json` defaults, and CLI `--var key=value` overrides.
   - Verify all `required: true` variables have values.
3. **Prepare Destination Directory**:
   - **`--force none`** (default): refuse to write into a non-empty destination directory.
   - **`--force overlay`** (or bare `--force`): never delete existing unrelated files or `.git/`; only overwrite files whose rendered paths collide with the template.
   - **`--force wipe`**: verify the destination is not an unsafe root (`/`, `$HOME`, `/tmp`, etc.) and remove all entries inside `<dir>` **except `.git/`** before rendering.
   - Create destination directory tree as needed.
4. **Render `files/` Tree**:
   - Walk `<template>/files/` recursively (skipping `.git`).
   - Substitute `{{var}}` in relative paths and text file contents.
   - Write rendered files to `<dir>/`, preserving executable permissions.
5. **Summary Output**:
   - Print the created directory, template source, and number of files rendered.

---

## 5. Invariants

- **Zero coupling to any specific framework**: `hive` contains no hardcoded Parabellum/SDK templates; any Git repository following `template.json` + `files/` works out of the box.
- **Private repo support**: Git cloning/refreshing goes through `libgit`, supporting `git+ssh://`, `git@host:org/repo.git`, `~/.ssh/config`, and SSH agents.
- **Safe by default**: Defaults to `--force none` (refuses non-empty target directories); even with `--force overlay` or `--force wipe`, `.git/` is never deleted.
