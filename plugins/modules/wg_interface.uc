// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { cursor } from 'uci';
import { connect } from 'ubus';
import { AnsibleModule } from '_basic';
import { diff_entry, section_values, upsert_section } from '_uci';
import { peer_section, render_template } from '_wg';

const PROTOCOLS = [ 'wireguard', 'amneziawg' ];
const AWG_OPTIONS = [
    'awg_jc', 'awg_jmin', 'awg_jmax',
    'awg_s1', 'awg_s2', 'awg_s3', 'awg_s4',
    'awg_h1', 'awg_h2', 'awg_h3', 'awg_h4',
    'awg_i1', 'awg_i2', 'awg_i3', 'awg_i4', 'awg_i5',
    'awg_header_protection_key', 'awg_content_padding_addition',
    'awg_rekey_after_time', 'awg_rekey_timeout', 'awg_reject_after_time',
    'awg_keepalive_timeout', 'awg_max_handshake_attempts',
    'awg_random_trailers', 'awg_disable_cookies',
];

const module = AnsibleModule({
    argument_spec: {
        proto: { type: 'str', choices: PROTOCOLS, default: 'wireguard' },
        state: { type: 'str', choices: [ 'present', 'absent' ], default: 'present' },
        interfaces: {
            type: 'list', elements: 'dict', required: true,
            options: {
                name: { type: 'str', required: true },
                state: { type: 'str', choices: [ 'present', 'absent' ] },
                proto: { type: 'str', choices: PROTOCOLS },
                listen_port: { type: 'int' },
                addresses: { type: 'list', elements: 'str' },
                mtu: { type: 'int' },
                metric: { type: 'int' },
                dns: { type: 'list', elements: 'str' },
                peerdns: { type: 'bool' },
                dns_metric: { type: 'int' },
                awg_tuning: { type: 'dict' },
            },
        },
        managed_interfaces: { type: 'list', elements: 'str' },
        force_rekey: { type: 'bool', default: false },
        force_psk_rekey: { type: 'bool', default: false },
        manage_firewall: { type: 'bool', default: true },
        peers: {
            type: 'list', elements: 'dict',
            options: {
                iface: { type: 'str', required: true },
                proto: { type: 'str', choices: PROTOCOLS },
                section: { type: 'str' },
                force_psk_rekey: { type: 'bool', default: false },
            },
        },
        firewall_rule_id_tpl: { type: 'str', default: '{{ iface_name }}_in' },
        firewall_rule_name_tpl: {
            type: 'str', default: 'Allow-Wan-{{ proto }}: {{ iface_name }}',
        },
        peer_id_tpl: {
            type: 'str',
            default: '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}',
        },
    },
    supports_check_mode: true,
});

const params = module.params;
let output = {
    public_key: '', interfaces: [], psks: [], firewall_changed: false,
    removed_interfaces: [],
};
let diffs = [];

function fail(msg) {
    module.fail_json({ ...output, msg: msg });
}

function checked(u, value, action) {
    if (value == null)
        fail(`${action}: ${u.error() ?? 'UCI operation failed'}`);
    return value;
}

function ubus_call(object, method, payload) {
    let connection = connect();
    if (connection == null)
        return null;
    try {
        let response = connection.call(object, method, payload ?? {});
        if (response == null && object != 'wireguard')
            return ubus_call('wireguard', method, payload);
        return response;
    } catch (e) {
        return object == 'wireguard' ? null : ubus_call('wireguard', method, payload);
    }
}

function resolve_identity(u, managed, proto) {
    let private_key = '';
    let distinct = {};
    for (let name in managed) {
        let current = u.get('network', name, 'private_key');
        if (current != null && current != '') {
            distinct[current] = true;
            if (private_key == '')
                private_key = current;
        }
    }
    if (!params.force_rekey && length(keys(distinct)) > 1)
        fail(`identity key mismatch across managed interfaces: ${length(keys(distinct))} distinct keys; use force_rekey to replace`);

    if (private_key == '' || params.force_rekey) {
        let generated = ubus_call(proto, 'genkey', {});
        if (generated == null || generated.private == null)
            fail(`failed to generate identity key via ubus ${proto}.genkey`);
        private_key = generated.private;
        output.changed = true;
    }

    let public_key = ubus_call(proto, 'pubkey', { private: private_key });
    if (public_key == null || public_key.public == null)
        fail(`failed to derive public key via ubus ${proto}.pubkey`);
    return { private: private_key, public: public_key.public };
}

function add_diff(config, section, section_type, before, after, redact_keys) {
    if (module.diff_mode)
        push(diffs, diff_entry(config, section, section_type, before, after, redact_keys));
}

function delete_interface(u, iface, proto) {
    let removed = false;
    let network = u.get_all('network') ?? {};
    for (let section in network) {
        if (network[section]['.type'] == `${proto}_${iface.name}`) {
            let before = section_values(network[section]);
            checked(u, u.delete('network', section), `cannot delete network.${section}`);
            add_diff('network', section, network[section]['.type'], before, {}, [ 'preshared_key' ]);
            removed = true;
        }
    }

    if (params.manage_firewall) {
        let firewall_section = render_template(params.firewall_rule_id_tpl, {
            iface_name: iface.name, proto: proto, listen_port: iface.listen_port,
        });
        let current = u.get_all('firewall', firewall_section);
        if (current != null) {
            checked(u, u.delete('firewall', firewall_section),
                    `cannot delete firewall.${firewall_section}`);
            add_diff('firewall', firewall_section, current['.type'], section_values(current), {}, null);
            output.firewall_changed = true;
            removed = true;
        }
    }

    let current = u.get_all('network', iface.name);
    if (current != null) {
        checked(u, u.delete('network', iface.name), `cannot delete network.${iface.name}`);
        add_diff('network', iface.name, current['.type'], section_values(current), {}, [ 'private_key' ]);
        removed = true;
    }
    if (removed) {
        output.changed = true;
        push(output.removed_interfaces, iface.name);
    }
}

