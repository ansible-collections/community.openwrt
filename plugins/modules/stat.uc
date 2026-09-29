// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { access, lstat, readfile, realpath } from 'fs';
import { AnsibleModule } from '_basic';
import { digest, is_link } from '_file';

const module = AnsibleModule({
    argument_spec: {
        path:               { type: 'str', required: true },
        checksum_algorithm: { type: 'str', default: 'sha1', aliases: [ 'checksum_algo', 'checksum' ],
                              choices: [ 'md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512' ] },
        get_checksum:       { type: 'bool', default: true },
        get_md5:            { type: 'bool', default: true },
        get_mime:           { type: 'bool', default: true },
        follow:             { type: 'bool' },
    },
    supports_check_mode: true,
});

const params = module.params;

// ---- helpers --------------------------------------------------------------

// The name an id has in a database laid out as /etc/passwd and /etc/group are,
// or the id itself when it has none - which is what ls(1) shows.
function name_of(database, id) {
    for (let entry in split(readfile(database) ?? '', '\n')) {
        let fields = split(entry, ':');
        if (length(fields) > 2 && fields[2] == `${id}`)
            return fields[0];
    }

    return `${id}`;
}

// The effective user and group ids the module runs with. ucode has no call for
// them, but the process status lists them second on its Uid and Gid lines.
function effective_ids() {
    let status = readfile('/proc/self/status') ?? '';
    let uid = match(status, /\nUid:\t[0-9]+\t([0-9]+)/);
    let gid = match(status, /\nGid:\t[0-9]+\t([0-9]+)/);

    return { uid: uid != null ? +uid[1] : null, gid: gid != null ? +gid[1] : null };
}

// The device number as the single integer the C library's makedev() makes of
// its major and minor parts.
function device_number(dev) {
    return ((dev.major & 0xfff) << 8) | ((dev.major & ~0xfff) << 32) |
           (dev.minor & 0xff) | ((dev.minor & ~0xff) << 12);
}

// What is known about `path`, whose lstat() is `info`.
function facts_of(path, info) {
    let perm = info.perm;
    let ids = effective_ids();

    return {
        path: path,
        exists: true,
        size: info.size,
        mode: sprintf('%04o', info.mode),
        uid: info.uid,
        gid: info.gid,
        pw_name: name_of('/etc/passwd', info.uid),
        gr_name: name_of('/etc/group', info.gid),
        mtime: info.mtime,
        ctime: info.ctime,
        inode: info.inode,
        nlink: info.nlink,
        dev: device_number(info.dev),
        isdir: info.type == 'directory',
        isreg: info.type == 'file',
        islnk: info.type == 'link',
        issock: info.type == 'socket',
        isblk: info.type == 'block',
        ischr: info.type == 'char',
        isfifo: info.type == 'fifo',
        isuid: info.uid == ids.uid,
        isgid: info.gid == ids.gid,
        readable: access(path, 'r') == true,
        writeable: access(path, 'w') == true,
        executable: access(path, 'x') == true,
        rusr: perm.user_read,
        wusr: perm.user_write,
        xusr: perm.user_exec,
        rgrp: perm.group_read,
        wgrp: perm.group_write,
        xgrp: perm.group_exec,
        roth: perm.other_read,
        woth: perm.other_write,
        xoth: perm.other_exec,
        charset: 'unknown',
        mime_type: 'unknown',
    };
}

// The digests of a readable regular file the task asked for. Failing to take
// the checksum is only an error for an algorithm other than the default one.
function digests_of(module, path) {
    let task = module.params;
    let digests = {};

    if (task.get_md5) {
        let md5 = digest(module, 'md5', path);
        if (md5 != '')
            digests.md5 = md5;
    }

    if (task.get_checksum) {
        let alg = task.checksum_algorithm;
        let checksum = digest(module, alg, path);
        if (checksum != '')
            digests.checksum = checksum;
        else if (alg != 'sha1')
            module.fail_json(`Could not hash file '${path}' with algorithm '${alg}'.`);
    }

    return digests;
}

// ---- main -----------------------------------------------------------------

let path = params.path;
let followed = {};

// A link being followed is reported as its target, with the link itself kept
// as the source.
if (params.follow && is_link(path)) {
    let target = realpath(path);
    if (target == null)
        module.exit_json({ stat: { path: path, exists: false } });

    followed = { lnk_source: path };
    path = target;
}

let info = lstat(path);
if (info == null)
    module.exit_json({ stat: { path: path, exists: false } });

let facts = { ...facts_of(path, info), ...followed };
if (facts.isreg && facts.readable)
    facts = { ...facts, ...digests_of(module, path) };

module.exit_json({ stat: facts });
