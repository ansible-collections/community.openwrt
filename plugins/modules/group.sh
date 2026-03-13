#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2026 Sebastian Hamann
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

init() {
    PARAMS="
        name/str/r
        gid/int
        gid_max/int
        gid_min/int
        state/str//present
        force/bool//false
        system/bool//false
        non_unique/bool//false
    "
    RESPONSE_VARS="
        gid/int
        name/str
        state/str
        system/bool
    "
    GID_MIN_REGULAR=1000
    GID_MAX_REGULAR=65535
    # Note: Several OpenWrt packages add a group with a fixed ID.
    # 600 was chosen so that ID collision with packages are unlikely.
    GID_MIN_SYSTEM=600
    GID_MAX_SYSTEM=999
    return 0
}

get_gid_by_name() {
    # Print the GID of the group with the given name.
    # Print nothing and return 1 of the group does not exist.
    local group_name="$1"
    awk -F: "\$1 == \"${group_name}\" { print \$3 }" /etc/group
}

group_exists() {
    # Return 0 if the group exists, 1 if it does not.
    local group_name="$1"
    grep -q "^${group_name}:" /etc/group
}

get_users_with_primary_group() {
    # Print the names of all users that have the given group as their primary group.
    local group_name="$1"
    local group_id
    group_id="$(get_gid_by_name "${group_name}")"
    awk -F: "\$4 == ${group_id} { print \$1 }" /etc/passwd
}

get_unused_gid() {
    # Print the first gid that is not already in use by an existing group,
    # and is between the given lower and upper bound.
    local gid_min="$1"
    local gid_max="$2"
    local used_gids
    used_gids="$(cut -d: -f3 /etc/group)"
    for gid in $(seq "${gid_min}" "${gid_max}"); do
        echo "${used_gids}" | grep -qxF "${gid}" || { echo "${gid}"; return 0; }
    done
    return 1
}

group_del() {
    if group_exists "${name}"; then
        changed
        if [ -n "${_ansible_check_mode}" ]; then
            return 0
        fi
        if [ "${force}" != 1 ]; then
            local first_user_with_group
            first_user_with_group="$(get_users_with_primary_group "${name}" | head -n1)"
            if [ -n "${first_user_with_group}" ]; then
                fail "cannot remove the primary group of user '${first_user_with_group}'"
            fi
        fi
        # Delete the group from /etc/group
        try sed -i -e "/^${name}:/d" /etc/group
    fi
}

group_add() {
    if ! group_exists "${name}"; then
        changed
        if [ -z "${gid}" ]; then
            # No user-supplied gid. Find the first unused gid.
            if [ "${system}" = 1 ]; then
                [ -z "${gid_min}" ] && gid_min="${GID_MIN_SYSTEM}"
                [ -z "${gid_max}" ] && gid_max="${GID_MAX_SYSTEM}"
            else
                [ -z "${gid_min}" ] && gid_min="${GID_MIN_REGULAR}"
                [ -z "${gid_max}" ] && gid_max="${GID_MAX_REGULAR}"
            fi
            gid="$(get_unused_gid "${gid_min}" "${gid_max}")"
            [ -z "${gid}" ] && fail "no unused GID found between ${gid_min} and ${gid_max}"
        elif [ "${non_unique}" != 1 ]; then
            # Check if a group with the chosen gid exists.
            gr_name="$(grep -F ":${gid}:" /etc/group | cut -d: -f1)"
            [ -n "${gr_name}" ] && fail "GID '${gid}' already exists with group '${gr_name}'"
        fi
        if [ -n "${_ansible_check_mode}" ]; then
            return 0
        fi
        # Add the new group.
        try sed -i -e "\$a ${name}:x:${gid}:" /etc/group
    else
        [ -z "${gid}" ] && return 0
        if [ "${non_unique}" != 1 ]; then
            # Check if a group with the given GID but a different name exists.
            gr_name="$(awk -F: "\$3 == ${gid} && \$1 != \"${name}\" { print \$1 }" /etc/group | tr $'\n' ', ')"
            if [ -n "${gr_name}" ]; then
                fail "GID '${gid}' already exists with group '${gr_name}'"
            fi
        fi
        old_gid="$(get_gid_by_name "${name}")"
        [ "${gid}" != "${old_gid}" ] && changed
        if [ -n "${_ansible_check_mode}" ] || [ "${gid}" = "${old_gid}" ]; then
            return 0
        fi
        # Change the GID.
        try sed -i -e "s/${name}:x:([0-9]+):/${name}:x:${gid}:/" /etc/group
    fi
}

validate() {
    case "$state" in
        present|installed|absent|removed) :;;
        *) fail "state must be present or absent";;
    esac

    if [ "${state}" = present ] && [ -z "${gid}" ] && [ "${non_unique}" = 1 ]; then
        fail "non_unique is \`true\` but all of the following are missing: gid"
    fi
}

main() {
    case "${state}" in
        absent) group_del ;;
        present) group_add ;;
    esac
}
