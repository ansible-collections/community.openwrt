// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { cursor } from 'uci';
import { AnsibleModule } from '_basic';
import { diff_entry, section_values, upsert_section } from '_uci';
import { peer_protocol, peer_section } from '_wg';

const module = AnsibleModule({
    argument_spec: {
        proto: { type: 'str', choices: [ 'wireguard', 'amneziawg' ] },
        state: { type: 'str', choices: [ 'present', 'absent' ], default: 'present' },
        peers: {
            type: 'list', elements: 'dict', required: true,
            options: {
                iface: { type: 'str', required: true },
                proto: { type: 'str', choices: [ 'wireguard', 'amneziawg' ] },
                state: { type: 'str', choices: [ 'present', 'absent' ] },
                section: { type: 'str' },
                description: { type: 'str' },
                public_key: { type: 'str' },
                preshared_key: { type: 'str' },
                endpoint_host: { type: 'str' },
                endpoint_port: { type: 'int' },
                persistent_keepalive: { type: 'int' },
                route_allowed_ips: { type: 'bool', default: false },
                allowed_ips: { type: 'list', elements: 'str', default: [ '0.0.0.0/0', '::/0' ] },
            },
        },
        peer_id_template: {
            type: 'str',
            default: '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}',
        },
    },
    supports_check_mode: true,
});

const params = module.params;
let output = { peers: [], removed: [] };
let diffs = [];

function fail(msg) {
    module.fail_json({ ...output, msg: msg });
}

function peer_proto(u, peer) {
    return peer_protocol(u, peer, params.proto);
}

function section_id(peer, proto) {
    let section;
    try {
        section = peer_section(params.peer_id_template, peer.iface, peer.section, proto);
    } catch (e) {
        fail(`peer_id_template: ${e.message}`);
    }
    if (section == '')
        fail('peer_id_template rendered an empty section name');
    return section;
}

function add_diff(section, section_type, before, after, before_type) {
    if (!module.diff_mode)
        return;
    let entry = diff_entry('network', section, section_type, before, after, [ 'preshared_key' ]);
    if (before_type != null)
        entry.before_header = `network.${section}=${before_type}`;
    push(diffs, entry);
}

function remove_peer(u, peer, proto) {
    let section = section_id(peer, proto);
    let current = u.get_all('network', section);
    if (current == null)
        return;

    let before = section_values(current);
    if (u.delete('network', section) == null)
        fail(`cannot delete network.${section}: ${u.error() ?? 'UCI operation failed'}`);
    output.changed = true;
    push(output.removed, section);
    add_diff(section, current['.type'], before, {});
}

function upsert_peer(u, peer, proto) {
    let section = section_id(peer, proto);
    if (peer.public_key == null || peer.public_key == '')
        fail(`public_key is required for present peer ${section}`);
    let section_type = `${proto}_${peer.iface}`;
    let suffix = peer.section ?? '';
    let wanted = {
        description: peer.description ?? (suffix != '' ? suffix : peer.iface),
        public_key: peer.public_key,
        endpoint_host: peer.endpoint_host ?? '',
        endpoint_port: peer.endpoint_port,
        persistent_keepalive: peer.persistent_keepalive,
        route_allowed_ips: peer.route_allowed_ips,
        allowed_ips: peer.allowed_ips,
    };
    if (peer.preshared_key != null && peer.preshared_key != '')
        wanted.preshared_key = peer.preshared_key;

    let dropped = {};
    if (peer.preshared_key == null || peer.preshared_key == '')
        dropped.preshared_key = true;

    // A protocol change only changes the section type, which UCI changes in place.
    let current_type = u.get('network', section);
    let retyped = current_type != null && current_type != section_type;
    if (retyped && u.set('network', section, section_type) == null)
        fail(`cannot change the type of network.${section}: ${u.error() ?? 'UCI operation failed'}`);

    let update = upsert_section(u, 'network', section, section_type, wanted, dropped);
    if (update.error != null)
        fail(`cannot update network.${section}: ${update.error}`);
    if (update.changed || retyped) {
        output.changed = true;
        add_diff(section, section_type, update.before, update.after, retyped ? current_type : null);
    }
    push(output.peers, section);
}

// END-OF-UNIT-TESTABLES

try {
    let u = cursor();
    if (u == null)
        fail('failed to open UCI cursor');

    for (let peer in params.peers) {
        let proto = peer_proto(u, peer);
        let state = peer.state ?? params.state;
        if (state == 'absent')
            remove_peer(u, peer, proto);
        else
            upsert_peer(u, peer, proto);
    }

    if (output.changed && !module.check_mode) {
        if (u.save('network') == null || u.commit('network') == null)
            fail(`cannot save network configuration: ${u.error() ?? 'UCI operation failed'}`);
    }
    if (length(diffs) > 0)
        output.diff = diffs;
    output.msg = 'wg peers configured';
    module.exit_json(output);
} catch (e) {
    fail(`wg_peer error: ${e}`);
}
