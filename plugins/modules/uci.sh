#!/bin/sh
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

[ $# -le 1 ] || { _script="$1"; shift; }
_params="$1"

. /usr/share/libubox/jshn.sh

_ANSIBLE_PARAMS="
    _ansible_version/s _ansible_no_log/b _ansible_module_name/s
    _ansible_syslog_facility/s _ansible_socket/s _ansible_verbosity/i
    _ansible_diff/b _ansible_debug/b _ansible_check_mode/b
"
FILE_PARAMS="group/s mode/s owner/s follow/b"
CHANGED=""
FACT_VARS=""
JSON_PREFIX=""
MESSAGE=""
NO_EXIT_JSON=""
PARAMS=""
RESPONSE_VARS=""
SKIPPED=""
SUPPORTS_CHECK_MODE="1"
WANT_JSON="1"

N="
"
T="	"

init() { :; }
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

json_set_namespace result
json_init
#!/bin/sh
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

WANT_JSON="1"
PARAMS="
    autocommit/bool
    command=cmd/str
    config/str
    find=find_by=search/any
    keep_keys=keep/any
    key/str
    merge/bool//false
    name/str
    option/str
    replace/bool//false
    section/str
    set_find/bool//true
    type/str
    unique/bool//false
    value/any
"
RESPONSE_VARS="result=_result command config section option"

init() {
    state_path=""
    [ -z "$_ansible_check_mode" ] || state_path="$(mktemp -d)" ||
        fail "could not create state path"
    changes="$(uci_change_hash)"
    case "$_type_keep_keys" in
        object) fail "keep_keys must be list or string";;
        array) json_get_values keep_keys "$_keep_keys" || :;;
    esac
    [ -z "$key" ] &&
        key="${config:+$config${section:+.$section${option:+.$option}}}" ||
        { oIFS="$IFS"; IFS="."; set -- $key; IFS="$oIFS"
            config="$1"; section="$2"; option="$3"; }
    [ -z "$_ansible_diff" -o -z "$config" ] ||
        set_diff "$(uci export "$config")"
    [ -n "$command" ] || { [ -z "$value" ] && command="get" || command="set"; }
}

uci() {
    [ -z "$state_path" ] || set -- -P "$state_path" "$@"
    command uci "$@"
}

uci_change_hash() {
    uci changes | md5
}

uci_result_do() {
    json_set_namespace result
    "$@"
    json_set_namespace params
}

uci_get_safe() {
    local tmp opts
    while [ "${1#-}" != "$1" ]; do opts="$opts $1"; shift; done
    tmp="$(uci $opts show "$1")" || return $?
    echo "${tmp#*=}"
}

uci_check_type() {
    local key="$1"; local type="$2"; local t
    t="$(uci -q get "$key")" || return 1
    [ -n "$type" -a "$t" != "$type" ] || return 0
    fail "$key exists with $t instead of $type"
}

uci_compare_list() {
    local k="${1:-$key}"
    local match="1"
    local keys values v i
    json_get_keys keys
    ! values="$(uci_get_safe -q "$k")" || {
        eval "set -- $values"
        for i in $keys; do
            json_get_var v "$i"
            [ $# -gt 0 -a "$v" = "$1" ] || { match=""; break; }
            shift
        done
        [ $# -eq 0 ] || match=""
        [ -z "$match" ] || return 0
    }
    return 1
}

uci_add() {
    section="${section:-$value}"
    [ -n "$name" -o -z "$type" ] || name="$section"
    type="${type:-$section}"
    [ -n "$type" ] || fail "type required for $command"
    [ -n "$name" ] && {
        uci_check_type "$config.$name" "$type" || {
            try uci add "$config" "$type"
            try uci rename "$config.$_result=$name"
        }
    } || try uci add "$config" "$type"
}

uci_set_list() {
    local k="${1:-$key}"
    local keys v i
    ! uci_compare_list "$k" || return 0
    uci -q delete "$k" || :
    json_get_keys keys
    for i in $keys; do
        json_get_var v "$i"
        try uci add_list "$k=$v"
    done
}

uci_set_dict() {
    local keys k v t
    json_get_keys keys
    keep_keys="$keep_keys $keys"
    for k in $keys; do
        json_get_type t "$k"
        case "$t" in
            array)
                json_select "$k"
                uci_set_list "$key.$k"
                json_select ..;;
            object) fail "cannot set $k to dict";;
            *)
                json_get_var v "$k"
                try uci set "$key.$k=$v";;
        esac
    done
}

