#!/usr/bin/env bash
# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

[ "${DEBUG:-}" != "" ] && set -x

TEST_TARGET_NAME="$1"
CLI_VERBOSITY="${2-}"
case "$CLI_VERBOSITY" in
    -v|-vv|-vvv|-vvvv) :;;
    *) echo "runme.sh: invalid parameter ($CLI_VERBOSITY)" >&2; exit 1 ;;
esac
OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"

export TEST_TARGET_NAME OPENWRT_VERSION

# shellcheck disable=SC2164
cd "$OUTPUT_DIR/../../../../"

source virtualenv.sh
pip install molecule 'molecule-plugins[docker]'
[ -x /usr/bin/docker ] || {
    sudo apt-get update && sudo apt-get install -y docker.io
}

# shellcheck disable=SC2086
molecule $CLI_VERBOSITY test --parallel -s integration_test
