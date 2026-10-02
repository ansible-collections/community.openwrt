// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { access, readfile, writefile } from 'fs';
import { AnsibleModule } from '_basic';

const SYSCTL = '/sbin/sysctl';
const DEFAULT_SYSCTL_FILE = '/etc/sysctl.conf';

const module = AnsibleModule({
    argument_spec: {
        ignore_errors: { type: 'bool', aliases: [ 'ignoreerrors' ] },
        name:          { type: 'str', required: true, aliases: [ 'key' ] },
        reload:        { type: 'bool', default: true },
        state:         { type: 'str', default: 'present' },
        sysctl_file:   { type: 'str' },
        sysctl_set:    { type: 'bool', default: false },
        value:         { type: 'str', aliases: [ 'val' ] },
    },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

const name = params.name;
const value = params.value != null ? params.value : '';
const sysctl_file = params.sysctl_file ? params.sysctl_file : DEFAULT_SYSCTL_FILE;

// Split a line into words, as the shell does with an unquoted expansion.
function words_of(line) {
    let trimmed = trim(line, ' \t\n');
    return trimmed == '' ? [] : split(trimmed, /[ \t\n]+/);
}

function starts_with_hash(word) {
    return substr(word, 0, 1) == '#';
}

function is_echo_option(word) {
    return match(word, /^-[neE]+$/) != null;
}

// The lines of `content` as the shell implementation read them, through
// `while read line` without -r: a backslash escapes the character after it and
// is dropped, a backslash before a newline joins two lines, blanks are trimmed
// from both ends (at the start, up to the first unescaped character), NUL
// bytes are dropped, and a last line not ending in a newline is lost.
function shell_read_lines(content) {
    let lines = [];
    let buf = '';
    let backslash = false;
    let startword = true;

    for (let c in split(content, '')) {
        if (c == '' || c == '\0')
            continue;

        if (backslash) {
            backslash = false;
            if (c != '\n')
                buf += c;
            continue;
        }
        if (c == '\\') {
            backslash = true;
            continue;
        }
        if (c == '\n') {
            push(lines, rtrim(buf, ' \t\n'));
            buf = '';
            startword = true;
            continue;
        }
        if (startword && index(' \t', c) >= 0)
            continue;

        startword = false;
        buf += c;
    }

    return lines;
}

// What `echo "$line"` wrote for a line: nothing, or a bare newline, for a
// line made of echo options alone.
function shell_echo_line(line) {
    if (is_echo_option(line))
        return index(line, 'n') >= 0 ? '' : '\n';
    return `${line}\n`;
}

// ---- running kernel -------------------------------------------------------

function is_known_key() {
    let out = module.run_command([ SYSCTL, name ]).stdout;
    return length(split(out, '\n')) - 1 == 1;
}

function set_kernel_value() {
    // The current value as `echo $(sysctl -n ...)` gave it: its words joined by
    // single blanks, leading words that are echo options left out.
    let words = words_of(module.run_command([ SYSCTL, '-n', name ]).stdout);
    while (length(words) > 0 && is_echo_option(words[0]))
        shift(words);
    let current = join(' ', words);
    if (current == value)
        return;

    result.changed();
    if (module.check_mode)
        return;

    let res = module.run_command([ SYSCTL, '-w', `${name}=${value}` ]);
    if (res.rc != 0)
        module.fail_json(`failed to set ${name} to ${value}: ${rtrim(res.stdout, '\n')}`);
}

// ---- sysctl file ----------------------------------------------------------

// The lines of the sysctl file, as read by the shell implementation, with the
// entries for the key updated or removed. Entries are only recognized in the
// form key=value, with no blanks around the equal sign, and a comment
// following the value is kept.
function updated_lines() {
    let content = readfile(sysctl_file);
    let lines = shell_read_lines(content != null ? content : '');

    let found = false;
    let out = [];

    for (let line in lines) {
        let words = words_of(line);
        let first = words[0];

        if (first == null || starts_with_hash(first) || index(first, '=') < 0) {
            push(out, line);
            continue;
        }

        let eq = index(first, '=');
        let k = substr(first, 0, eq);
        if (k == name) {
            found = true;
            if (params.state != 'present') {
                result.changed();
                continue;
            }

            let v = substr(first, eq + 1);
            let i = 1;
            for (; i < length(words) && !starts_with_hash(words[i]); i++)
                v += ` ${words[i]}`;

            if (v != value) {
                let comment = slice(words, i);
                line = `${k}=${value}` + (length(comment) > 0 ? ` ${join(' ', comment)}` : '');
                result.changed();
            }
        }
        push(out, line);
    }

    if (params.state == 'present' && !found) {
        push(out, `${name}=${value}`);
        result.changed();
    }

    return out;
}

// ---- main -----------------------------------------------------------------

if (params.state == 'present') {
    if (value == '')
        module.fail_json('value must be given with state present');
}
else if (params.state != 'absent')
    module.fail_json('state must be present or absent');

result.update({ name: name });
if (value != '')
    result.update({ value: value });

if (!access(sysctl_file, 'w'))
    module.fail_json(`sysctl file ${sysctl_file} not writeable`);

let ignore_errors = params.state != 'present' || params.ignore_errors;
if (!(ignore_errors && !params.sysctl_set) && !is_known_key())
    module.fail_json(`unknown sysctl key ${name}`);

if (params.sysctl_set)
    set_kernel_value();

let lines = updated_lines();

if (result.is_changed() && !module.check_mode) {
    writefile(sysctl_file, join('', map(lines, shell_echo_line)));

    if (params.reload && params.state == 'present') {
        let res = module.run_command([ SYSCTL, '-p', sysctl_file ]);
        if (res.rc != 0)
            module.fail_json(`failed to reload: ${rtrim(res.stdout + res.stderr, '\n')}`);
    }
}

module.exit_json();
