# shellcheck shell=ash
# Copyright (c) 2017 Markus Weippert
# Copyright (c) 2026, Alexei Znamensky
# GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

FILE_PARAMS="group/s mode/s owner/s follow/b"

_get_file_attributes() {
    local R="${2:+Ra}"
    ls -l${R:-d} -- "$1" 2>/dev/null | md5
}

set_file_attributes() {
    [ -z "$_ansible_check_mode" ] || return 0
    [ "$mode" != "False" ] || mode=""
    [ -n "$owner" -o -n "$group" -o -n "$mode" ] || return 0
    local file="$1"
    local R="${2:+-R }"
    local result h
    local before="$(_get_file_attributes "$@")"
    ! result="$(printf "%04o" "$mode" 2>/dev/null)" || mode="$result"
    [ -z "$follow" ] && h="-h " || h=""
    [ -z "$owner" ] || result="$(chown $h$R"$owner" -- "$file" 2>&1)" ||
        fail "chown ($file) failed: $result"
    [ -z "$group" ] || result="$(chgrp $h$R"$group" -- "$file" 2>&1)" ||
        fail "chgrp ($file) failed: $result"
    [ -z "$follow" -a -h "$file" ] ||
        [ -z "$mode" ] || result="$(chmod $R"$mode" -- "$file" 2>&1)" ||
            fail "chmod ($file) failed: $result"
    [ "$before" = "$(_get_file_attributes "$@")" ] || changed
}

is_abs() {
    [ "${1#/}" != "$1" ]
}

abspath() {
    local dir="$(dirname -- "$1")"
    local file="$(basename -- "$1")"
    local P="${2:+ -P}"
    [ -d "$dir" ] && dir="$(cd -- "$dir" && pwd$P)" ||
        is_abs "$dir" || dir="$(pwd$P)/$dir"
    echo "${dir:+$dir/}$file"
}

realpath() {
    local f="$(abspath "$1" x)"
    local tmp
    while [ -h "$f" ]; do
        tmp="$(readlink -- "$f")"
        is_abs "$tmp" || tmp="$(dirname -- "$f")/$tmp"
        f="$(abspath "$tmp" x)"
    done
    echo "$f"
}

backup_local() {
    local src="$1"
    local dest
    [ ! -e "$src" ] || {
        dest="$src.$$.$(date "+%Y-%m-%d@%H:%M:%S~")"
        try cp -a -- "$src" "$dest"
        echo "$dest"
    }
}

dgst() {
    local alg="$1"
    local cmd checksum
    shift
    case "$alg" in
        sha1|sha224|sha256|sha384|sha512|md5)
            cmd="${alg}sum"
            ! type "$cmd" >/dev/null 2>&1 || {
                checksum="$($cmd -- "$@")"
                echo "${checksum%% *}"
                return 0
            }
            ! type openssl >/dev/null 2>&1 || {
                checksum="$(openssl dgst -hex -$alg "$@")"
                echo "${checksum##*= }"
                return 0
            }
            return 1;;
        *) fail "Unknown checksum algorithm '$alg'.";;
    esac
}

md5() {
    dgst md5 "$@"
}

base64() {
    ! which base64 >/dev/null 2>&1 ||
        { try command base64 "$1"; echo "$_result"; return 0; }
    ! type openssl >/dev/null 2>&1 ||
        { try openssl base64 -in "$1"; echo "$_result"; return 0; }
    hexdump -e '16/1 "%02x" "\n"' -- "$1" | awk '
        BEGIN { b64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" }
        { for(c=1; c<=length($0); c++) {
            d=index("0123456789abcdef",substr($0,c,1));
            if(d--) {
              for(b=1; b<=4; b++) {
                o=o*2+int(d/8); d=(d*2)%16;
                if(!(++obc%6)) {
                  line=line""substr(b64,o+1,1); o=0;
                  if(++rc>75) { print line; line=""; rc=0; }
                }
              }
            }
        } }
        END {
          if(obc%6) {
            while(obc++%6) { o=o*2; }
            line=line""substr(b64,o+1,1);
          }
          while(obc%8||obc%6) { if(!(++obc%6)) { line=line"="; } }
          print line;
        }
    '
}
