#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# Ansible scans this file statically before execution: if WANT_JSON is present, args are
# passed as a JSON temp file (path in $1); otherwise key=value pairs are used instead.
WANT_JSON=1

[ $# -le 1 ] || { _script="$1"; shift; }
_params="$1"

. /usr/share/libubox/jshn.sh

if [ -f "$_params" ]; then
    json_load "$(cat "$_params")"
    [ -n "$_script" ] || {
        json_get_var _temp_script _openwrt_script 2>/dev/null || true
        [ -n "$_temp_script" ] && _script="$_temp_script"
    }
    json_get_type _libs_type _openwrt_libs 2>/dev/null || true
    if [ "$_libs_type" = "array" ]; then
        json_select _openwrt_libs
        _i=1
        while json_get_var _lib "$_i" 2>/dev/null; do
            . "$_lib"
            _i=$((_i + 1))
        done
        json_select ..
    fi
    json_cleanup
fi


json_set_namespace result
json_init
. "$_script"
init || fail "module init failed"
_parse_params
_support_check_mode
validate || fail "module validation failed"
_init_done="1"
main
