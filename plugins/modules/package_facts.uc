// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2026 Sebastian Guarino
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {},
    supports_check_mode: true,
});

function have(cmd) {
    return module.run_command([ 'which', cmd ]).rc == 0;
}

function detect_package_manager() {
    if (have('apk'))
        return 'apk';
    if (have('opkg'))
        return 'opkg';
    return null;
}

// A version ending in a release such as -r1 is split into the two.
function add_package(packages, source, name, version) {
    let release = '';
    let dash = rindex(version, '-');
    if (dash >= 0 && substr(version, dash + 1, 1) == 'r') {
        release = substr(version, dash + 1);
        version = substr(version, 0, dash);
    }

    if (packages[name] == null)
        packages[name] = [];
    push(packages[name], { name: name, source: source, release: release, version: version });
}

// `apk query` describes each package in a block of "Field: value" lines.
function apk_packages(packages, output) {
    let name = null;
    for (let line in split(output, '\n')) {
        let field = match(line, /^([A-Za-z]+): (.*)$/);
        if (field == null)
            continue;

        if (field[1] == 'Name')
            name = field[2];
        else if (field[1] == 'Version' && name != null) {
            add_package(packages, 'apk', name, field[2]);
            name = null;
        }
    }
}

// `opkg list-installed` prints one "name - version" line per package.
function opkg_packages(packages, output) {
    for (let line in split(output, '\n')) {
        let sep = index(line, ' - ');
        if (sep < 0)
            continue;

        add_package(packages, 'opkg', substr(line, 0, sep), trim(substr(line, sep + 3)));
    }
}

// ---- main -----------------------------------------------------------------

let pkg_mgr = detect_package_manager();
let packages = {};

if (pkg_mgr != null) {
    let res = pkg_mgr == 'apk'
        ? module.run_command([ 'apk', 'query', '--fields', 'name,version', '--installed', '*' ])
        : module.run_command([ 'opkg', 'list-installed' ]);

    if (res.rc != 0)
        module.fail_json(`Error retrieving package listing (package manager detected: ${pkg_mgr})`);

    if (pkg_mgr == 'apk')
        apk_packages(packages, res.stdout);
    else
        opkg_packages(packages, res.stdout);
}

module.exit_json({ ansible_facts: { packages: packages } });
