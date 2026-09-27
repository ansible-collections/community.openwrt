// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// _file.uc — helpers for modules managing filesystem objects, the ucode
// counterpart of _file.sh. It covers the attributes such a module sets on what
// it writes, the backup it takes before writing, and the digests it compares:
//
//   import { FILE_COMMON_ARGS, backup_local, digest, set_file_attributes } from '_file';

import { lstat, readlink, stat } from 'fs';

// The parameters every module setting attributes on a file accepts. Spread it
// into the module's argument_spec:
//
//   argument_spec: { dest: { type: 'str', required: true }, ...FILE_COMMON_ARGS },
export const FILE_COMMON_ARGS = {
    owner:  { type: 'str' },
    group:  { type: 'str' },
    mode:   { type: 'str' },
    follow: { type: 'bool', default: false },
};

// ---- digests --------------------------------------------------------------

// Whether a command exists on the device. The answer is kept, since a module
// asks for the same few commands over and over.
let known_commands = {};
function have(module, cmd) {
    if (known_commands[cmd] == null)
        known_commands[cmd] = module.run_command([ 'command', '-v', cmd ]).rc == 0;

    return known_commands[cmd];
}

// The digest of a file as a hex string, computed with whichever tool the device
// carries. An empty string means no digest could be taken.
export function digest(module, alg, path) {
    let cmd = `${alg}sum`;

    if (have(module, cmd)) {
        let res = module.run_command([ cmd, '--', path ]);
        // The output is "<digest>  <path>".
        return res.rc == 0 ? split(trim(res.stdout), ' ')[0] : '';
    }

    if (have(module, 'openssl')) {
        let res = module.run_command([ 'openssl', 'dgst', '-hex', `-${alg}`, path ]);
        // The output is "<ALG>(<path>)= <digest>".
        let found = res.rc == 0 ? match(res.stdout, /= *([0-9a-fA-F]+)/) : null;
        return found != null ? found[1] : '';
    }

    return '';
};

// ---- backup ---------------------------------------------------------------

// ucode has no getpid(); Linux exposes the process id through /proc/self.
function process_id() {
    let pid = readlink('/proc/self');
    return pid != null ? pid : 'unknown';
}

// Copy a file next to itself, under a name carrying the moment it was taken,
// and return the name of the copy. A file that is not there is not backed up,
// and the empty string says so.
export function backup_local(module, path) {
    if (stat(path) == null)
        return '';

    let now = localtime();
    let backup = sprintf('%s.%s.%04d-%02d-%02d@%02d:%02d:%02d~', path, process_id(),
                         now.year, now.mon, now.mday, now.hour, now.min, now.sec);

    module.run_command([ 'cp', '-a', '--', path, backup ], { check_rc: true });

    return backup;
};

// ---- attributes -----------------------------------------------------------

// The permissions as chmod(1) is to receive them. A numeric mode is read the
// way printf(1) reads it, which is what turns the 420 of a `mode: 0644` written
// unquoted in a playbook back into 0644. A symbolic mode such as u+rwx has no
// numeric reading and is passed on untouched.
function chmod_mode(mode) {
    if (!match(mode, /^[0-9]+$/))
        return mode;

    // A leading zero is the octal prefix it is in C.
    let base = substr(mode, 0, 1) == '0' ? 8 : 10;
    let value = 0;

    for (let i = 0; i < length(mode); i++) {
        let digit = ord(mode, i) - 48;
        if (digit >= base)
            return mode;

        value = value * base + digit;
    }

    return sprintf('%04o', value);
}

// Whether the path is a symbolic link, rather than whatever it points at.
function is_link(path) {
    let info = lstat(path);
    return info != null && info.type == 'link';
}

// The ownership and permissions of a path, for telling whether setting them
// changed anything.
function attributes_of(path, follow) {
    let info = follow ? stat(path) : lstat(path);
    return info != null ? sprintf('%d:%d:%d', info.uid, info.gid, info.mode) : '';
}

// Set the owner, group and mode the module was asked for on `path`. `overrides`
// replaces individual attributes, as a module giving a mode of its own to the
// directories it creates does. Nothing is set in check mode. Returns whether
// anything actually changed.
export function set_file_attributes(module, path, overrides) {
    if (module.check_mode)
        return false;

    let params = module.params;
    let attrs = {
        owner: params.owner,
        group: params.group,
        mode: params.mode,
        follow: params.follow,
        ...(overrides != null ? overrides : {}),
    };

    // A mode that reaches the module as a boolean stands for no mode at all.
    if (attrs.mode == 'False' || attrs.mode == 'false')
        attrs.mode = null;

    if (attrs.owner == null && attrs.group == null && attrs.mode == null)
        return false;

    let before = attributes_of(path, attrs.follow);
    // Without `follow`, the attributes belong to the link and not to its target.
    let on_link = attrs.follow ? [] : [ '-h' ];

    if (attrs.owner != null) {
        let res = module.run_command([ 'chown', ...on_link, attrs.owner, '--', path ]);
        if (res.rc != 0)
            module.fail_json(`chown (${path}) failed: ${trim(res.stderr)}`);
    }

    if (attrs.group != null) {
        let res = module.run_command([ 'chgrp', ...on_link, attrs.group, '--', path ]);
        if (res.rc != 0)
            module.fail_json(`chgrp (${path}) failed: ${trim(res.stderr)}`);
    }

    // There is no mode to set on a link that is not being followed.
    if (attrs.mode != null && (attrs.follow || !is_link(path))) {
        let res = module.run_command([ 'chmod', chmod_mode(attrs.mode), '--', path ]);
        if (res.rc != 0)
            module.fail_json(`chmod (${path}) failed: ${trim(res.stderr)}`);
    }

    return before != attributes_of(path, attrs.follow);
};
