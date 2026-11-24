# `hive.json` — Project & Workspace Descriptor

`hive.json` is the optional, machine-friendly JSON configuration file at the root of a project or multi-module workspace. Because users rarely hand-edit it, JSON is chosen over YAML for strictness and zero-dependency parsing via Zig's `std.json`.

If `hive.json` is absent, `hive` falls back to `.name` and `.version` from `build.zig.zon` and uses sensible defaults for every goal.

---

## 1. Complete Example

```json
{
  "group": "org.parabellum",
  "name": "my-app",
  "version": "1.0.0",
  "modules": [],
  "artifacts": {
    "app": ["my-app", "libapp"],
    "plugin": ["libmy_plugin"]
  },

  "repositories": [
    { "name": "local", "type": "local", "path": "~/.hive/packages" },
    { "name": "org-releases", "type": "github", "owner": "my-org" },
    {
      "name": "corp-mirror",
      "type": "http",
      "url": "https://artifacts.corp.internal/hive",
      "auth_env": "CORP_HIVE_TOKEN",
      "require_signature": false
    },
    { "name": "team-registry", "type": "git", "url": "git@github.com:my-org/hive-registry.git" }
  ],

  "dependencies": {
    "org.parabellum:libgit": { "version": "1.0.0", "repo": "org-releases" },
    "my-plugin": { "version": "0.2.0-snapshot" }
  },
  "dependency_overrides": {
    "org.parabellum:libgit": { "version": "1.0.1" }
  },

  "abi": {
    "required_symbols": [],
    "any_of_symbols": ["my_module_manifest"],
    "validator": ["my-abi-check", "{artifact}"]
  },

  "docs": {
    "step": "docs",
    "root_source_file": "src/root.zig"
  },

  "test": {
    "e2e_args": []
  },

  "release": {
    "branch": "main"
  },

  "packaging": {
    "default_format": "so",
    "sources": false,
    "docs": false,
    "entrypoint": "libapp.a",
    "link_libs": ["c"],
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
        "lto": false,
        "sources": true,
        "docs": true,
        "packagers": ["corp-sign"]
      }
    }
  }
}
```

---

## 2. Field Reference

| Section | Required | Description |
|---|---|---|
| `group` | No | Publisher group coordinate (e.g. `"org.parabellum"`). Defaults to `"local"`. |
| `name` | No | Artifact coordinate name. Falls back to `.name` in `build.zig.zon`. |
| `version` | No | SemVer string (`"1.0.0"`). Falls back to `.version` in `build.zig.zon`. |
| `modules` | No | List of relative subdirectory paths for multi-module workspaces (e.g. `["sdk", "engine", "app"]`). Empty/omitted means single-project mode. |
| `artifacts` | No | Optional map of `<artifact-id> -> [<filename-prefix>, ...]` to split outputs from a single `build.zig` into separate coordinates during `hive install`. |
| `repositories` | No | Ordered list of artifact repositories queried by `hive fetch` (`local`, `github`, `http`, `git`), with optional `auth_env` (env var name for tokens—never plaintext secrets) and `require_signature`. |
| `dependencies` | No | Map of `<group>:<artifact>` (or `<artifact>`) `-> { version, repo? }` resolved by `hive fetch` and linked by `hive package`. |
| `dependency_overrides` | No | Optional map of `<group>:<artifact> -> { version, repo? }` to pin transitive dependency versions and resolve graph conflicts. |
| `abi` | No | Ecosystem-agnostic symbol & validator contract checked by `hive build --verify-abi` and `hive package --verify-abi`. |
| `docs` | No | Optional `autodoc` overrides (`step` name in `build.zig`, `root_source_file` fallback). |
| `test` | No | Optional test overrides (`e2e_args` forwarded to `zig build test-e2e`). |
| `release` | No | Optional source release settings (e.g., `branch`, defaulting to `"main"`). |
| `packaging` | No | Default output format (`bin` \| `so` \| `tar`), `sources` / `docs` bundle toggles, `entrypoint` / `link_libs` for `zig cc` assembly, named external `packagers` (`{input}` / `{output}` placeholders), and named `profiles` selected via `--profile <name>`. |

---

## 3. Precedence Rules

1. **CLI flags** always take highest precedence (e.g. `--format bin`, `--strip`, `-x test`).
2. **Active profile** (`--profile <name>`) overrides `hive.json` top-level defaults.
3. **`hive.json`** overrides `build.zig.zon` fallbacks and built-in defaults.
