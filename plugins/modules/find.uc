// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { error, lsdir, lstat, stat } from 'fs';
import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        paths:      { type: 'list', elements: 'str', required: true, aliases: [ 'name', 'path' ] },
        patterns:   { type: 'list', elements: 'str', default: [], aliases: [ 'pattern' ] },
        excludes:   { type: 'list', elements: 'str', default: [], aliases: [ 'exclude' ] },
        use_regex:  { type: 'bool', default: false },
        file_type:  { type: 'str', default: 'file',
                      choices: [ 'any', 'directory', 'file', 'link', 'block', 'char', 'socket', 'pipe' ] },
        recurse:    { type: 'bool', default: false },
        depth:      { type: 'int' },
        hidden:     { type: 'bool', default: false },
        follow:     { type: 'bool', default: false },
        age:        { type: 'str' },
        age_stamp:  { type: 'str', default: 'mtime', choices: [ 'atime', 'ctime', 'mtime' ] },
        size:       { type: 'str' },
        mode:       { type: 'str' },
        exact_mode: { type: 'bool', default: true },
        limit:      { type: 'int' },
    },
    supports_check_mode: true,
});

const params = module.params;

// The type lstat() reports for each value of file_type; `any` takes them all.
const FILE_TYPES = {
    any: null, directory: 'directory', file: 'file', link: 'link',
    block: 'block', char: 'char', socket: 'socket', pipe: 'fifo',
};

const AGE_UNITS = { s: 1, m: 60, h: 3600, d: 86400, w: 604800 };
const SIZE_UNITS = { b: 1, k: 1024, m: 1024 * 1024, g: 1024 * 1024 * 1024, t: 1024 * 1024 * 1024 * 1024 };

// ---- criteria -------------------------------------------------------------

// The POSIX extended regular expression matching the same names as the shell
// glob `glob`, anchored at both ends.
function glob_to_regex(glob) {
    let re = '';
    let n = length(glob);

    for (let i = 0; i < n; i++) {
        let c = substr(glob, i, 1);

        if (c == '*')
            re += '.*';
        else if (c == '?')
            re += '.';
        else if (c == '[') {
            // A bracket expression runs to the next `]`, a `]` right after the
            // opening (or after its negation) being part of it. Without a
            // closing `]` the `[` stands for itself.
            let j = i + 1;
            if (j < n && substr(glob, j, 1) == '!')
                j++;
            if (j < n && substr(glob, j, 1) == ']')
                j++;
            while (j < n && substr(glob, j, 1) != ']')
                j++;

            if (j >= n)
                re += '\\[';
            else {
                let body = substr(glob, i + 1, j - i - 1);
                if (substr(body, 0, 1) == '!')
                    body = '^' + substr(body, 1);
                re += `[${body}]`;
                i = j;
            }
        }
        else if (index('.^$+(){}|\\', c) >= 0)
            re += '\\' + c;
        else
            re += c;
    }

    return `^${re}$`;
}

// The patterns, as compiled regular expressions matching the whole name.
function compile_patterns(patterns, use_regex) {
    let compiled = [];

    for (let pattern in patterns ?? []) {
        let source = use_regex ? `^(${pattern})$` : glob_to_regex(pattern);
        try {
            push(compiled, regexp(source));
        } catch (e) {
            module.fail_json(`invalid pattern '${pattern}': ${e.message}`);
        }
    }

    return compiled;
}

function matches_any(name, regexes) {
    for (let re in regexes) {
        if (match(name, re))
            return true;
    }

    return false;
}

// A signed amount followed by an optional unit, as the amount times the factor
// of its unit; `null` when `spec` is not in that form.
function parse_amount(spec, units, default_unit) {
    let found = match(lc(trim(spec)), /^(-?[0-9]+)([a-z]?)$/);
    if (found == null)
        return null;

    let factor = units[found[2] != '' ? found[2] : default_unit];
    if (factor == null)
        return null;

    return +found[1] * factor;
}

// An octal permission string as a number; `null` when it is not one.
function parse_mode(spec) {
    if (!match(spec, /^[0-7]{1,4}$/))
        return null;

    let value = 0;
    for (let i = 0; i < length(spec); i++)
        value = value * 8 + +substr(spec, i, 1);

    return value;
}

// What the task selects on, worked out once from its parameters.
function criteria(now) {
    let crit = {
        patterns: compile_patterns(params.patterns, params.use_regex),
        excludes: compile_patterns(params.excludes, params.use_regex),
        type: FILE_TYPES[params.file_type],
        stamp: params.age_stamp,
        now: now,
        age: null,
        size: null,
        mode: null,
    };

    if (params.age != null) {
        crit.age = parse_amount(params.age, AGE_UNITS, 's');
        if (crit.age == null)
            module.fail_json(`invalid age '${params.age}'`);
    }

    if (params.size != null) {
        crit.size = parse_amount(params.size, SIZE_UNITS, 'b');
        if (crit.size == null)
            module.fail_json(`invalid size '${params.size}'`);
    }

    if (params.mode != null) {
        crit.mode = parse_mode(params.mode);
        if (crit.mode == null)
            module.fail_json(`invalid mode '${params.mode}': only octal modes are supported`);
    }

    return crit;
}

