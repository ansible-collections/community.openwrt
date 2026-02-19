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
    read now year month day hour minute second weekday weekday_number weeknumber tz tz_offset <<EOF
        $(date +"%s %Y %m %d %H %M %S %A %w %W %Z %z")
EOF
    read utcnow uyear umonth uday uhour uminute usecond <<EOF
        $(date -u +"%s %Y %m %d %H %M %S" -d "@$now")
EOF

    date="$year-$month-$day"
    time="$hour:$minute:$second"

    iso8601="$year-$month-$day"T"$hour:$minute:$second"Z
    iso8601_micro="$iso8601"
    iso8601_micro="${iso8601_micro%Z}.000000Z"

    # I'd think we have to use uyear, umonth, ... here, but then it gives different results for me!?
    iso8601_basic="${year}${month}${day}T${hour}${minute}${second}000000"
    iso8601_basic_short="${year}${month}${day}T${hour}${minute}${second}"

    epoch="$now"
    epoch_int="$now"
    tz_dst=$"tz"
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
