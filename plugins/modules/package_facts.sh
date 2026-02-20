#!/bin/sh
# shellcheck shell=ash disable=SC3010
# Copyright (c) 2017 Sebastian Guarino
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

NO_EXIT_JSON="1"

add_package_fact() {
    json_add_array "$1"
    json_add_object "o-$1"
    json_add_string name "$1"
    json_add_string source "$ansible_pkg_mgr"
    local version=${2/*: /}
    local release=${version/*-/}
    if [[ "$release" =~ ^r ]]; then
        version="${version/-$release/}"
    else
        release=""
    fi
    json_add_string release "$release"
    json_add_string version "$version"
    json_close_object
    json_close_array
}

detect_package_management() {
    if which apk > /dev/null 2>&1; then
        ansible_pkg_mgr="apk"
    elif which opkg > /dev/null 2>&1; then
        ansible_pkg_mgr="opkg"
    fi
}

main() {
    detect_package_management
    json_set_namespace package_facts
    json_init
    set -o pipefail
    if [ "$ansible_pkg_mgr" = "apk" ]; then
        _output=$(apk query --fields name,version --installed \*  2> /dev/null | grep -v '^$' | sed -e 'N;s/Name: \([^ ]*\)\nVersion: \([^ ]*\)/\1,\2/')
    elif [ "$ansible_pkg_mgr" = "opkg" ] ; then
        _output=$(opkg list-installed 2>/dev/null | sed -e 's/ - /,/')
    fi
    $_rc=$?
    if [ "$_rc" == 0 ]; then
        json_add_object ansible_facts
        json_add_object packages
        for line in $_output; do
            package=${line/,*/}
            version=${line/*,/}
            add_package_fact "$package" "$version"
        done
        json_close_object
        json_close_object
    else
        json_add_string msg "Error retrieving package listing (package manager detected: $ansible_pkg_mgr)"
        json_add_boolean failed $([ $_rc -eq 0 ]; echo $?)
    fi
    result="$(json_dump)"
    json_cleanup
    echo "${result}"

}

[ -n "$_ANSIBLE_PARAMS" ] || main
