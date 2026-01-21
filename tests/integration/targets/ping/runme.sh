#!/usr/bin/env bash
# Copyright (c) 2026 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

export SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$OUTPUT_DIR/../../../utils/runme.sh" "$(basename "$SCRIPT_DIR")" "$@"
