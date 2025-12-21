#!/usr/bin/env bash

set -uo pipefail
[ "${DEBUG:-}" != "" ] && set -x

verboses="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_DIR="$SCRIPT_DIR"
SCENARIO="${MOLECULE_SCENARIO:-default}"
export OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"
MOL_DIR="$ROOT/molecule"
rc=0

echo SCRIPT_DIR="$SCRIPT_DIR"
echo ROOT="$ROOT"
echo TARGET_DIR="$TARGET_DIR"

source virtualenv.sh

pip install molecule 'molecule-plugins[docker]'

[ -x /usr/bin/docker ] || {
    sudo apt-get update && sudo apt-get install -y docker.io
}

cleanup() {
    rc=$?
    rm -rf "$MOL_DIR" || true
    exit $rc
}
trap cleanup EXIT

if ! command -v molecule >/dev/null 2>&1; then
    echo "Error: 'molecule' not found in PATH; ensure molecule is installed in CI environment" >&2
    exit 1
fi

if [ ! -d "$TARGET_DIR/molecule" ]; then
    echo "Error: missing per-target molecule scenario: $TARGET_DIR/molecule" >&2
    exit 1
fi

cp -a "$TARGET_DIR/molecule" "$MOL_DIR"

if [ -d "$TARGET_DIR/tasks" ]; then
    mkdir -p "$ROOT/tasks"
    cp -a "$TARGET_DIR/tasks/." "$ROOT/tasks/"
    echo "Copied per-target tasks into repo tests/tasks: $ROOT/tasks"
fi

# shellcheck disable=SC2086
molecule $verboses test -s "$SCENARIO"
