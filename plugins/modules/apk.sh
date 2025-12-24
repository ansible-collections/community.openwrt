#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2024 Krzysztof Bialek/Markus Weippert
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
        if ! query_package "$pkg"; then
            pkgs_to_install="$pkgs_to_install $pkg"
        fi
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
        if query_package "$pkg"; then
            pkgs_to_remove="$pkgs_to_remove $pkg"
        fi
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

    # Map boolean update_cache to apk flag
    if [ "$update_cache" = "True" ] || [ "$update_cache" = "yes" ]; then
        update_cache="--update-cache"
    else
        update_cache=""
    fi

    # Map no_cache (common in apk)
    if [ "$no_cache" = "True" ] || [ "$no_cache" = "yes" ]; then
        no_cache="--no-cache"
    else
        no_cache=""
    fi

    # Handle force (apk uses --force-broken-world for dependency issues)
    if [ "$force_broken_world" = "True" ] || [ "$force_broken_world" = "yes" ]; then
        force_broken_world="--force-broken-world"
    else
        force_broken_world=""
    fi

    case "$state" in
        present|installed) install_packages;;
        absent|removed) remove_packages;;
    esac
}