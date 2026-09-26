// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { access, readfile, stat } from 'fs';
import { connect } from 'ubus';
import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        // Handled by the action plugin.
        expose_secrets: { type: 'bool', default: false },
    },
    supports_check_mode: true,
});

// The facts from ubus: fact name, ubus object and method.
const UBUS_FACTS = [
    [ 'openwrt_info',     'system',           'info' ],
    [ 'openwrt_devices',  'network.device',   'status' ],
    [ 'openwrt_services', 'service',          'list' ],
    [ 'openwrt_board',    'system',           'board' ],
    [ 'openwrt_wireless', 'network.wireless', 'status' ],
];

const INTERFACE_PREFIX = 'network.interface.';

// Split a line into words, as the shell does with an unquoted expansion.
function words_of(line) {
    let trimmed = trim(line, ' \t\n');
    return trimmed == '' ? [] : split(trimmed, /[ \t\n]+/);
}

function is_file(path) {
    let info = stat(path);
    return info != null && info.type == 'file';
}

// ---- distribution ---------------------------------------------------------

// The variables assigned in a file of shell assignments, such as
// /etc/openwrt_release, with the quotes around their values removed.
function shell_vars(path) {
    let vars = {};
    let content = readfile(path);
    if (content == null)
        return vars;

    for (let line in split(content, '\n')) {
        let m = match(line, /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
        if (m == null)
            continue;

        let value = m[2];
        let q = substr(value, 0, 1);
        if ((q == "'" || q == '"') && length(value) >= 2 && substr(value, -1) == q)
            value = substr(value, 1, length(value) - 2);
        vars[m[1]] = value;
    }
    return vars;
}

function distribution() {
    let dist = { name: 'OpenWrt', version: 'NA', release: 'NA' };

    if (is_file('/etc/openwrt_release')) {
        let vars = shell_vars('/etc/openwrt_release');
        dist.name = vars.DISTRIB_ID || dist.name;
        dist.version = vars.DISTRIB_RELEASE || dist.version;
        dist.release = vars.DISTRIB_CODENAME || dist.release;
    }
    else if (is_file('/etc/os-release')) {
        let vars = shell_vars('/etc/os-release');
        dist.name = vars.NAME || dist.name;
        dist.version = vars.VERSION_ID || dist.version;
    }

    return dist;
}

function pkg_mgr() {
    for (let mgr in [ 'apk', 'opkg' ])
        if (module.run_command([ 'which', mgr ]).rc == 0)
            return mgr;
    return null;
}

function is_chroot() {
    let root = stat('/');

    if (access('/proc/1/root/.', 'r')) {
        let init_root = stat('/proc/1/root/.');
        return !(root != null && init_root != null &&
                 root.dev.major == init_root.dev.major && root.dev.minor == init_root.dev.minor &&
                 root.inode == init_root.inode);
    }

    return !(root != null && root.inode == 2);
}

// ---- date and time --------------------------------------------------------

// The output of `date` with the given arguments, split into the named fields.
function date_fields(args, names) {
    let words = words_of(module.run_command([ 'date', ...args ]).stdout);
    let fields = {};
    for (let i = 0; i < length(names); i++)
        fields[names[i]] = words[i] ?? '';
    return fields;
}

function date_time() {
    let now = date_fields([ '+%s %6N' ], [ 'epoch', 'us' ]);
    // BusyBox date has no %N; only coreutils-date gives the microseconds.
    let us = match(now.us, /^[0-9]{6}$/) ? now.us : '000000';

    let t = date_fields([ '+%Y %m %d %H %M %S %A %w %W %Z %z', '-d', `@${now.epoch}` ],
                        [ 'year', 'month', 'day', 'hour', 'minute', 'second',
                          'weekday', 'weekday_number', 'weeknumber', 'tz', 'tz_offset' ]);
    let u = date_fields([ '-u', '+%Y %m %d %H %M', '-d', `@${now.epoch}` ],
                        [ 'year', 'month', 'day', 'hour', 'minute' ]);

    let utc = `${u.year}-${u.month}-${u.day}T${u.hour}:${u.minute}:${t.second}`;
    let basic_short = `${t.year}${t.month}${t.day}T${t.hour}${t.minute}${t.second}`;

    let facts = {
        date: `${t.year}-${t.month}-${t.day}`,
        day: t.day,
        epoch: now.epoch,
        epoch_int: now.epoch,
        hour: t.hour,
        iso8601: `${utc}Z`,
        iso8601_basic: `${basic_short}${us}`,
        iso8601_basic_short: basic_short,
        iso8601_micro: `${utc}.${us}Z`,
        minute: t.minute,
        month: t.month,
        second: t.second,
        time: `${t.hour}:${t.minute}:${t.second}`,
        tz: t.tz,
        tz_dst: t.tz,
        tz_offset: t.tz_offset,
        weekday: t.weekday,
        weekday_number: t.weekday_number,
        weeknumber: t.weeknumber,
        year: t.year,
    };

    // Facts without a value are left out.
    for (let name in keys(facts))
        if (facts[name] == '')
            delete facts[name];

    return facts;
}

// ---- ubus -----------------------------------------------------------------

function ubus_facts() {
    let facts = { openwrt_interfaces: {} };

    let conn = connect();
    if (conn == null)
        return facts;

    // An object that exists but returns nothing is reported as empty.
    let status = (object, method) => conn.call(object, method) ?? {};

    for (let fact in UBUS_FACTS)
        if (conn.list(fact[1]) != null)
            facts[fact[0]] = status(fact[1], fact[2]);

    for (let object in conn.list()) {
        if (substr(object, 0, length(INTERFACE_PREFIX)) != INTERFACE_PREFIX)
            continue;

        let parts = split(object, '.');
        facts.openwrt_interfaces[parts[length(parts) - 1]] = status(object, 'status');
    }

    return facts;
}

// ---- main -----------------------------------------------------------------

let dist = distribution();

let facts = {
    ansible_hostname: rtrim(readfile('/proc/sys/kernel/hostname') ?? '', '\n'),
    ansible_distribution: dist.name,
    ansible_distribution_major_version: split(dist.version, '.')[0],
    ansible_distribution_release: dist.release,
    ansible_distribution_version: dist.version,
    ansible_os_family: 'OpenWrt',
    ansible_is_chroot: is_chroot(),
    ansible_date_time: date_time(),
};

let mgr = pkg_mgr();
if (mgr != null)
    facts.ansible_pkg_mgr = mgr;

module.exit_json({ ansible_facts: { ...facts, ...ubus_facts() } });
