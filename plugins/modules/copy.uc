// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { access, basename, dirname, error, lstat, mkdir, open, readfile, realpath, stat, unlink } from 'fs';
import { AnsibleModule } from '_basic';
import { FILE_COMMON_ARGS, backup_local, digest, set_file_attributes } from '_file';

const module = AnsibleModule({
    argument_spec: {
        backup:            { type: 'bool', default: false },
        dest:              { type: 'str', required: true },
        directory_mode:    { type: 'str' },
        force:             { type: 'bool', default: true, aliases: [ 'thirsty' ] },
        original_basename: { type: 'str', aliases: [ '_original_basename' ] },
        src:               { type: 'str' },
        validate:          { type: 'str' },
        _diff_max_bytes:   { type: 'int', default: 104448 },
        ...FILE_COMMON_ARGS,
    },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

const CHUNK_SIZE = 65536;

// The source is the copy of the file the action plugin left on the device. The
// destination is rewritten as the module works out where the file goes.
let src = params.src != null ? params.src : '';
let dest = params.dest;

// ---- helpers --------------------------------------------------------------

function is_dir(path) {
    let info = stat(path);
    return info != null && info.type == 'directory';
}

function is_link(path) {
    let info = lstat(path);
    return info != null && info.type == 'link';
}

function file_size(path) {
    let info = stat(path);
    return info != null ? info.size : 0;
}

// Keep the destination reported to the user in step with the one being worked on.
function set_dest(value) {
    dest = value;
    result.update({ dest: dest });
}

// Create the directories leading to the destination, giving each one the mode
// the task asked for its directories.
function make_parents(path) {
    let created = substr(path, 0, 1) == '/' ? '' : '.';

    for (let part in split(path, '/')) {
        if (part == '')
            continue;

        created += `/${part}`;
        if (is_dir(created))
            continue;

        if (!mkdir(created))
            module.fail_json(`mkdir ${created}: ${error()}`);

        if (set_file_attributes(module, created, { mode: params.directory_mode }))
            result.changed();
    }
}

// One side of the diff, as a text ending in a single newline - or nothing at
// all, which is how a file that is not there is told apart from an empty one.
function diff_side(text) {
    let content = rtrim(text, '\n');
    return content != '' ? `${content}\n` : '';
}

// Show what the copy does to the destination. A file too large on either side
// is reported as skipped rather than read into memory.
function report_diff() {
    let limit = params._diff_max_bytes;
    let before = '';
    let after = '';

    if (file_size(src) > limit || (access(dest, 'r') && file_size(dest) > limit)) {
        before = `[diff skipped: file larger than ${limit} bytes]`;
        after = before;
    } else {
        if (access(dest, 'r'))
            before = readfile(dest);

        after = readfile(src);
    }

    result.update({
        diff: {
            before: diff_side(before),
            after: diff_side(after),
            before_header: dest,
            after_header: dest,
        },
    });
}

// Run the command the task wants the file checked with before it is put in
// place, with %s standing for the file.
function validate_source() {
    if (index(params.validate, '%s') < 0)
        module.fail_json(`validate must contain %s: ${params.validate}`);

    let res = module.run_command(replace(params.validate, '%s', () => src));
    if (res.rc != 0)
        module.fail_json(`failed to validate: ${trim(`${res.stdout}${res.stderr}`)}`);
}

// Replace the contents of the destination with those of the source, reading the
// file a piece at a time so that its size is not the module's memory footprint.
function copy_contents() {
    let input = open(src, 'r');
    if (input == null)
        module.fail_json(`cannot read ${src}: ${error()}`);

    let output = open(dest, 'w');
    if (output == null)
        module.fail_json(`cannot write ${dest}: ${error()}`);

    for (let chunk = input.read(CHUNK_SIZE); chunk != null && chunk != ''; chunk = input.read(CHUNK_SIZE)) {
        if (output.write(chunk) != length(chunk))
            module.fail_json(`cannot write ${dest}: ${error()}`);
    }

    input.close();
    output.close();
}

// ---- validation -----------------------------------------------------------

if (stat(src) == null)
    module.fail_json(`Source ${src} not found`);

if (!access(src, 'r'))
    module.fail_json(`Source ${src} not readable`);

if (is_dir(src))
    module.fail_json(`Remote copy does not support recursive copy of directory: ${src}`);

// ---- main -----------------------------------------------------------------

let md5sum_src = digest(module, 'md5', src);
let md5sum_dest = '';

result.update({ src: src, dest: dest });
if (md5sum_src != '')
    result.update({ md5sum: md5sum_src });

// A destination ending in "/" names the directory the file goes into.
if (params.original_basename != null && substr(dest, -1) == '/') {
    set_dest(`${dest}${params.original_basename}`);

    let parent = dirname(dest);
    if (!is_dir(parent))
        make_parents(parent);
}

// So does a destination that is a directory already.
if (is_dir(dest))
    set_dest(`${rtrim(dest, '/')}/${params.original_basename != null ? params.original_basename : basename(src)}`);

// The directory the file is written into, which is the one that has to be
// writeable even when the destination itself turns out to be a symlink.
let parent = dirname(dest);

if (stat(dest) != null) {
    if (is_link(dest) && params.follow)
        set_dest(realpath(dest));

    if (!params.force) {
        result.changed(false);
        module.exit_json('file already exists');
    }

    if (access(dest, 'r'))
        md5sum_dest = digest(module, 'md5', dest);
} else if (!is_dir(parent)) {
    module.fail_json(`Destination directory ${parent} does not exist`);
}

if (!access(parent, 'w'))
    module.fail_json(`Destination ${parent} not writeable`);

// A symlink is replaced by a file of its own, so it is copied over even when it
// already points at the same contents.
if (md5sum_src != md5sum_dest || is_link(dest)) {
    if (module.diff_mode)
        report_diff();

    if (!module.check_mode) {
        if (params.backup) {
            let backup_file = backup_local(module, dest);
            if (backup_file != '')
                result.update({ backup_file: backup_file });
        }

        if (is_link(dest))
            unlink(dest);

        if (params.validate != null)
            validate_source();

        copy_contents();
    }

    result.changed();
}

if (set_file_attributes(module, dest))
    result.changed();

module.exit_json();
