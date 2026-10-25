// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { readfile, stat, unlink } from 'fs';
import { AnsibleModule, deep_equal } from '_basic';
import { replace_file } from '_file';

const KEYS_DIR = '/etc/apk/keys';

const module = AnsibleModule({
    argument_spec: {
        url:          { type: 'str', required: true },
        tag:          { type: 'str' },
        state:        { type: 'str', default: 'present', choices: [ 'absent', 'present' ] },
        file:         { type: 'str', default: '/etc/apk/repositories.d/customfeeds.list' },
        key:          { type: 'str' },
        key_url:      { type: 'str' },
        key_name:     { type: 'str' },
        update_cache: { type: 'bool', default: false },
    },
    mutually_exclusive: [ [ 'key', 'key_url' ] ],
    required_by: { key: [ 'key_name' ], key_url: [ 'key_name' ] },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// ---- files ----------------------------------------------------------------

function write_file(path, content) {
    try {
        replace_file(path, content);
    } catch (e) {
        module.fail_json(e.message);
    }
}

// ---- feeds ----------------------------------------------------------------

// A line of a repositories file reads `[@tag] url`. Comments and blank lines
// hold no feed and yield null.
function parse_feed(line) {
    let words = filter(split(trim(line), /[ \t]+/), (w) => w != '');
    if (length(words) == 0 || substr(words[0], 0, 1) == '#')
        return null;

    let tag = null;
    if (substr(words[0], 0, 1) == '@')
        tag = substr(shift(words), 1);

    return { tag: tag, url: join(' ', words) };
}

function feed_line(url, tag) {
    return tag != null ? `@${tag} ${url}` : url;
}

function same_url(line, url) {
    let feed = parse_feed(line);
    return feed != null && feed.url == url;
}

// The lines of the repositories file once the feed is in place: the first line
// holding its URL is rewritten as wanted, any further one dropped, and the feed
// appended when no line holds it.
function lines_present(lines, url, tag) {
    let wanted = feed_line(url, tag);
    let found = false;
    let out = [];

    for (let line in lines) {
        if (!same_url(line, url))
            push(out, line);
        else if (!found) {
            push(out, wanted);
            found = true;
        }
    }
    if (!found)
        push(out, wanted);

    return out;
}

function lines_absent(lines, url) {
    return filter(lines, (line) => !same_url(line, url));
}

function read_lines(path) {
    let content = readfile(path);
    if (content == null)
        return null;

    let lines = split(content, '\n');
    if (lines[length(lines) - 1] == '')
        pop(lines);
    return lines;
}

function manage_feed() {
    let lines = read_lines(params.file);
    let url = trim(params.url);

    if (lines == null) {
        if (stat(params.file) != null)
            module.fail_json(`cannot read ${params.file}`);
        if (params.state == 'absent')
            return;
        lines = [];
    }

    let wanted = params.state == 'present' ? lines_present(lines, url, params.tag) : lines_absent(lines, url);
    if (deep_equal(wanted, lines))
        return;

    result.changed();
    if (!module.check_mode)
        write_file(params.file, join('', map(wanted, (line) => `${line}\n`)));
}

// ---- keys -----------------------------------------------------------------

function key_path() {
    let name = params.key_name;
    if (name == '' || name == '.' || name == '..' || index(name, '/') >= 0)
        module.fail_json(`'${name}' is not a valid key name`);
    return `${KEYS_DIR}/${name}`;
}

function fetch_key(url) {
    let res = module.run_command([ 'wget', '-q', '-O', '-', url ]);
    if (res.rc != 0)
        module.fail_json({ msg: `failed to download the key from ${url}`, rc: res.rc, stderr: res.stderr });
    return res.stdout;
}

function wanted_key() {
    let content = params.key != null ? params.key : fetch_key(params.key_url);
    if (!match(content, /-----BEGIN [A-Z ]*KEY-----/))
        module.fail_json('the key is not a PEM encoded key');
    return substr(content, -1) == '\n' ? content : `${content}\n`;
}

function key_present(path) {
    let content = wanted_key();
    if (readfile(path) == content)
        return;

    result.changed();
    if (!module.check_mode)
        write_file(path, content);
}

function key_absent(path) {
    if (stat(path) == null)
        return;

    result.changed();
    if (!module.check_mode && !unlink(path))
        module.fail_json(`cannot remove ${path}`);
}

// ---- main -----------------------------------------------------------------

if (module.run_command([ 'apk', '--version' ]).rc != 0)
    module.fail_json('apk is not available on this device');

if (trim(params.url) == '' || match(params.url, /[\n#]/))
    module.fail_json(`'${params.url}' is not a valid feed URL`);
if (params.tag != null && !match(params.tag, /^[A-Za-z0-9_.-]+$/))
    module.fail_json(`'${params.tag}' is not a valid tag`);

result.update({ url: trim(params.url), tag: params.tag, state: params.state, file: params.file });

let key_file = params.key_name != null ? key_path() : null;
if (key_file != null)
    result.update({ key_file: key_file });

if (params.state == 'present') {
    if (params.key != null || params.key_url != null)
        key_present(key_file);
    manage_feed();
}
else {
    manage_feed();
    if (key_file != null)
        key_absent(key_file);
}

if (params.update_cache && result.is_changed() && !module.check_mode)
    module.run_command([ 'apk', 'update' ], { check_rc: true });

module.exit_json();
