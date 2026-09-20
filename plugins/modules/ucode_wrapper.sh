#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# Ansible scans this file statically before execution: if WANT_JSON is present, args are
# passed as a JSON temp file (path in $1).
WANT_JSON=1

_dir="$(dirname "$0")"

exec ucode -S -L "$_dir/module_utils" "$_dir/module.uc" "$1"
