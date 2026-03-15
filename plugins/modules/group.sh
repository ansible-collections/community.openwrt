#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2026 Sebastian Hamann
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

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
    return 0
}

get_group_lineno() {
    # Print the line number (starting at 1) of the given group in /etc/group.
    # Print nothing and return 1 if the group does not exists.
    local group_name="$1"
    i=0
    while read -r line; do
        let i++
        [ "$(echo "${line}" | cut -d: -f1)" = "${group_name}" ] && { echo "${i}"; return 0; }
    done < /etc/group
    return 1
}

group_exists() {
    # Return 0 if the group exists, 1 if it does not.
    [ -n "${_group_lineno}" ]
}

get_users_with_primary_group() {
    # Print the names of all users that have the given group as their primary group.
    local group_name="$1"
    local group_id
    group_id="$(sed -n -e "${_group_lineno}p" /etc/group | cut -d: -f3)"
    while read -r line; do
        [ "$(echo "${line}" | cut -d: -f4)" = "${group_id}" ] && echo "${line}" | cut -d: -f1
    done < /etc/passwd
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
    # shellcheck disable=SC2154  # module parameter
    if group_exists; then
        changed
        if [ -n "${_ansible_check_mode}" ]; then
            exit 0
        fi
        if [ "${force}" != 1 ]; then
            local first_user_with_group
            first_user_with_group="$(get_users_with_primary_group "${name}" | head -n1)"
            if [ -n "${first_user_with_group}" ]; then
                fail "cannot remove the primary group of user '${first_user_with_group}'"
            fi
        fi
        # Delete the group from /etc/group
        sed -i -e "${_group_lineno}d" /etc/group
    fi
}

group_add() {
    if ! group_exists; then
        changed
        # shellcheck disable=SC2154  # module parameter
        if [ -z "${gid}" ]; then
            # No user-supplied gid. Find the first unused gid.
            if [ "${system}" = 1 ]; then
                # Note: Several OpenWrt packages add a group with a fixed ID.
                # 600 was chosen so that ID collision with packages are unlikely.
                [ -z "${gid_min}" ] && gid_min=600
                [ -z "${gid_max}" ] && gid_max=1000
            else
                [ -z "${gid_min}" ] && gid_min=1000
                [ -z "${gid_max}" ] && gid_max=65535
            fi
            gid="$(get_unused_gid "${gid_min}" "${gid_max}")"
            [ -z "${gid}" ] && fail "no unused GID found between ${gid_min} and ${gid_max}"
        elif [ "${non_unique}" != 1 ]; then
            # Check if a group with the chosen gid exists.
            gr_name="$(grep -F ":${gid}:" /etc/group | cut -d: -f1)"
            [ -n "${gr_name}" ] && fail "GID '${gid}' already exists with group '${gr_name}'"
        fi
        if [ -n "${_ansible_check_mode}" ]; then
            exit 0
        fi
        # Add the new group.
        try sed -i -e "\$a ${name}:x:${gid}:" /etc/group
    else
        [ -z "${gid}" ] && return 0
        if [ "${non_unique}" != 1 ]; then
            # Check if a group with the given GID but a different name exists.
            while read -r line; do
                if [ "$(echo "${line}" | cut -d: -f3)" = "${gid}" ]; then
                    gr_name="$(echo "${line}" | cut -d: -f1)"
                    if [ "${name}" != "${gr_name}" ]; then
                        fail "GID '${gid}' already exists with group '${gr_name}'"
                    else
                        break
                    fi
                fi
            done < /etc/group
        fi
        old_gid="$(sed -n -e "${_group_lineno}p" /etc/group | cut -d: -f3)"
        [ "${gid}" != "${old_gid}" ] && changed
        if [ -n "${_ansible_check_mode}" ] || [ "${gid}" = "${old_gid}" ]; then
            exit 0
        fi
        # Change the GID.
        try sed -i -e "${_group_lineno}s/.*:x:([0-9]+):/${name}:x:${gid}:/" /etc/group
    fi
}

validate() {
    # shellcheck disable=SC2154  # module parameter
    case "$state" in
        present|installed|absent|removed) :;;
        *) fail "state must be present or absent";;
    esac

    if [ "${state}" = present ] && [ -z "${gid}" ] && [ "${non_unique}" = 1 ]; then
        fail "non_unique is True but all of the following are missing: gid"
    fi
}

main() {
    # shellcheck disable=SC2154  # module parameter
    _group_lineno="$(get_group_lineno "${name}")"
    # shellcheck disable=SC2154  # module parameter
    case "${state}" in
        absent) group_del ;;
        present) group_add ;;
    esac
}
