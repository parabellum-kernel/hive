# Improvement 001: `publish` (`publish-github`) Practical Refinements

## Context

During manual release publishing across `engine`, `sdk`, `driver`, `extension`, and `vault`, three practical gaps were identified against [docs/goals/publish.md](../goals/publish.md).

## 1. Decoupled Target GitHub Repository (`owner/repo`)

Private source repositories (such as `engine`) publish their compiled binaries to a separate public distribution repository (`parabellum-kernel/sdk`).

- **Requirement**: `publish-github` must resolve the destination `owner/repo` from the selected `repositories` entry in `hive.json` (rather than assuming the current Git `origin` remote).
- **Example**: `engine/hive.json` can declare a `github` repository pointing to `parabellum-kernel/sdk`, so `hive publish` from `engine` uploads `libparabellum_host`, `parabellum`, and `parabellum-engine` to `parabellum-kernel/sdk` releases.

## 2. Asset Naming & Granularity (`raw binaries` vs `tar.gz`)

The current `publish.md` spec references `<name>-<version>-<target>.tar.gz`, whereas existing CI/CD consumers (e.g. `vidsec/.github/workflows/ci.yml`) download individual target-suffixed binaries without the version in the filename (e.g. `libparabellum_host-linux-x86_64.so`, `libanalyzer-macos-aarch64.dylib`).

- **Requirement**: Support configurable asset packaging in `publish-github` (or `hive.json` repository config):
  - `archive` (default or opt-in): `<name>-<version>-<target>.tar.gz` + `SHA256SUMS.txt`
  - `raw`: individual binaries/libraries with platform suffix (`<artifact>-<os>-<arch>.<ext>`) + `SHA256SUMS.txt`

## 3. Local Authentication Fallback via `gh` CLI

- **Requirement**: In addition to `GITHUB_TOKEN` and `HIVE_GITHUB_TOKEN`, `publish-github` should support falling back to `gh auth token` when the GitHub CLI (`gh`) is installed and authenticated locally, avoiding manual token exports during local releases.