uci_set() {
    local var="${1:-value}"
    local var_type
    eval "var_type=\"\$_type_$var\""
    [ -z "$option" ] || keep_keys="$keep_keys $option"
    case "$var_type" in
        array)
            [ -n "$config" -a -n "$section" -a -n "$option" ] ||
                fail "config, section and option required for $command"
            json_select_real "$var"
            uci_set_list
            json_select ..;;
        object)
            [ -n "$config" -a -n "$section" -a -z "$option" ] ||
                fail "config and section but not option required for $command"
            json_select_real "$var"
            uci_set_dict
            json_select ..;;
        *) try "uci set \"\$key=\$$var\"";;
    esac
}

uci_get() {
    local entry
    try uci get "$key"
    eval "set -- $(uci_get_safe -q "$key")"
    json_set_namespace result
    json_add_array result_list
    for entry; do json_add_string . "$entry"; done
    json_close_array
    json_set_namespace params
}

uci_find() {
    local keys i c v k tmp
    case "$_type_find" in
        array|object)
            [ -n "$config" -a -n "$type" ] ||
                fail "config and type required for $command"
            json_select_real find
            json_get_keys keys;;
        *)
            [ -n "$config" -a -n "$type" ] &&
                [ -n "$option" -o "$command" = find_all ] ||
                fail "config, type and option required for $command";;
    esac
    [ "$command" != "find_all" ] || uci_result_do json_add_array result
    type="${type:-$section}"
    section=""; i=0
    while [ -n "$(uci -q get "$config.@$type[$i]")" ]; do
        c="@$type[$((i++))]"
        case "$_type_find" in
            array)
                [ -z "$option" ] && {
                    for k in $keys; do
                        json_get_var v "$k"
                        uci -q get "$config.$c.$v" >/dev/null || continue 2
                    done
                } || {
                    uci_compare_list "$config.$c.$option" || continue
                };;
            object)
                for k in $keys; do
                    json_get_type tmp "$k"
                    case "$tmp" in
                        array)
                            json_select "$k"
                            uci_compare_list "$config.$c.$k" &&
                                tmp="1" || tmp=""
                            json_select ..
                            [ -n "$tmp" ] || continue 2;;
                        object)
                            fail "cannot compare $k with dict";;
                        *)
                            json_get_var v "$k"
                            tmp="$(uci -q get "$config.$c.$k")" &&
                                [ "$tmp" = "$v" ] || continue 2
                    esac
                done;;
            *)
                [ -z "$option" ] || {
                    v="$(uci -q get "$config.$c.$option")" &&
                        [ -z "$find" -o "$find" = "$v" ] || continue
                };;
        esac
        [ "$command" = "find_all" ] || { section="$c"; break; }
        uci_result_do json_add_string . "$c"
    done
    case "$_type_find" in
        array|object) json_select ..;;
    esac
    case "$command" in
        find_all)
            uci_result_do json_close_array
            _result="";;
        *)
            _result="$section"
            [ -n "$section" ] && return 0 || return 1;;
    esac
}

uci_ensure() {
    local keys k v
    [ -n "$name" -o -z "$type" ] || name="$section"
    type="${type:-$section}"
    [ -n "$config" -a -n "$type" ] ||
        fail "config, type and name required for $command"
    [ -n "$name" ] && uci_check_type "$config.$name" "$type" || {
        [ "$_type_find" = "object" -o -n "$option" ] && uci_find && {
            [ -z "$name" ] || try uci rename "$config.$section=$name"
        } || {
            [ "$command" = absent ] && return 0 || uci_add
        }
    }
    section="${name:-$_result}"
    key="$config.$section${option:+.$option}"
    [ "$command" = "absent" ] && {
        [ -z "$_defined_value" ] &&
            { uci -q delete "$key" || :; } ||
            case "$_type_value" in
                array|object)
                    json_select_real value
                    json_get_keys keys
                    for k in $keys; do
                        json_get_var v "$k"
                        case "$_type_value" in
                            array) uci -q delete "$config.$section.$v";;
                            object) uci -q delete "$config.$section.$k=$v";;
                        esac
                    done
                    json_select ..;;
                *) uci -q delete "$config.$section.$value";;
            esac
        return 0
    }
    [ -z "$set_find" -o "$_type_find" != "object" -a -z "$option" ] || {
        uci_set find
        [ "$_type_value" != "object" ] || {
            key="$config.$section"
            option=""
        }
    }
    [ -z "$_defined_value" ] || uci_set
    _result="$section"
}

