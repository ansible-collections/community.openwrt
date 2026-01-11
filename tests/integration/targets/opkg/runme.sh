#!/usr/bin/env bash
# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

[ "${DEBUG:-}" != "" ] && set -x

export CLI_VERBOSITY="${1:-}"
export OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$OUTPUT_DIR/../../../../" && pwd)"

# shellcheck disable=SC2155
export TEST_TARGET_NAME="$(basename "$SCRIPT_DIR")"

source virtualenv.sh
pip install molecule 'molecule-plugins[docker]'
[ -x /usr/bin/docker ] || {
    sudo apt-get update && sudo apt-get install -y docker.io
}

# shellcheck disable=SC2164
cd "$REPO_ROOT"
pytest -s tests/utils/integration/tests