function is_hidden(name) {
    return substr(name, 0, 1) == '.';
}

// A positive limit selects what is at least that much, a negative one what is
// at most its absolute value.
function within(value, limit) {
    return limit >= 0 ? value >= limit : value <= -limit;
}

// Whether the entry `name`, whose (l)stat() is `info`, is one the task looks for.
function selected(name, info, crit) {
    if (!params.hidden && is_hidden(name))
        return false;
    if (crit.type != null && info.type != crit.type)
        return false;
    if (length(crit.patterns) > 0 && !matches_any(name, crit.patterns))
        return false;
    if (matches_any(name, crit.excludes))
        return false;
    if (crit.age != null && !within(crit.now - info[crit.stamp], crit.age))
        return false;
    if (crit.size != null && info.type == 'file' && !within(info.size, crit.size))
        return false;
    if (crit.mode != null) {
        let perm = info.mode & 0xfff;
        if (params.exact_mode ? perm != crit.mode : (perm & crit.mode) != crit.mode)
            return false;
    }

    return true;
}

// ---- walking --------------------------------------------------------------

function file_facts(path, info) {
    return {
        path: path,
        mode: sprintf('%04o', info.mode & 0xfff),
        size: info.size,
        uid: info.uid,
        gid: info.gid,
        atime: info.atime,
        mtime: info.mtime,
        ctime: info.ctime,
        inode: info.inode,
        nlink: info.nlink,
        isdir: info.type == 'directory',
        isreg: info.type == 'file',
        islnk: info.type == 'link',
        issock: info.type == 'socket',
        isblk: info.type == 'block',
        ischr: info.type == 'char',
        isfifo: info.type == 'fifo',
    };
}

function dir_key(info) {
    return `${info.dev.major}:${info.dev.minor}:${info.inode}`;
}

// Look at the entries of `dir`, which sits at `level` below the path the task
// named, collecting into `state` the ones selected.
function walk(dir, level, crit, state) {
    let entries = lsdir(dir);
    if (entries == null) {
        state.skipped_paths[dir] = `cannot read '${dir}': ${error()}`;
        return;
    }

    for (let name in sort(entries)) {
        if (state.done)
            return;

        let path = dir == '/' ? `/${name}` : `${dir}/${name}`;
        let info = lstat(path);
        if (info == null)
            continue;  // gone since it was listed

        // A link that cannot be followed is reported as the link it is.
        if (params.follow && info.type == 'link')
            info = stat(path) ?? info;

        state.examined++;

        if (selected(name, info, crit)) {
            push(state.files, file_facts(path, info));
            if (params.limit != null && length(state.files) >= params.limit) {
                state.done = true;
                return;
            }
        }

        if (info.type != 'directory' || !params.recurse)
            continue;
        if (params.depth != null && level >= params.depth)
            continue;
        if (!params.hidden && is_hidden(name))
            continue;

        // Following links can lead back into a directory being searched, which
        // would never end. Reaching the same directory by another way is fine.
        let key = dir_key(info);
        if (state.ancestors[key]) {
            state.skipped_paths[path] = `'${path}' is a link to a directory being searched`;
            continue;
        }

        state.ancestors[key] = true;
        walk(path, level + 1, crit, state);
        delete state.ancestors[key];
    }
}

// END-OF-UNIT-TESTABLES

for (let name in [ 'depth', 'limit' ]) {
    if (params[name] != null && params[name] < 1)
        module.fail_json(`${name} must be a positive integer`);
}

let crit = criteria(time());
let state = { files: [], examined: 0, skipped_paths: {}, ancestors: {}, done: false };

for (let path in params.paths) {
    if (substr(path, 0, 1) != '/')
        module.fail_json(`'${path}' is not an absolute path`);

    // Drop trailing slashes, so the paths built from it have none doubled.
    let root = replace(path, /\/+$/, '');
    if (root == '')
        root = '/';

    // The path the task names is a directory to search even when reached
    // through a link.
    let info = stat(root);
    if (info == null)
        state.skipped_paths[path] = `'${path}' does not exist or cannot be accessed`;
    else if (info.type != 'directory')
        state.skipped_paths[path] = `'${path}' is not a directory`;
    else {
        state.ancestors = {};
        state.ancestors[dir_key(info)] = true;
        walk(root, 1, crit, state);
    }

    if (state.done)
        break;
}

for (let path, reason in state.skipped_paths)
    module.warn(`skipped ${path}: ${reason}`);

module.exit_json({
    msg: length(state.skipped_paths) > 0 ? 'Not all paths examined, check warnings for details' : '',
    files: state.files,
    matched: length(state.files),
    examined: state.examined,
    skipped_paths: state.skipped_paths,
});
