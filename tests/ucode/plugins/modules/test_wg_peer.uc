// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach } from 'utest';
import { cursor } from 'uci';
import { mkdir, writefile } from 'fs';
import { module_internals } from 'utils.ansible_module';

const MODULE = '../../plugins/modules/wg_peer.uc';
const SCRATCH = '/tmp/test_wg_peer';
const CONFDIR = `${SCRATCH}/config`;
const SAVEDIR = `${SCRATCH}/delta`;

const NETWORK = `
config interface 'awg1'
	option proto 'amneziawg'

config wireguard_wg0 'peer_wg0'
	option public_key 'OLD'
	option preshared_key 'OLDPSK'
	option description 'old'
`;

let params;
let fn;
let u;

beforeEach(() => {
    mkdir(SCRATCH);
    mkdir(CONFDIR);
    mkdir(SAVEDIR);
    writefile(`${CONFDIR}/network`, NETWORK);
    u = cursor(CONFDIR, SAVEDIR);

    params = {
        proto: null,
        state: 'present',
        peer_id_template: '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}',
    };
    fn = module_internals(MODULE, {
        params: params,
        check_mode: false,
        diff_mode: false,
        fail_json: (result) => die(result.msg),
    });
});

describe('wg_peer: peer_proto()', () => {
    it('prefers the protocol of the peer', () => {
        params.proto = 'wireguard';
        assert.match('amneziawg', fn.peer_proto(u, { iface: 'wg0', proto: 'amneziawg' }));
    });

    it('falls back to the module-wide protocol', () => {
        params.proto = 'wireguard';
        assert.match('wireguard', fn.peer_proto(u, { iface: 'awg1' }));
    });

    it('falls back to the protocol of the interface', () => {
        assert.match('amneziawg', fn.peer_proto(u, { iface: 'awg1' }));
    });

    it('defaults to wireguard without an interface section', () => {
        assert.match('wireguard', fn.peer_proto(u, { iface: 'wg9' }));
    });
});

describe('wg_peer: section_id()', () => {
    it('renders the peer section id', () => {
        assert.match('peer_wg0_spoke1', fn.section_id({ iface: 'wg0', section: 'spoke1' }, 'wireguard'));
    });

    it('fails when the id renders empty', () => {
        params.peer_id_template = '{{ nothing }}';
        assert.throws(() => fn.section_id({ iface: 'wg0' }, 'wireguard'), 'rendered an empty section name');
    });
});

describe('wg_peer: upsert_peer()', () => {
    it('writes a peer with the defaults', () => {
        fn.upsert_peer(u, { iface: 'wg1', public_key: 'PUB' }, 'wireguard');
        assert.match('wireguard_wg1', u.get('network', 'peer_wg1'));
        assert.match('PUB', u.get('network', 'peer_wg1', 'public_key'));
        assert.match('wg1', u.get('network', 'peer_wg1', 'description'));
        assert.match('0', u.get('network', 'peer_wg1', 'route_allowed_ips'));
        assert.match([ '0.0.0.0/0', '::/0' ], u.get('network', 'peer_wg1', 'allowed_ips'));
        assert.match(null, u.get('network', 'peer_wg1', 'endpoint_host'));
        assert.match(null, u.get('network', 'peer_wg1', 'preshared_key'));
    });

    it('describes the peer by its section', () => {
        fn.upsert_peer(u, { iface: 'wg1', section: 'spoke1', public_key: 'PUB' }, 'wireguard');
        assert.match('spoke1', u.get('network', 'peer_wg1_spoke1', 'description'));
    });

    it('types the section after the protocol and interface', () => {
        fn.upsert_peer(u, { iface: 'awg1', public_key: 'PUB' }, 'amneziawg');
        assert.match('amneziawg_awg1', u.get('network', 'peer_awg1'));
    });

    it('writes the given options', () => {
        fn.upsert_peer(u, {
            iface: 'wg1', public_key: 'PUB', preshared_key: 'PSK',
            endpoint_host: 'peer.example.com', endpoint_port: 51820, persistent_keepalive: 25,
            allowed_ips: [ '10.0.0.2/32' ],
        }, 'wireguard');
        assert.match('PSK', u.get('network', 'peer_wg1', 'preshared_key'));
        assert.match('peer.example.com', u.get('network', 'peer_wg1', 'endpoint_host'));
        assert.match('51820', u.get('network', 'peer_wg1', 'endpoint_port'));
        assert.match('25', u.get('network', 'peer_wg1', 'persistent_keepalive'));
        assert.match([ '10.0.0.2/32' ], u.get('network', 'peer_wg1', 'allowed_ips'));
    });

    it('fails without a public key', () => {
        assert.throws(() => fn.upsert_peer(u, { iface: 'wg1' }, 'wireguard'), 'public_key is required');
    });

    it('drops an existing pre-shared key when none is given', () => {
        fn.upsert_peer(u, { iface: 'wg0', public_key: 'NEW' }, 'wireguard');
        assert.match('NEW', u.get('network', 'peer_wg0', 'public_key'));
        assert.match(null, u.get('network', 'peer_wg0', 'preshared_key'));
    });
});

describe('wg_peer: remove_peer()', () => {
    it('removes the peer section', () => {
        fn.remove_peer(u, { iface: 'wg0' }, 'wireguard');
        assert.match(null, u.get('network', 'peer_wg0'));
    });

    it('does nothing for a missing peer', () => {
        fn.remove_peer(u, { iface: 'wg9' }, 'wireguard');
        assert.match('interface', u.get('network', 'awg1'));
        assert.match('wireguard_wg0', u.get('network', 'peer_wg0'));
    });
});
