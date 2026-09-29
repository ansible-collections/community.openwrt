// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { basename, dirname, error, lsdir, lstat, open, readlink, realpath, stat, symlink } from 'fs';
import { AnsibleModule } from '_basic';
import { FILE_COMMON_ARGS, is_dir, is_link, make_dirs, set_file_attributes } from '_file';

const module = AnsibleModule({
    argument_spec: {
        path:              { type: 'str', required: true, aliases: [ 'dest', 'name' ] },
        state:             { type: 'str', choices: [ 'absent', 'directory', 'file', 'hard', 'link', 'touch' ] },
        src:               { type: 'str' },
        force:             { type: 'bool', default: false },
        recurse:           { type: 'bool', default: false },
        original_basename: { type: 'str', aliases: [ '_original_basename' ] },
        diff_peek:         { type: 'str' },
        ...FILE_COMMON_ARGS,
    },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// How much of a file is looked at to tell whether it is binary.
const PEEK_SIZE = 8192;

// How many links in a chain are followed before it is taken for a loop.
const MAX_LINKS = 40;

// ---- helpers --------------------------------------------------------------

// The state a path is in, in the terms of the `state` parameter. Anything that
// is neither a directory nor a link counts as a file - or as a hard link, when
// more than one name leads to it.
function state_of(path) {
    let info = lstat(path);
    if (info == null)
        return 'absent';
    if (info.type in [ 'directory', 'link' ])
        return info.type;

    return info.nlink > 1 ? 'hard' : 'file';
}

// Whether the start of a file holds a NUL byte, which text never does.
function appears_binary(path) {
    let fh = open(path, 'r');
    if (fh == null)
        return false;

    let head = fh.read(PEEK_SIZE);
    fh.close();

    return head != null && index(head, '\u0000') >= 0;
}

// Where a chain of symbolic links ends, whether or not anything is there.
function resolve_link(path) {
    for (let hops = 0; hops < MAX_LINKS && is_link(path); hops++) {
        let target = readlink(path);
        path = substr(target, 0, 1) == '/' ? target : `${dirname(path)}/${target}`;
    }

    return realpath(path) ?? path;
}

// The file a link at `path` leads to. A relative src is taken from the
// directory the link is in - or from `path` itself, when that is a directory.
function link_source(src, path) {
    if (substr(src, 0, 1) == '/')
        return src;
    if (!is_link(path) && is_dir(path))
        return `${path}/${src}`;

    return `${dirname(path)}/${src}`;
}

// Remove whatever is at `path`, directories and their contents included.
function remove(module, path, failure) {
    let res = module.run_command([ 'rm', '-rf', '--', path ]);
    if (res.rc != 0)
        module.fail_json(`${failure}: ${trim(res.stderr)}`);
}

// Make a link at `path`. A symbolic link holds src as it was written; a hard
// link is another name for the file src leads to.
function make_link(module, state, path, src, abs_src) {
    if (state == 'link') {
        if (!symlink(src, path))
            module.fail_json(`error while linking ${path} to ${src}: ${error()}`);
        return;
    }

    let res = module.run_command([ 'ln', '--', abs_src, path ]);
    if (res.rc != 0)
        module.fail_json(`error while linking ${path} to ${src}: ${trim(res.stderr)}`);
}

// Whether the link at `path` has to be made, failing when that would replace
// something the task is not allowed to replace.
function link_outdated(module, state, path, prev_state, src, abs_src) {
    let force = module.params.force;

    if (prev_state == 'absent')
        return true;
    if (prev_state != state && !force)
        module.fail_json(`refusing to convert between ${prev_state} and ${state} for ${path}`);

    switch (prev_state) {
    case 'link':
        return state != 'link' || readlink(path) != src;

    case 'hard':
        if (state == 'hard' && lstat(path).inode == lstat(abs_src).inode)
            return false;
        if (!force)
            module.fail_json('cannot link, different hard link exists at destination');
        return true;

    case 'directory':
        if (length(lsdir(path) ?? []) > 0)
            module.fail_json(`the directory ${path} is not empty refusing to convert it`);
        return true;
    }

    return true;
}

// ---- states ---------------------------------------------------------------
//
// Each state is brought about by a function returning the path it ended up
// acting on - a link being followed leads it elsewhere - and whether that
// changed anything.

function ensure_absent(module, path, prev_state) {
    if (prev_state == 'absent')
        return { path: path, changed: false };

    if (!module.check_mode)
        remove(module, path, 'removing failed');

    return { path: path, changed: true };
}

function ensure_file(module, path, prev_state) {
    if (module.params.follow && prev_state == 'link') {
        path = resolve_link(path);
        prev_state = state_of(path);
    }

    if (!(prev_state in [ 'file', 'hard' ]))
        module.fail_json(`file (${path}) is ${prev_state}, cannot continue`);

    return { path: path, changed: set_file_attributes(module, path) };
}

function ensure_directory(module, path, prev_state) {
    if (module.params.follow && prev_state == 'link') {
        path = resolve_link(path);
        prev_state = state_of(path);
    }

    if (prev_state == 'absent') {
        if (!module.check_mode)
            make_dirs(module, path);

        return { path: path, changed: true };
    }

    if (prev_state != 'directory')
        module.fail_json(`${path} already exists as a ${prev_state}`);

    return { path: path, changed: set_file_attributes(module, path, { recurse: module.params.recurse }) };
}

function ensure_link(module, state, path, prev_state, src) {
    let abs_src = link_source(src, path);
    let source = stat(abs_src);

    if (source == null) {
        if (state == 'hard')
            module.fail_json(`src file does not exist, cannot hard link ${abs_src}`);
        if (!module.params.force)
            module.fail_json(`src file does not exist, use force=yes if you want to link ${abs_src}`);
    } else if (state == 'hard' && source.type == 'directory') {
        module.fail_json(`src is a directory, cannot hard link ${abs_src}`);
    }

    let changed = link_outdated(module, state, path, prev_state, src, abs_src);
    if (module.check_mode)
        return { path: path, changed: changed };

    if (changed) {
        if (prev_state != 'absent')
            remove(module, path, `error replacing ${path}`);

        make_link(module, state, path, src, abs_src);
    }

    return { path: path, changed: set_file_attributes(module, path) || changed };
}

// Touching updates the times of the file, so it always counts as a change.
function ensure_touched(module, path, prev_state) {
    if (module.params.follow && prev_state == 'link')
        path = resolve_link(path);

    if (!module.check_mode) {
        let res = module.run_command([ 'touch', '--', path ]);
        if (res.rc != 0)
            module.fail_json(`error touching ${path}: ${trim(res.stderr)}`);

        set_file_attributes(module, path);
    }

    return { path: path, changed: true };
}

// ---- main -----------------------------------------------------------------

// diff_peek only asks whether the file looks binary, and changes nothing.
if (params.diff_peek != null)
    module.exit_json({ path: params.path, appears_binary: appears_binary(params.path) });

let path = params.path;
let prev_state = state_of(path);

// Without a state, the path stays what it is, and a path that is not there
// becomes a file - or a directory, when the task recurses into it.
let state = params.state;
if (state == null)
    state = prev_state != 'absent' ? prev_state : (params.recurse ? 'directory' : 'file');

// A link made without src leads to what the path already resolves to.
let src = params.src;
if (src == null && state in [ 'link', 'hard' ]) {
    if (state == 'link' && params.follow)
        module.fail_json('src and dest are required for creating links');

    src = resolve_link(path);
}

// A directory given as the path of anything but a link or an absence stands
// for the file of the same name inside it.
if (!(state in [ 'absent', 'link' ]) && is_dir(path)) {
    let name = params.original_basename ?? (src != null ? basename(src) : null);
    if (name != null) {
        path = `${rtrim(path, '/')}/${name}`;
        prev_state = state_of(path);
    }
}

if (params.recurse && state != 'directory')
    module.fail_json('recurse options requires state to be directory');

let outcome;
switch (state) {
case 'absent':
    outcome = ensure_absent(module, path, prev_state);
    break;
case 'file':
    outcome = ensure_file(module, path, prev_state);
    break;
case 'directory':
    outcome = ensure_directory(module, path, prev_state);
    break;
case 'touch':
    outcome = ensure_touched(module, path, prev_state);
    break;
default:
    outcome = ensure_link(module, state, path, prev_state, src);
}

result.update({ path: outcome.path, state: state });
result.changed(outcome.changed);

module.exit_json();
