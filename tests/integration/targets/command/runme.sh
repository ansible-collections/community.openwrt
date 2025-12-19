#!/usr/bin/env bash
# runme for ansible-test integration target: command
# Simplified: run the per-target Molecule scenario via `molecule test`
set -euo pipefail
[ "${DEBUG:-}" != "" ] && set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_DIR="$SCRIPT_DIR"
SCENARIO="${MOLECULE_SCENARIO:-default}"
# OpenWrt version used for this integration test (can be overridden by env)
OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"
export OPENWRT_VERSION
MOL_DIR="$ROOT/molecule"
created_copy=0

source virtualenv.sh

pip install -r ${ROOT}/requirements-test.txt

cleanup() {
    if [ "$created_copy" = "1" ] && [ -d "$MOL_DIR" ]; then
        rm -rf "$MOL_DIR" || true
    fi
}
trap cleanup EXIT

# Use per-target molecule scenario; do not generate metadata here
if [ ! -d "$TARGET_DIR/molecule" ]; then
    echo "Error: missing per-target molecule scenario: $TARGET_DIR/molecule" >&2
    exit 1
fi

cp -a "$TARGET_DIR/molecule" "$MOL_DIR"
created_copy=1
# Copy per-target verify playbook and tasks into the scenario so ephemeral runs find them
if [ -f "$TARGET_DIR/verify.yml" ]; then
    mkdir -p "$MOL_DIR/$SCENARIO"
    cp "$TARGET_DIR/verify.yml" "$MOL_DIR/$SCENARIO/verify.yml"
    echo "Copied per-target verify playbook into scenario: $MOL_DIR/$SCENARIO/verify.yml"
fi
# If the per-target molecule scenario contains a verify playbook, copy that too (handles ephemeral test copies)
if [ ! -f "$MOL_DIR/$SCENARIO/verify.yml" ] && [ -f "$TARGET_DIR/molecule/$SCENARIO/verify.yml" ]; then
    mkdir -p "$MOL_DIR/$SCENARIO"
    cp "$TARGET_DIR/molecule/$SCENARIO/verify.yml" "$MOL_DIR/$SCENARIO/verify.yml"
    echo "Copied molecule scenario verify playbook into scenario: $MOL_DIR/$SCENARIO/verify.yml"
fi
if [ -d "$TARGET_DIR/tasks" ]; then
    mkdir -p "$ROOT/tasks"
    cp -a "$TARGET_DIR/tasks/." "$ROOT/tasks/"
    echo "Copied per-target tasks into repo tests/tasks: $ROOT/tasks"
fi

if ! command -v molecule >/dev/null 2>&1; then
    echo "Error: 'molecule' not found in PATH; ensure molecule is installed in CI environment" >&2
    exit 1
fi

molecule test -s "$SCENARIO"
rc=$?
cleanup
exit $rc
