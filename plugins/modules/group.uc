// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2026 Sebastian Hamann
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { chmod, chown, open, readfile, rename, stat, unlink } from 'fs';
import { AnsibleModule, process_id } from '_basic';

const GROUP_FILE = '/etc/group';
const PASSWD_FILE = '/etc/passwd';

const GROUP_FIELDS = [ 'name', 'password', 'gid', 'members' ];
const PASSWD_FIELDS = [ 'name', 'password', 'uid', 'gid', 'gecos', 'home', 'shell' ];
const ID_FIELDS = [ 'uid', 'gid' ];

const GID_RANGE_REGULAR = { min: 1000, max: 65535 };
// Several OpenWrt packages add a group with a fixed ID.
// 600 was chosen so that ID collision with packages are unlikely.
const GID_RANGE_SYSTEM = { min: 600, max: 999 };

const module = AnsibleModule({
    argument_spec: {
        name:       { type: 'str', required: true },
        gid:        { type: 'int' },
        gid_max:    { type: 'int' },
        gid_min:    { type: 'int' },
        state:      { type: 'str', default: 'present', choices: [ 'absent', 'present' ] },
        force:      { type: 'bool', default: false },
        system:     { type: 'bool', default: false },
        non_unique: { type: 'bool', default: false },
    },
    required_if: [ [ 'non_unique', true, [ 'gid' ] ] ],
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// ---- /etc/group and /etc/passwd -------------------------------------------

// The ID held in a field, as libc reads it: digits only, an empty field being 0.
// null when the field holds anything else.
function to_id(value) {
    if (!match(value, /^[0-9]*$/))
        return null;
    return value == '' ? 0 : int(value);
}

// Read a colon-separated database, one entry per line, into objects holding
// the given fields, parsed as musl does: the last field takes the rest of the
// line, and the IDs are numbers. A line musl skips is kept as `{ line }` alone,
// so that it matches no name nor ID. With `warnings` set, skipped lines and empty
// IDs are warned about. Each line is also kept as written so that the entries
// left untouched are written back unchanged.
function read_entries(path, names, warnings) {
    let content = readfile(path);
    if (content == null)
        module.fail_json(`cannot read ${path}`);

    let lines = split(content, '\n');
    if (lines[length(lines) - 1] == '')
        pop(lines);

    return map(lines, (line, index) => {
        let warn = (msg) => {
            if (warnings)
                module.warn(`${path}, line ${index + 1}: ${msg}`);
        };
        let skip = (reason) => {
            warn(`entry ignored, ${reason}`);
            return { line: line };
        };

        let values = split(line, ':', length(names));
        if (length(values) != length(names))
            return skip(`expected ${length(names)} fields, found ${length(values)}`);

        let entry = { line: line };
        let empty_ids = [];
        for (let i = 0; i < length(names); i++) {
            let value = values[i];
            if (names[i] in ID_FIELDS) {
                if (value == '')
                    push(empty_ids, names[i]);
                value = to_id(value);
                if (value == null)
                    return skip(`${names[i]} is not a number`);
            }
            entry[names[i]] = value;
        }

        for (let name in empty_ids)
            warn(`empty ${name} read as 0`);
        return entry;
    });
}

// /etc/group is the database this module manages, so its oddities are warned
// about. /etc/passwd is only consulted, and taken as it is.
function read_groups() {
    return read_entries(GROUP_FILE, GROUP_FIELDS, true);
}

function read_users() {
    return read_entries(PASSWD_FILE, PASSWD_FIELDS);
}

function names_of(entries) {
    return map(entries, (entry) => entry.name);
}

function find_group(groups, name) {
    return filter(groups, (group) => group.name == name)[0];
}

// The names of the groups other than `name` holding the given GID.
function groups_with_gid(groups, gid, name) {
    return names_of(filter(groups, (group) => group.gid == gid && group.name != name));
}

// The names of the users having the given GID as their primary group.
function users_with_primary_gid(gid) {
    return names_of(filter(read_users(), (user) => user.gid == gid));
}

// The first GID in the configured range not held by any group.
function unused_gid(groups) {
    let range = params.system ? GID_RANGE_SYSTEM : GID_RANGE_REGULAR;
    let gid_min = params.gid_min != null ? params.gid_min : range.min;
    let gid_max = params.gid_max != null ? params.gid_max : range.max;

    let used = {};
    for (let group in groups)
        used[group.gid] = true;

    for (let gid = gid_min; gid <= gid_max; gid++)
        if (!used[gid])
            return gid;

    module.fail_json(`no unused GID found between ${gid_min} and ${gid_max}`);
}

function ensure_gid_unique(groups, gid) {
    if (params.non_unique)
        return;

    let clashing = groups_with_gid(groups, gid, params.name);
    if (length(clashing) > 0)
        module.fail_json(`GID '${gid}' already exists with group '${join(', ', clashing)}'`);
}

// Replace a database file, through a temporary file renamed over it so that the
// file is never seen half-written, keeping its ownership and permissions. The
// temporary file sits next to the database, as rename() cannot cross filesystems,
// under a name unique per process and per moment so that concurrent runs never
// share it. It is created exclusively: a file, or a symlink, already holding
// that name is neither followed nor overwritten.
function write_entries(path, entries) {
    let info = stat(path);
    let now = clock(true) || clock();
    let tmp = sprintf('%s.ansible_tmp.%s.%d.%d', path, process_id(), now[0], now[1]);
    let content = join('', map(entries, (entry) => `${entry.line}\n`));

    let file = open(tmp, 'wx', 0600);
    if (file == null)
        module.fail_json(`cannot write ${path}`);

    let written = file.write(content) != null;
    if (!file.close() || !written ||
        !chmod(tmp, info.mode) || !chown(tmp, info.uid, info.gid) ||
        !rename(tmp, path)) {
        unlink(tmp);
        module.fail_json(`cannot write ${path}`);
    }
}

// A copy of the entry with its GID replaced, in the line as well.
function with_gid(entry, names, gid) {
    let values = split(entry.line, ':', length(names));
    values[index(names, 'gid')] = gid;
    return { ...entry, gid: gid, line: join(':', values) };
}

// Give the group a new GID, and move the users having the old one as their
// primary group along with it, as groupmod does.
function change_gid(groups, group, gid) {
    write_entries(GROUP_FILE, map(groups, (g) => g == group ? with_gid(g, GROUP_FIELDS, gid) : g));

    let users = read_users();
    let moved = (user) => user.gid == group.gid;
    if (length(filter(users, moved)) > 0)
        write_entries(PASSWD_FILE, map(users, (user) => moved(user) ? with_gid(user, PASSWD_FIELDS, gid) : user));
}

// ---- operations -----------------------------------------------------------

function group_absent(groups) {
    let group = find_group(groups, params.name);
    if (group == null)
        return;

    if (!module.check_mode && !params.force) {
        let users = users_with_primary_gid(group.gid);
        if (length(users) > 0)
            module.fail_json(`cannot remove the primary group of user '${users[0]}'`);
    }

    result.changed();
    if (!module.check_mode)
        write_entries(GROUP_FILE, filter(groups, (g) => g != group));
}

function group_present(groups) {
    let group = find_group(groups, params.name);
    let gid = params.gid;

    if (group == null) {
        if (gid == null)
            gid = unused_gid(groups);
        else
            ensure_gid_unique(groups, gid);

        result.changed();
        if (!module.check_mode)
            write_entries(GROUP_FILE, [ ...groups, { line: `${params.name}:x:${gid}:` } ]);
    }
    else if (gid != null && gid != group.gid) {
        ensure_gid_unique(groups, gid);

        result.changed();
        if (!module.check_mode)
            change_gid(groups, group, gid);
    }
    else
        gid = group.gid;

    result.update({ gid: gid, system: params.system });
}

// MAIN ----------------------------------------------------------------------

if (params.name == '' || match(params.name, /[:\n]/))
    module.fail_json(`'${params.name}' is not a valid group name`);

result.update({ name: params.name, state: params.state });

let groups = read_groups();

if (params.state == 'present')
    group_present(groups);
else
    group_absent(groups);

module.exit_json();
