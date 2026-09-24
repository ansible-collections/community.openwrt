// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2026 Sebastian Hamann
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { chmod, chown, readfile, rename, stat, unlink, writefile } from 'fs';
import { AnsibleModule } from '_basic';

const GROUP_FILE = '/etc/group';
const PASSWD_FILE = '/etc/passwd';

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
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// ---- /etc/group and /etc/passwd -------------------------------------------

// Read a colon-separated database, one entry per line, keeping each line as
// written so that the entries left untouched are written back unchanged.
function read_entries(path) {
    let content = readfile(path);
    if (content == null)
        module.fail_json(`cannot read ${path}`);

    let lines = split(content, '\n');
    if (lines[length(lines) - 1] == '')
        pop(lines);

    return map(lines, (line) => ({ line: line, fields: split(line, ':') }));
}

// The numeric ID held in the given field of an entry, null when there is none.
function id_field(entry, index) {
    let value = entry.fields[index];
    return value != null && match(value, /^[0-9]+$/) ? int(value) : null;
}

function names_of(entries) {
    return map(entries, (entry) => entry.fields[0]);
}

function find_group(groups, name) {
    return filter(groups, (group) => group.fields[0] == name)[0];
}

// The names of the groups other than `name` holding the given GID.
function groups_with_gid(groups, gid, name) {
    return names_of(filter(groups, (group) => id_field(group, 2) == gid && group.fields[0] != name));
}

// The names of the users having the given GID as their primary group.
function users_with_primary_gid(gid) {
    return names_of(filter(read_entries(PASSWD_FILE), (user) => id_field(user, 3) == gid));
}

// The first GID in the configured range not held by any group.
function unused_gid(groups) {
    let range = params.system ? GID_RANGE_SYSTEM : GID_RANGE_REGULAR;
    let gid_min = params.gid_min != null ? params.gid_min : range.min;
    let gid_max = params.gid_max != null ? params.gid_max : range.max;

    let used = {};
    for (let group in groups)
        used[id_field(group, 2)] = true;

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

// Replace the group file, through a temporary file renamed over it so that the
// file is never seen half-written, keeping its ownership and permissions.
function write_groups(groups) {
    let info = stat(GROUP_FILE);
    let tmp = `${GROUP_FILE}.ansible_tmp`;
    let content = join('', map(groups, (group) => `${group.line}\n`));

    if (writefile(tmp, content) == null ||
        !chmod(tmp, info.mode) || !chown(tmp, info.uid, info.gid) ||
        !rename(tmp, GROUP_FILE)) {
        unlink(tmp);
        module.fail_json(`cannot write ${GROUP_FILE}`);
    }
}

// ---- operations -----------------------------------------------------------

function group_absent(groups) {
    let group = find_group(groups, params.name);
    if (group == null)
        return;

    if (!params.force) {
        let users = users_with_primary_gid(id_field(group, 2));
        if (length(users) > 0)
            module.fail_json(`cannot remove the primary group of user '${users[0]}'`);
    }

    if (!module.check_mode)
        write_groups(filter(groups, (g) => g != group));

    result.changed();
}

function group_present(groups) {
    let group = find_group(groups, params.name);
    let gid = params.gid;

    if (group == null) {
        if (gid == null)
            gid = unused_gid(groups);
        else
            ensure_gid_unique(groups, gid);

        if (!module.check_mode)
            write_groups([ ...groups, { line: `${params.name}:x:${gid}:` } ]);

        result.update({ gid: gid });
        result.changed();
        return;
    }

    let current_gid = id_field(group, 2);
    if (gid == null || gid == current_gid) {
        result.update({ gid: current_gid });
        return;
    }

    ensure_gid_unique(groups, gid);

    if (!module.check_mode) {
        let fields = [ ...group.fields ];
        fields[2] = gid;
        group.line = join(':', fields);
        write_groups(groups);
    }

    result.update({ gid: gid });
    result.changed();
}

// ---- main -----------------------------------------------------------------

if (params.state == 'present' && params.non_unique && params.gid == null)
    module.fail_json('non_unique is `true` but all of the following are missing: gid');

result.update({ name: params.name, state: params.state });

let groups = read_entries(GROUP_FILE);

if (params.state == 'present') {
    result.update({ system: params.system });
    group_present(groups);
}
else
    group_absent(groups);

module.exit_json();
