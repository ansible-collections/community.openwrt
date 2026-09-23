// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2025 Krzysztof Bialek/Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { stat } from 'fs';
import { AnsibleModule } from 'basic';

const module = AnsibleModule({
    argument_spec: {
        name:               { type: 'str', required: true, aliases: [ 'pkg' ] },
        state:              { type: 'str', default: 'present',
                              choices: [ 'absent', 'installed', 'present', 'removed' ] },
        update_cache:       { type: 'bool', default: false },
        no_cache:           { type: 'bool', default: false },
        force_broken_world: { type: 'bool', default: false },
        allow_untrusted:    { type: 'bool', default: false },
    },
    mutually_exclusive: [ [ 'update_cache', 'no_cache' ] ],
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// ---- helpers --------------------------------------------------------------

// Record the outcome of an apk invocation in the result.
function record(res) {
    result.update({ rc: res.rc, stdout: res.stdout, stderr: res.stderr });
}

// `apk info -e` exits 0 when the package is installed, non-zero otherwise.
function is_installed(pkg) {
    return module.run_command([ 'apk', 'info', '-e', pkg ]).rc == 0;
}

// The packages to act upon, given as a comma-separated list.
function requested_packages() {
    return filter(split(params.name, ','), (pkg) => pkg != '');
}

// A package installed from a local file is registered under the name recorded
// in its metadata, so ask apk for that name before verifying the installation.
function installed_name(pkg) {
    let info = stat(pkg);
    if (info == null || info.type != 'file')
        return pkg;

    let dump = module.run_command([ 'apk', 'adbdump', '--format', 'json', pkg ]);
    let meta;
    try {
        meta = json(dump.stdout);
    } catch (e) {
        meta = null;
    }
    if (type(meta) != 'object' || type(meta.info) != 'object' || meta.info.name == null)
        module.fail_json('could not parse output of apk adbdump');

    return meta.info.name;
}

// ---- operations -----------------------------------------------------------

function install_packages(pkgs) {
    let to_install = [];
    for (let pkg in pkgs) {
        if (!is_installed(pkg))
            push(to_install, pkg);
    }

    if (length(to_install) == 0)
        return;

    if (!module.check_mode) {
        let cmd = [ 'apk' ];
        if (params.update_cache)
            push(cmd, '--update-cache');
        if (params.no_cache)
            push(cmd, '--no-cache');
        if (params.force_broken_world)
            push(cmd, '--force-broken-world');
        if (params.allow_untrusted)
            push(cmd, '--allow-untrusted');
        push(cmd, 'add', ...to_install);

        let res = module.run_command(cmd);
        record(res);

        for (let pkg in to_install) {
            if (!is_installed(installed_name(pkg)))
                module.fail_json(`failed to install ${pkg}: ${res.stdout} ${res.stderr}`);
        }
    }

    result.changed();
}

function remove_packages(pkgs) {
    let to_remove = [];
    for (let pkg in pkgs) {
        if (is_installed(pkg))
            push(to_remove, pkg);
    }

    if (length(to_remove) == 0)
        return;

    if (!module.check_mode) {
        let cmd = [ 'apk' ];
        if (params.no_cache)
            push(cmd, '--no-cache');
        push(cmd, 'del', ...to_remove);

        let res = module.run_command(cmd);
        record(res);

        for (let pkg in to_remove) {
            if (is_installed(pkg))
                module.fail_json(`failed to remove ${pkg}: ${res.stdout} ${res.stderr}`);
        }
    }

    result.changed();
}

// ---- main -----------------------------------------------------------------

result.update({ rc: 0, stdout: '', stderr: '' });

let packages = requested_packages();

if (params.state in ['present', 'installed'])
    install_packages(packages);
else
    remove_packages(packages);

module.exit_json();
