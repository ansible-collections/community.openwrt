// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { AnsibleModule } from 'basic';

const module = AnsibleModule({
    argument_spec: {
        name:         { type: 'str', required: true, aliases: [ 'pkg' ] },
        state:        { type: 'str', default: 'present',
                        choices: [ 'absent', 'installed', 'present', 'removed' ] },
        force:        { type: 'str',
                        choices: [ 'depends', 'maintainer', 'reinstall', 'overwrite', 'downgrade',
                                   'space', 'postinstall', 'remove', 'checksum',
                                   'removal-of-dependent-packages' ] },
        update_cache: { type: 'bool' },
        autoremove:   { type: 'bool' },
        nodeps:       { type: 'bool' },
        conf_file:    { type: 'str' },
    },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

// Run a command, failing the module with its output when it does not succeed.
function try_run(args) {
    let res = module.run_command(args);
    if (res.rc != 0)
        module.fail_json(sprintf('%s: %s', join(' ', args), trim(res.stdout + res.stderr)));
    return res;
}

// `opkg status` prints nothing for a package that is not installed.
function is_installed(pkg) {
    return trim(module.run_command([ 'opkg', 'status', pkg ]).stdout) != '';
}

// The packages to act upon, given as a comma-separated list.
function requested_packages() {
    let pkgs = [];
    for (let pkg in split(params.name, ',')) {
        if (pkg != '')
            push(pkgs, pkg);
    }
    return pkgs;
}

// The options that go before the opkg sub-command.
function conf_opt() {
    return params.conf_file != null ? [ '--conf', params.conf_file ] : [];
}

// The options that go after it.
function common_opts() {
    let opts = [];
    if (params.force != null)
        push(opts, `--force-${params.force}`);
    return opts;
}

function install_packages(pkgs) {
    for (let pkg in pkgs) {
        if (is_installed(pkg))
            continue;

        if (!module.check_mode) {
            let cmd = [ 'opkg', ...conf_opt(), 'install', ...common_opts() ];
            if (params.nodeps)
                push(cmd, '--nodeps');
            push(cmd, pkg);

            let res = try_run(cmd);
            if (!is_installed(pkg))
                module.fail_json(sprintf('failed to install %s: %s', pkg, trim(res.stdout + res.stderr)));
        }
        result.changed();
    }
}

function remove_packages(pkgs) {
    for (let pkg in pkgs) {
        if (!is_installed(pkg))
            continue;

        if (!module.check_mode) {
            let cmd = [ 'opkg', 'remove', ...common_opts() ];
            if (params.autoremove)
                push(cmd, '--autoremove');
            if (params.nodeps)
                push(cmd, '--nodeps');
            push(cmd, pkg);

            let res = try_run(cmd);
            if (is_installed(pkg))
                module.fail_json(sprintf('failed to remove %s: %s', pkg, trim(res.stdout + res.stderr)));
        }
        result.changed();
    }
}

// ---- main -----------------------------------------------------------------

if (params.update_cache && !module.check_mode)
    try_run([ 'opkg', ...conf_opt(), 'update' ]);

let packages = requested_packages();

if (params.state in [ 'present', 'installed' ])
    install_packages(packages);
else
    remove_packages(packages);

module.exit_json();
