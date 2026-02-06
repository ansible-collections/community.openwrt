#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2026 Ilya Bogdanov
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

PARAMS="
    path/str//
    prefix/str//ansible
    state/str//file
"

RESPONSE_VARS="path"

main() {
    local mktemp_cmd="mktemp"
    case "${state}" in
        file) : ;;
        directory) mktemp_cmd="${mktemp_cmd} -d" ;;
        *) fail "unknown state option";;
    esac
    if [ -z "${path}" ]; then
        path="/tmp"
    fi
    mktemp_cmd="${mktemp_cmd} -p ${path}"
    if [ -n "${prefix}" ]; then
        mktemp_cmd="${mktemp_cmd} ${prefix}XXXXXX"
    fi
    if [ -n "${_ansible_check_mode}" ]; then
        changed
        return
    fi
    {
        IFS=$'\n\027' read -r -d $'\027' stderr;
        IFS=$'\n\027' read -r -d $'\027' stdout;
    } <<EOF
$( (printf $'\027%s\027' "$(${mktemp_cmd})" 1>&2) 2>&1)
EOF
    if [ -z "${stdout}" ]; then
        unset path
        fail "${stderr}"
    fi
    changed
    path="${stdout}"
}
