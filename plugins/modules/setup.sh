#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

init() {
    NO_EXIT_JSON="1"
    DATE_TIME_VARS="
        date/str
        day/str
        epoch/str
        epoch_int/str
        hour/str
        iso8601/str
        iso8601_basic/str
        iso8601_basic_short/str
        iso8601_micro/str
        minute/str
        month/str
        second/str
        time/str
        tz/str
        tz_dst/str
        tz_offset/str
        weekday/str
        weekday_number/str
        weeknumber/str
        year/str
    "
}

set_datetime_vars() {
    local now=$(date +%s)
    local utcnow=$(date -u +%s -d "@$now")

    year=$(date +%Y -d "@$now")
    month=$(date +%m -d "@$now")
    weekday=$(date +%A -d "@$now")
    weekday_number=$(date +%w -d "@$now")
    weeknumber=$(date +%W -d "@$now")
    day=$(date +%d -d "@$now")
    hour=$(date +%H -d "@$now")
    minute=$(date +%M -d "@$now")
    second=$(date +%S -d "@$now")
    epoch=$(date +%s -d "@$now")
    epoch_int=$(date +%s -d "@$now")
    date=$(date +%Y-%m-%d)
    time=$(date +%H:%M:%S)
    iso8601_micro=$(date +%Y-%m-%dT%H:%M:%S.000000Z "@$utcnow")
    iso8601=$(date +%Y-%m-%dT%H:%M:%SZ "@$utcnow")
    iso8601_basic=$(date +%Y%m%dT%H%M%S000000 "@$now")
    iso8601_basic_short=$(date +%Y%m%dT%H%M%S "@$now")
    tz=$(date +%Z)
    tz_dst=$(date +%Z)
    tz_offset=$(date +%z)
}

add_ubus_fact() {
    set -- ${1//!/ }
    ubus list "$2" > /dev/null 2>&1 || return
    local json="$($ubus call "$2" "$3" 2>/dev/null)"
    echo -n "$delimiter\"$1\":$json"
    delimiter=","
}

main() {
    set_datetime_vars
    ubus="/bin/ubus"
    delimiter=","
    echo '{"changed":false,"ansible_facts":'
    dist="OpenWrt"
    dist_version="NA"
    dist_release="NA"
    test -f /etc/openwrt_release && {
        . /etc/openwrt_release
        dist="${DISTRIB_ID:-$dist}"
        dist_version="${DISTRIB_RELEASE:-$dist_version}"
        dist_release="${DISTRIB_CODENAME:-$dist_release}"
    } || test ! -f /etc/os-release || {
        . /etc/os-release
        dist="${NAME:-$dist}"
        dist_version="${VERSION_ID:-$dist_version}"
    }
    dist_major="${dist_version%%.*}"
    json_set_namespace facts
    json_init
    json_add_string ansible_hostname "$(cat /proc/sys/kernel/hostname)"
    json_add_string ansible_distribution "$dist"
    json_add_string ansible_distribution_major_version "$dist_major"
    json_add_string ansible_distribution_release "$dist_release"
    json_add_string ansible_distribution_version "$dist_version"
    json_add_string ansible_os_family OpenWrt
    if which apk > /dev/null 2>&1; then
        json_add_string ansible_pkg_mgr "apk"
    elif which opkg > /dev/null 2>&1; then
        json_add_string ansible_pkg_mgr "opkg"
    fi
    json_add_boolean ansible_is_chroot "$([ -r /proc/1/root/. ] &&
        { [ / -ef /proc/1/root/. ]; echo $?; } ||
        { [ "$(ls -di / | awk '{print $1}')" -eq 2 ]; echo $?; }
        )"
    json_add_object ansible_date_time
    _exit_add_vars $DATE_TIME_VARS
    json_close_object

    dist_facts="$(json_dump)"
    json_cleanup
    json_set_namespace result
    echo "${dist_facts%\}*}"
    for fact in \
            info!system!info \
            devices!network.device!status \
            services!service!list \
            board!system!board \
            wireless!network.wireless!status \
            ; do
        add_ubus_fact "openwrt_$fact"
    done
    echo "$delimiter"'"openwrt_interfaces":{'
    delimiter=""
    for net in $($ubus list); do
        [ "${net#network.interface.}" = "$net" ] ||
            add_ubus_fact "${net##*.}!$net!status"
    done
    echo '}}}'
}

[ -n "$_ANSIBLE_PARAMS" ] || main
