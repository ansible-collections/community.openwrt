#!/usr/bin/env bash
#
# Entry-point used by ansible-test integration
#
# Here it triggers the molecule test
#

set -uo pipefail
[ "${DEBUG:-}" != "" ] && set -x

verboses="${1:-}"

export OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"
export ANSIBLE_ROLES_PATH
ANSIBLE_ROLES_PATH="$(pwd)"

source virtualenv.sh
pip install molecule 'molecule-plugins[docker]'
[ -x /usr/bin/docker ] || {
    sudo apt-get update && sudo apt-get install -y docker.io
}

# shellcheck disable=SC2086
molecule -c ../config.yml $verboses test
