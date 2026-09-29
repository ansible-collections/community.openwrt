// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { dirname, readfile, stat, writefile } from 'fs';
import { AnsibleModule } from '_basic';
import { FILE_COMMON_ARGS, diff_side, is_dir, make_dirs, set_file_attributes } from '_file';

const module = AnsibleModule({
    argument_spec: {
        path:         { type: 'str', required: true, aliases: [ 'dest', 'destfile', 'name' ] },
        line:         { type: 'str', aliases: [ 'value' ] },
        state:        { type: 'str', default: 'present', choices: [ 'absent', 'present' ] },
        regex:        { type: 'str', aliases: [ 'regexp' ] },
        backrefs:     { type: 'bool', default: false },
        insertafter:  { type: 'str' },
        insertbefore: { type: 'str' },
        create:       { type: 'bool', default: false },
        ...FILE_COMMON_ARGS,
    },
    required_if: [
        [ 'state', 'present', [ 'line' ] ],
        [ 'state', 'absent', [ 'line', 'regex' ], true ],
    ],
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// ---- helpers --------------------------------------------------------------

// A regular expression the task gave, failing the module when it is not valid.
function compile(module, name, pattern) {
    try {
        return regexp(pattern);
    } catch (e) {
        module.fail_json(`${name} is not a valid regular expression: ${e.message}`);
    }
}

// The lines of a text. Newlines at its end end the last line, and do not start
// empty ones.
function lines_of(text) {
    let content = rtrim(text, '\n');
    return content != '' ? split(content, '\n') : [];
}

// The text of a file made of `lines`.
function text_of(lines) {
    return length(lines) > 0 ? `${join('\n', lines)}\n` : '';
}

// The index of the last line `matches` accepts, or -1 when there is none.
function last_match(lines, matches) {
    for (let i = length(lines) - 1; i >= 0; i--) {
        if (matches(lines[i]))
            return i;
    }

    return -1;
}

// The line a backrefs match turns `text` into: the part `re` matches is
// replaced by `line`, in which \1 to \9 stand for the groups and & for the
// whole match, as they do for sed(1).
function substitute(text, re, line) {
    return replace(text, re, (...groups) =>
        replace(line, /\\([0-9&\\])|&/g, (ref, escaped) => {
            if (escaped == null)
                return groups[0];
            if (escaped in [ '&', '\\' ])
                return escaped;
            return groups[+escaped] ?? '';
        }));
}

// Where a line that is not in the file yet goes: after the last line
// insertafter matches, or before the last one insertbefore matches, and
// otherwise at the end - or at the start, when either of them is BOF.
function insertion_point(module, lines, insertafter, insertbefore) {
    if (insertafter != null && !(insertafter in [ '', 'BOF', 'EOF' ])) {
        let re = compile(module, 'insertafter', insertafter);
        let at = last_match(lines, (text) => match(text, re) != null);
        if (at >= 0)
            return at + 1;
    } else if (insertbefore != null && !(insertbefore in [ '', 'BOF' ])) {
        let re = compile(module, 'insertbefore', insertbefore);
        let at = last_match(lines, (text) => match(text, re) != null);
        if (at >= 0)
            return at;
    }

    return 'BOF' in [ insertafter, insertbefore ] ? 0 : length(lines);
}

// The lines with the line the task asked for in place, or null when there is
// nothing to change. The last line `matches` accepts is the one replaced.
function line_present(module, lines, re, matches) {
    let task = module.params;
    let at = last_match(lines, matches);

    if (at < 0) {
        if (task.backrefs)
            return null;

        let insert_at = insertion_point(module, lines, task.insertafter, task.insertbefore);
        return [ ...slice(lines, 0, insert_at), task.line, ...slice(lines, insert_at) ];
    }

    let wanted = task.backrefs ? substitute(lines[at], re, task.line) : task.line;
    if (lines[at] == wanted)
        return null;

    let updated = [ ...lines ];
    updated[at] = wanted;
    return updated;
}

// The lines without any `matches` accepts, or null when there is none.
function line_absent(lines, matches) {
    let kept = filter(lines, (text) => !matches(text));
    return length(kept) != length(lines) ? kept : null;
}

// ---- validation -----------------------------------------------------------

const path = params.path;

if (params.state == 'present' && params.backrefs && params.regex == null)
    module.fail_json('regexp is required with backrefs');

if (is_dir(path))
    module.fail_json(`path ${path} is a directory`);

// Without regexp, the line to look for is the line itself.
const re = params.regex != null ? compile(module, 'regexp', params.regex) : null;
const matches = re != null ? (text) => match(text, re) != null : (text) => text == params.line;

// ---- main -----------------------------------------------------------------

let info = stat(path);
let exists = info != null && info.type == 'file';
let text = '';

if (exists) {
    text = readfile(path);
    if (text == null)
        module.fail_json(`path ${path} not readable`);
} else if (params.state == 'present' && !params.create) {
    module.fail_json(`path ${path} does not exist`);
}

let before = lines_of(text);
let after = params.state == 'present' ? line_present(module, before, re, matches) : line_absent(before, matches);

if (after != null) {
    if (module.diff_mode) {
        result.update({
            diff: {
                before: diff_side(join('\n', before)),
                after: diff_side(join('\n', after)),
                before_header: path,
                after_header: path,
            },
        });
    }

    if (!module.check_mode) {
        if (!exists)
            make_dirs(module, dirname(path), { owner: null, group: null, mode: null });

        if (writefile(path, text_of(after)) == null)
            module.fail_json(`path ${path} not writeable`);
    }

    result.changed();
}

if (stat(path) != null && set_file_attributes(module, path))
    result.changed();

module.exit_json();
