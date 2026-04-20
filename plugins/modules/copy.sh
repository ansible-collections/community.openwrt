#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

PARAMS="
    backup/bool
    dest/str/r
    directory_mode/str
    force=thirsty/bool//true
    original_basename=_original_basename/str
    src/str
    validate/str
    _diff_max_bytes/int//104448
    $FILE_PARAMS
"
RESPONSE_VARS="src dest md5sum=md5sum_src checksum backup_file"

init() {
    export md5sum_src=""
    export checksum=""
    export backup_file=""
}

validate()  {
    [ -e "$src" ] || fail "Source $src not found"
    [ -r "$src" ] || fail "Source $src not readable"
    [ ! -d "$src" ] || fail "Remote copy does not support recursive copy of directory: $src"
}

main() {
    local tmp _IFS

    checksum_src="$(dgst sha1 "$src")" || :
    md5sum_src="$(md5 "$src")"
    md5sum_dest=""

    [ -z "$original_basename" -o "${dest%/}" = "$dest" ] || {
        dest="$dest/$original_basename"
        tmp="$(dirname -- "$dest")"
        [ -d "$tmp" ] || {
            _IFS="$IFS"; IFS="/"; set -- $tmp; IFS="$_IFS"
            tmp="$mode"; mode="$directory_mode"
            local d
            local p=""
            for d; do
                [ -n "$d" ] || continue
                p="$p/$d"
                [ ! -d "$p" ] || continue
                try mkdir "$p"
                set_file_attributes "$p"
            done
            mode="$tmp"
        }
    }

    [ ! -d "$dest" ] || {
        dest="${dest%/}"
        [ -z "$original_basename" ] &&
            dest="$dest/$(basename -- "$src")" ||
            dest="$dest/$original_basename"
    }

    tmp="$(dirname -- "$dest")"
    [ -e "$dest" ] && {
        [ ! -h "$dest" -o -z "$follow" ] || dest="$(realpath "$dest")"
        [ -n "$force" ] || { unchanged; succeed "file already exists"; }
        [ ! -r "$dest" ] || md5sum_dest="$(md5 "$dest")"
    } || [ -d "$tmp" ] || fail "Destination directory $tmp does not exist"
    [ -w "$tmp" ] || fail "Destination $tmp not writeable"

    [ "$md5sum_src" = "$md5sum_dest" -a ! -h "$dest" ] || {
        [ -z "$_ansible_diff" ] || {
            _diff_before=""
            _diff_after=""
            _src_size="$(wc -c < "$src" 2>/dev/null || echo 0)"
            _dst_size=0
            [ ! -e "$dest" ] || [ ! -r "$dest" ] || _dst_size="$(wc -c < "$dest" 2>/dev/null || echo 0)"
            if [ "$_src_size" -gt "$_diff_max_bytes" ] || [ "$_dst_size" -gt "$_diff_max_bytes" ]; then
                _diff_before="[diff skipped: file larger than $_diff_max_bytes bytes]"
                _diff_after="$_diff_before"
            else
                [ "$_dst_size" = 0 ] || _diff_before="$(cat -- "$dest")"
                _diff_after="$(cat -- "$src")"
            fi
            set_diff "$_diff_before" "$_diff_after" "$dest" "$dest"
        }
        [ -n "$_ansible_check_mode" ] || {
            [ -z "$backup" ] || backup_file="$(backup_local "$dest")"
            [ ! -h "$dest" ] || { rm -f -- "$dest"; touch -- "$dest"; }
            [ -z "$validate" ] || {
                [ "${validate/%s/}" != "$validate" ] ||
                    fail "validate must contain %s: $validate"
                tmp="$($(printf "$validate" "$src") 2>&1)" ||
                    fail "failed to validate: $tmp"
            }
            try 'cat -- "$src" > "$dest"'
        }
        changed
    }

    [ -n "$_ansible_check_mode" ] || set_file_attributes "$dest"
}