function interface_options(iface, proto) {
    let wanted = {
        proto: proto,
        listen_port: iface.listen_port,
        addresses: iface.addresses,
        mtu: iface.mtu,
        metric: iface.metric,
        dns: iface.dns,
        peerdns: iface.peerdns,
        dns_metric: iface.dns_metric,
    };
    if (proto == 'amneziawg') {
        for (let name in AWG_OPTIONS)
            wanted[name] = '';
        for (let name in iface.awg_tuning ?? {})
            wanted[name] = iface.awg_tuning[name];
    }
    return wanted;
}

function upsert_interface(u, iface, proto) {
    let update = upsert_section(u, 'network', iface.name, 'interface',
                                interface_options(iface, proto), {});
    if (update.error != null)
        fail(`cannot update network.${iface.name}: ${update.error}`);
    if (update.changed) {
        output.changed = true;
        add_diff('network', iface.name, 'interface', update.before, update.after, [ 'private_key' ]);
    }
    push(output.interfaces, iface.name);

    if (!params.manage_firewall || iface.listen_port == null)
        return;
    let scope = { iface_name: iface.name, proto: proto, listen_port: iface.listen_port };
    let section = render_template(params.firewall_rule_id_tpl, scope);
    if (section == '')
        fail('firewall_rule_id_tpl rendered an empty section name');
    let wanted = {
        name: render_template(params.firewall_rule_name_tpl, scope),
        src: 'wan', proto: 'udp', dest_port: iface.listen_port, target: 'ACCEPT',
    };
    let firewall_update = upsert_section(u, 'firewall', section, 'rule', wanted, {});
    if (firewall_update.error != null)
        fail(`cannot update firewall.${section}: ${firewall_update.error}`);
    if (firewall_update.changed) {
        output.changed = true;
        output.firewall_changed = true;
        add_diff('firewall', section, 'rule', firewall_update.before, firewall_update.after, null);
    }
}

try {
    let u = cursor();
    if (u == null)
        fail('failed to open UCI cursor');

    let managed = params.managed_interfaces ?? [];
    if (length(managed) == 0) {
        let seen = {};
        for (let iface in params.interfaces) {
            if ((iface.state ?? params.state) != 'absent' && !seen[iface.name]) {
                push(managed, iface.name);
                seen[iface.name] = true;
            }
        }
    }

    let any_present = false;
    let key_proto = params.proto;
    for (let iface in params.interfaces) {
        if (iface.proto != null)
            key_proto = iface.proto;
        if ((iface.state ?? params.state) != 'absent')
            any_present = true;
    }
    let identity = null;
    if (any_present || length(managed) > 0) {
        identity = resolve_identity(u, managed, key_proto);
        output.public_key = identity.public;
        for (let name in managed) {
            let current = u.get('network', name, 'private_key');
            if (params.force_rekey || current == null || current == '') {
                if (u.get_all('network', name) == null)
                    checked(u, u.set('network', name, 'interface'), `cannot create network.${name}`);
                checked(u, u.set('network', name, 'private_key', identity.private),
                        `cannot set network.${name}.private_key`);
                output.changed = true;
            }
        }
    }

    for (let iface in params.interfaces) {
        let proto = iface.proto ?? params.proto;
        if ((iface.state ?? params.state) == 'absent')
            delete_interface(u, iface, proto);
        else
            upsert_interface(u, iface, proto);
    }

    for (let peer in params.peers ?? []) {
        let proto = peer.proto ?? params.proto;
        let section = peer_section(params.peer_id_tpl, peer.iface, peer.section, proto);
        if (section == '')
            fail('peer_id_tpl rendered an empty section name');
        let psk = !params.force_psk_rekey && !peer.force_psk_rekey
            ? u.get('network', section, 'preshared_key') : null;
        if (psk == null || psk == '') {
            let generated = ubus_call(proto, 'genpsk', {});
            if (generated == null || generated.preshared == null)
                fail(`failed to generate PSK via ubus ${proto}.genpsk`);
            psk = generated.preshared;
            output.changed = true;
        }
        push(output.psks, psk);
    }

    if (output.changed && !module.check_mode) {
        checked(u, u.save('network'), 'cannot save network configuration');
        checked(u, u.commit('network'), 'cannot commit network configuration');
        if (params.manage_firewall) {
            checked(u, u.save('firewall'), 'cannot save firewall configuration');
            checked(u, u.commit('firewall'), 'cannot commit firewall configuration');
        }
    }
    if (length(diffs) > 0)
        output.diff = diffs;
    output.msg = 'wg interfaces configured';
    module.exit_json(output);
} catch (e) {
    fail(`wg_interface error: ${e}`);
}
