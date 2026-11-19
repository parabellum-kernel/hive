#!/usr/bin/env bash
set -euo pipefail

# Build (and optionally install) hive on macOS (Apple Silicon / aarch64-macos).
# Usage:
#   ./scripts/build-macos.sh [--target <zig-triple>] [--optimize <mode>] [--install] [--prefix <dir>]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="${HIVE_TARGET:-aarch64-macos}"
OPTIMIZE="${HIVE_OPTIMIZE:-ReleaseSafe}"
DO_INSTALL=0
PREFIX="${HIVE_PREFIX:-$HOME/.local}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --optimize) OPTIMIZE="$2"; shift 2 ;;
        --install) DO_INSTALL=1; shift ;;
        --prefix) PREFIX="$2"; DO_INSTALL=1; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--target <zig-triple>] [--optimize <mode>] [--install] [--prefix <dir>]"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

BUILD_ARGS=("-Doptimize=${OPTIMIZE}")
if [[ "$TARGET" != "native" ]]; then
    BUILD_ARGS+=("-Dtarget=${TARGET}")
fi

echo "==> Building hive for macOS (target=${TARGET}, optimize=${OPTIMIZE})..."
zig build "${BUILD_ARGS[@]}"
echo "==> Built: ${ROOT_DIR}/zig-out/bin/hive"

if [[ "$DO_INSTALL" -eq 1 ]]; then
    echo "==> Installing hive to ${PREFIX}/bin/hive..."
    zig build "${BUILD_ARGS[@]}" --prefix "$PREFIX"
    echo "==> Installed: ${PREFIX}/bin/hive"
    case ":${PATH}:" in
        *":${PREFIX}/bin:"*) ;;
        *) echo "Note: add '${PREFIX}/bin' to your PATH to run 'hive' from any directory." ;;
    esac
fi
