#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2025 Krzysztof Bialek/Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

PARAMS="
    name=pkg/str/r
    state/str//present
    update_cache/bool
    no_cache/bool
    force_broken_world/bool
"

query_package() {
    # apk info returns 0 if installed, 1 if not
    apk info -e "$1" >/dev/null 2>&1
}

install_packages() {
    local _IFS pkg pkgs_to_install
    _IFS="$IFS"; IFS=","; set -- $name; IFS="$_IFS"
    
    for pkg; do
        query_package "$pkg" || pkgs_to_install="$pkgs_to_install $pkg"
    done

    [ -n "$pkgs_to_install" ] || return 0

    [ -n "$_ansible_check_mode" ] || {
        # shellcheck disable=SC2086
        try apk add $update_cache $no_cache $force_broken_world $pkgs_to_install
        # Verify installation
        for pkg in $pkgs_to_install; do
            query_package "$pkg" || fail "failed to install $pkg: $_result"
        done
    }
    changed
}

remove_packages() {
    local _IFS pkg pkgs_to_remove
    _IFS="$IFS"; IFS=","; set -- $name; IFS="$_IFS"

    for pkg; do
        query_package "$pkg" && pkgs_to_remove="$pkgs_to_remove $pkg"
    done

    [ -n "$pkgs_to_remove" ] || return 0

    [ -n "$_ansible_check_mode" ] || {
        # shellcheck disable=SC2086
        try apk del $no_cache $pkgs_to_remove
        # Verify removal
        for pkg in $pkgs_to_remove; do
            ! query_package "$pkg" || fail "failed to remove $pkg: $_result"
        done
    }
    changed
}

main() {
    case "$state" in
        present|installed|absent|removed) :;;
        *) fail "state must be present or absent";;
    esac

    [ -z "$update_cache" ] || update_cache="--update-cache"
    [ -z "$no_cache" ] || no_cache="--no-cache"
    [ -z "$force_broken_world" ] || force_broken_world="--force-broken-world"

    case "$state" in
        present|installed) install_packages;;
        absent|removed) remove_packages;;
    esac
}