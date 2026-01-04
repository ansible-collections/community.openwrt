#!/bin/sh
# shellcheck shell=ash
# Copyright (c) 2021 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

init() {
    PARAMS="
        cmd=raw_params=_raw_params/str/r
        uses_shell=_uses_shell/bool//false
        chdir/str
        executable/str
        creates/str
        removes/str
    "
    RESPONSE_VARS="
        start end delta cmd
        stdout/str/a stderr/str/a rc/int/a
    "
    cmd=
    stdout=""
    stderr=""
    start=""
    end=""
    delta=""
    rc="0"
    out="$(mktemp)" && err="$(mktemp)"
}

validate() {
    no_check_mode
    [ -n "$executable" ] || executable="/bin/sh"
}

main() {
    local ts_start ts_end s_delta
    [ -z "$chdir" ] || try cd "$chdir"

    [ -z "$creates" ] || ! ls -d -- "$creates" >/dev/null 2>/dev/null || {
        stdout="skipped, since $creates exists"; exit 0
    }
    [ -z "$removes" ] || ls -d -- "$removes" >/dev/null 2>/dev/null || {
        stdout="skipped, since $removes does not exist"; exit 0
    }

    ts_start="$(date +%s)"
    if [ -z "$uses_shell" ]; then
        echo "$cmd" | xargs sh -c 'exec "$@"' -- >"$out" 2>"$err"
        rc=$?
    else
        "$executable" -c "$cmd" >"$out" 2>"$err"
        rc=$?
    fi
    ts_end="$(date +%s)"
    s_delta=$((ts_end - ts_start))

    start="$(date -d "@$ts_start" "+%Y-%m-%d %H:%M:%S").000000"
    end="$(date -d "@$ts_end" "+%Y-%m-%d %H:%M:%S").000000"
    delta="$(printf "%d:%02d:%02d.000000" $((s_delta / 3600)) $((s_delta % 3600 / 60)) $((s_delta % 60)))"
    stdout="$(cat "$out")"
    stderr="$(cat "$err")"
    changed
    test "$rc" -eq 0 || fail "non-zero return code"
    return 0
}

cleanup() {
    rm -f -- "$out" "$err"
}