uci_cleanup_section() {
    case "$command" in
        set|ensure|section) :;;
        *) return 0;;
    esac
    local k v
    [ -n "$replace" -a -n "$config" -a -n "$section" ] || return 0
    for k in $(uci -q show "$config.$section" |
            sed -n 's/^..*\...*\.\([^.][^.]*\)=.*$/\1/p')
            do
        for v in $keep_keys; do
            [ "$k" != "$v" ] || continue 2
        done
        uci -q delete "$config.$section.$k"
    done
}

uci_revert() {
    [ -z "$key" ] && rm -f -- "/tmp/.uci"/* 2>/dev/null || uci revert "$key"
}

uci_autocommit() {
    [ -n "$autocommit" ] || return 0
    case "$command" in
        commit|revert) return 0;;
    esac
    [ "$1" -eq 0 ] && {
        [ -n "$config" ] && uci commit "$config" || uci commit
    } || uci_revert
}

main() {
    case "$command" in
        batch|import)
            [ -n "$value" ] || fail "value required for $command";;
        add_list|del_list|rename|reorder)
            [ -n "$key" -a -n "$value" ] ||
                fail "key and value required for $command";;
        add|get|delete|ensure|absent)
            [ -n "$key" ] || fail "key required for $command";;
    esac
    case "$command" in
        batch)
            echo "$value" | final uci $command;;
        export|changes|show|commit)
            local cmd="final uci $command"
            [ -z "$key" ] && $cmd || $cmd "$key";;
        import)
            local cmd="final uci ${merge:+-m }$command"
            [ -z "$key" ] && echo "$value" | $cmd ||
                echo "$value" | $cmd "$key";;
        add)
            uci_add; exit 0;;
        add_list)
            [ -z "$unique" ] || {
                eval "set -- $(uci_get_safe -q "$key")"
                for entry; do [ "$entry" = "$value" ] && exit 0; done
            }
            final uci add_list "$key=$value";;
        del_list|reorder)
            final uci $command "$key=$value";;
        get)
            uci_get; exit 0;;
        delete)
            final uci $command "$key${value:+=$value}";;
        rename)
            final uci $command "$key=${name:-$value}";;
        revert)
            final uci_revert;;
        set)
            uci_set; exit 0;;
        find|find_all)
            uci_find; exit $?;;
        ensure|section)
            uci_ensure; exit 0;;
        absent)
            [ -n "$_defined_find" ] || {
                uci -q delete "$key${value:+=$value}"; exit 0
            }
            uci_ensure; exit 0;;
        *) fail "unknown command: $command";;
    esac
}

cleanup() {
    local ec="$1"
    [ "$ec" -ne 0 ] || uci_cleanup_section
    [ "$changes" = "$(uci_change_hash)" ] || {
        changed
        [ "$_ansible_verbosity" -lt 2 ] || {
            local _IFS line
            _IFS="$IFS"; IFS="$N"; set -- $(uci changes); IFS="$_IFS"
            json_set_namespace result
            json_add_array changes
            for line; do json_add_string . "$line"; done
            json_close_array
            json_set_namespace params
        }
        uci_autocommit "$ec"
    }
    [ -z "$_ansible_diff" -o -z "$config" ] ||
        set_diff "" "$(uci export "$config")"
    [ -z "$_ansible_check_mode" -o -z "$state_path" -o ! -d "$state_path" ] ||
        rm -rf "$state_path"
}

_parse_params
_support_check_mode
init || fail "module init failed"
_init_done="1"
main
