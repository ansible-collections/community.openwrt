#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2025 Krzysztof Bialek/Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

query_package() {
    # apk info returns 0 if installed, 1 if not
    apk info -e "$1" >/dev/null 2>&1
}

install_packages() {
    local _IFS pkg pkgs_to_install
    # shellcheck disable=SC2154,SC2086
    { _IFS="$IFS"; IFS=","; set -- $name; IFS="$_IFS"; }

    for pkg; do
        query_package "$pkg" || pkgs_to_install="$pkgs_to_install $pkg"
    done

    [ -n "$pkgs_to_install" ] || return 0

    [ -n "$_ansible_check_mode" ] || {
        # shellcheck disable=SC2086
        apk $update_cache $no_cache $force_broken_world add $pkgs_to_install >"$out" 2>"$err"
        rc=$?
        stdout="$(cat "$out")"
        stderr="$(cat "$err")"
        # Verify installation
        for pkg in $pkgs_to_install; do
            query_package "$pkg" || fail "failed to install $pkg: $stdout $stderr"
        done
    }
    changed
}

remove_packages() {
    local _IFS pkg pkgs_to_remove
    # shellcheck disable=SC2154,SC2086
    { _IFS="$IFS"; IFS=","; set -- $name; IFS="$_IFS"; }

    for pkg; do
        query_package "$pkg" && pkgs_to_remove="$pkgs_to_remove $pkg"
    done

    [ -n "$pkgs_to_remove" ] || return 0

    [ -n "$_ansible_check_mode" ] || {
        # shellcheck disable=SC2086
        apk $no_cache del $pkgs_to_remove >"$out" 2>"$err"
        rc=$?
        stdout="$(cat "$out")"
        stderr="$(cat "$err")"
        # Verify removal
        for pkg in $pkgs_to_remove; do
            ! query_package "$pkg" || fail "failed to remove $pkg: $stdout $stderr"
        done
    }
    changed
}

init() {
    PARAMS="
        name=pkg/str/r
        state/str//present
        update_cache/bool
        no_cache/bool
        force_broken_world/bool
    "
    RESPONSE_VARS="
        stdout/str/a
        stderr/str/a
        rc/int/a
    "

    stdout=""
    stderr=""
    rc="0"
    out="$(mktemp)"
    err="$(mktemp)"
}

validate() {
    # shellcheck disable=SC2154
    case "$state" in
        present|installed|absent|removed) :;;
        *) fail "state must be present or absent";;
    esac

    if [ -n "$update_cache" ] && [ -n "$no_cache" ]; then
        fail "update_cache and no_cache parameters are mutually exclusive"
    fi
}

main() {
    [ -z "$update_cache" ] || update_cache="--update-cache"
    [ -z "$no_cache" ] || no_cache="--no-cache"
    [ -z "$force_broken_world" ] || force_broken_world="--force-broken-world"

    case "$state" in
        present|installed) install_packages;;
        absent|removed) remove_packages;;
    esac
}
