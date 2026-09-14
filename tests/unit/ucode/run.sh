#!/usr/bin/env bash
# Copyright (c) 2026 Vladimir Ermakov
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# Run the ucode unit tests (tests/unit/ucode/*.uc) inside an OpenWrt container,
# using the container's real `ucode` (25.12.x). The shared helper library is
# staged next to each test script, mirroring how the runtime action plugin ships
# it next to a module.

set -euo pipefail

OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.4}"
IMAGE="ghcr.io/openwrt/rootfs:x86_64-${OPENWRT_VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' EXIT

cp "${REPO_ROOT}/plugins/module_utils/_ansible_common.uc" "${stage_dir}/"
cp "${SCRIPT_DIR}"/test_*.uc "${stage_dir}/"

failed=0
for testfile in "${SCRIPT_DIR}"/test_*.uc; do
    name="$(basename "${testfile}")"
    echo "=== ${name} ==="
    docker run --rm -v "${stage_dir}:/t" -v "${testfile}:${stage_dir}/${name}:ro" \
        --entrypoint ucode "${IMAGE}" "/t/${name}" \
        || { echo "FAILED: ${name}"; failed=1; }
done

exit "${failed}"