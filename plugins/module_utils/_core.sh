# shellcheck shell=ash
# Copyright (c) 2017 Markus Weippert
# Copyright (c) 2026, Alexei Znamensky
# GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

# Core shell framework for community.openwrt modules.
# Sourced by wrapper.sh on every module execution.
# Provides:
#   parameter parsing (JSON and legacy)
#   exit/result handling
#   check mode support
#   diff support
#   control flow helpers (changed, fail, succeed, try, final)

_ANSIBLE_PARAMS="
    _ansible_version/s
    _ansible_no_log/b
    _ansible_module_name/s
    _ansible_syslog_facility/s
    _ansible_socket/s
    _ansible_verbosity/i
    _ansible_diff/b
    _ansible_debug/b
    _ansible_check_mode/b
"
CHANGED=""
FACT_VARS=""
JSON_PREFIX=""
MESSAGE=""
NO_EXIT_JSON=""
PARAMS=""
RESPONSE_VARS=""
SKIPPED=""
SUPPORTS_CHECK_MODE="1"

N="
"
T="	"

init() { :; }
validate() { :; }
main() { :; }
cleanup() { :; }

_exit_add_vars() {
    local _var _name _type _always _value _IFS
    for _var; do
        _IFS="$IFS"; IFS="/"; set -- $_var; IFS="$_IFS"
        _var="$1"; _type="$(_map_type "$2")"; _always="$3"
        _IFS="$IFS"; IFS="="; set -- $_var; IFS="$_IFS"
        _name="$1"; _var="${2:-$_name}"
        eval "_value=\"\$$_var\""
        [ -z "$_value" -a -z "$_always" ] ||
            eval "json_add_$_type \"\$_name\" \"\$_value\""
    done
}

_init_done=""
_exit() {
    local _rc="$?"
    local _v _k
    [ -z "$_init_done" ] || cleanup "$_rc" || :
    [ -z "$NO_EXIT_JSON" ] || return $_rc
    json_set_namespace result
    json_add_boolean changed $([ -z "$CHANGED" ]; echo $?)
    json_add_boolean failed $([ $_rc -eq 0 ]; echo $?)
    [ -z "$SKIPPED" ] || json_add_boolean skipped 1
    [ -z "$MESSAGE" ] || json_add_string msg "$MESSAGE"
    [ -z "$_init_done" ] || {
        [ -z "$RESPONSE_VARS" ] || _exit_add_vars $RESPONSE_VARS
        [ -z "$FACT_VARS" ] || {
            json_add_object ansible_facts
            _exit_add_vars "$FACT_VARS"
            json_close_object
        }
    }
    [ -z "$_ansible_diff" -o -z "$_diff_set" ] || {
        json_add_object diff
        json_add_string before "$_diff_before${_diff_before:+$N}"
        json_add_string after "$_diff_after${_diff_after:+$N}"
        [ -z "$_diff_before_header" ] ||
            json_add_string before_header "$_diff_before_header"
        [ -z "$_diff_after_header" ] ||
            json_add_string after_header "$_diff_after_header"
        json_close_object
    }
    echo; json_dump
    json_cleanup
    return $_rc
}
trap _exit EXIT

_map_type() {
    [ -n "$1" ] || { echo "string"; return 0; }
    case "$1" in
        any) echo "any";;
        s|str|string) echo "string";;
        i|int|integer) echo "int";;
        b|bool|boolean) echo "boolean";;
        f|d|float|double) echo "double";;
        l|a|list|array) echo "array";;
        o|h|obj|object|hash|map) echo "object";;
        *) fail "unknown type: $1";;
    esac
}

_verify_value_type() {
    local _value="$1"
    local _type="$2"
    case "$_type" in
        int) printf "%d" "$_value" >/dev/null 2>&1 || return 1;;
        double) printf "%f" "$_value" >/dev/null 2>&1 || return 1;;
        boolean)
            case "$_value" in
                yes|true|True|1) _value="1";;
                no|false|False|0) _value="";;
                *) return 1;;
            esac;;
    esac
    echo "$_value"
}

