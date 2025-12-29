#!/usr/bin/env bash
#
# Entry-point used by ansible-test integration
#
# Here it triggers pytest which uses pytest-ansible/molecule fixtures
#

set -uo pipefail
[ "${DEBUG:-}" != "" ] && set -x

export CLI_VERBOSITY="${1:-}"

export OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.4}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../../../../../../" && pwd)"

export TEST_TARGET_NAME="$(basename "$SCRIPT_DIR")"

(cd "$REPO_ROOT"; pytest -s tests/utils/integration/tests )
