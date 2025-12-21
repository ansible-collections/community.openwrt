#!/usr/bin/env bash

set -euo pipefail
[ "${DEBUG:-}" != "" ] && set -x

verboses="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_DIR="$SCRIPT_DIR"
SCENARIO="${MOLECULE_SCENARIO:-default}"
export OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"
MOL_DIR="$ROOT/molecule"
created_copy=0

echo SCRIPT_DIR="$SCRIPT_DIR"
echo ROOT="$ROOT"
echo TARGET_DIR="$TARGET_DIR"

source virtualenv.sh

pip install molecule 'molecule-plugins[docker]'

[ -x /usr/bin/docker ] || {
    sudo apt-get update && sudo apt-get install -y docker.io
}

cleanup() {
    if [ "$created_copy" = "1" ] && [ -d "$MOL_DIR" ]; then
        rm -rf "$MOL_DIR" || true
    fi
}
trap cleanup EXIT

if [ ! -d "$TARGET_DIR/molecule" ]; then
    echo "Error: missing per-target molecule scenario: $TARGET_DIR/molecule" >&2
    exit 1
fi

cp -a "$TARGET_DIR/molecule" "$MOL_DIR"
created_copy=1

if [ -d "$TARGET_DIR/tasks" ]; then
    mkdir -p "$ROOT/tasks"
    cp -a "$TARGET_DIR/tasks/." "$ROOT/tasks/"
    echo "Copied per-target tasks into repo tests/tasks: $ROOT/tasks"
fi

if ! command -v molecule >/dev/null 2>&1; then
    echo "Error: 'molecule' not found in PATH; ensure molecule is installed in CI environment" >&2
    exit 1
fi

# shellcheck disable=SC2086
molecule $verboses test -s "$SCENARIO"
rc=$?
cleanup
exit $rc