_parse_legacy_params() {
    local _var _type _required _default _alias
    local _param _value _IFS
    for _param in $PARAMS; do
        eval "${_param%%[/=]*}=\"\""
    done
    eval "$(cat "$_params")" || fail "could not parse params"
    for _param in $PARAMS $_ANSIBLE_PARAMS; do
        _value=""; _IFS="$IFS"; IFS="/"; set -- $_param; IFS="$_IFS"
        _var="$1"; _type="$(_map_type "$2")"; _required="$3"; _default="$4"
        _IFS="$IFS"; IFS="="; set -- $_var; IFS="$_IFS"; _var="$1"
        for _alias; do
            eval "_value=\"\$$_alias\""
            [ -z "$_value" ] || break
        done
        eval "export -- _orig_$_var=\"\$_value\""
        [ -z "$_value" ] && {
            [ -z "$_required" ] || fail "$_var is required"
            [ -z "$_default" ] ||
                _value="$(_verify_value_type "$_default" "$_type")"
        } || {
            _value="$(_verify_value_type "$_value" "$_type")" ||
                fail "$_var must be $_type"
        }
        eval "export -- $_var=\"\$_value\" _type_$_var=\"\$_type\""
    done
    return 0
}

_parse_json_params() {
    local _var _type _required _default _alias
    local _param _value _found _is_type _IFS
    json_set_namespace params
    json_load "$(cat -- "$_params")" || fail "could not parse params"
    for _param in $PARAMS $_ANSIBLE_PARAMS; do
        _value=""; _IFS="$IFS"; IFS="/"; set -- $_param; IFS="$_IFS"
        _var="$1"; _type="$(_map_type "$2")"; _required="$3"; _default="$4"
        _IFS="$IFS"; IFS="="; set -- $_var; IFS="$_IFS"; _var="$1"
        _is_type=""; _found=""
        for _alias; do
            json_get_type _is_type "$_alias" &&
                json_get_var _value "$_alias" ||
                continue
            _found="1"; break
        done
        eval "export -- _orig_$_var=\"\$_value\" _defined_$_var=\"$_found\""
        [ -n "$_found" ] || {
            [ -z "$_required" ] || fail "$_var is required"
            [ -z "$_default" ] ||
                _value="$(_verify_value_type "$_default" "$_type")"
        }
        case "$_is_type" in
            array|object)
                [ "$_type" = "$_is_type" -o "$_type" = "any" ] ||
                    fail "$_var must be $_type"
                eval "export -- _type_${_var}=\"\$_is_type\""
                json_add_string "_$_var" "$_alias";;
            *)
                [ -z "$_found" ] ||
                    _value="$(_verify_value_type "$_value" "$_type")" ||
                    fail "$_var must be $_type"
                eval "export -- $_var=\"\$_value\" _type_$_var=\"\$_type\""
                json_add_string "$_var" "$_value";;
        esac
    done
    return 0
}

_parse_params() {
    [ -n "$WANT_JSON" ] && _parse_json_params || _parse_legacy_params
}

_support_check_mode() {
    [ -n "$_ansible_check_mode" -a -z "$SUPPORTS_CHECK_MODE" ] || return 0
    SKIPPED="1"
    MESSAGE="module does not support check mode"
    exit 0
}

json_select_real() {
    local real_var
    json_get_var real_var "_$1"
    json_select "$real_var"
}

changed() {
    CHANGED="1"
}

unchanged() {
    CHANGED=""
}

succeed() {
    [ -n "$*" ] && MESSAGE="$*"
    exit 0
}

fail() {
    MESSAGE="$*"
    exit 1
}

_result=""
try() {
    [ $# -eq 1 ] && {
        _result="$(eval "$1" 2>&1)" || fail "$*: $_result"
    } || {
        _result="$("$@" 2>&1)" || fail "$*: $_result"
    }
}

final() {
    try "$@"
    exit 0
}

_diff_set=""
_diff_before=""
_diff_after=""
_diff_before_header=""
_diff_after_header=""
set_diff() {
    _diff_before="${1:-$_diff_before}"
    _diff_after="${2:-$_diff_after}"
    _diff_before_header="${3:-$_diff_before_header}"
    _diff_after_header="${4:-$_diff_after_header}"
    _diff_set="1"
}
