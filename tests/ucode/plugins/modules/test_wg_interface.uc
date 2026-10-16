// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach, afterEach, mock } from 'utest';
import { cursor } from 'uci';
import { mkdir, writefile } from 'fs';
import { module_internals } from 'utils.ansible_module';

const MODULE = '../../plugins/modules/wg_interface.uc';
const SCRATCH = '/tmp/test_wg_interface';
const CONFDIR = `${SCRATCH}/config`;
const SAVEDIR = `${SCRATCH}/delta`;

const NETWORK = `
config interface 'wg0'
	option proto 'wireguard'
	option private_key 'EXISTING'
	option listen_port '51820'

config wireguard_wg0 'peer_wg0'
	option public_key 'PEER0'

config wireguard_wg1 'peer_wg1'
	option public_key 'PEER1'

config interface 'wg1'
	option proto 'wireguard'
`;

const FIREWALL = `
config rule 'wg0_in'
	option src 'wan'
	option dest_port '51820'
`;

let params;
let fn;
let u;

// Load the module's functions with `params`, and a fresh UCI config. The
// key server answers with keys derived from its arguments.
function setup(network) {
    mkdir(SCRATCH);
    mkdir(CONFDIR);
    mkdir(SAVEDIR);
    writefile(`${CONFDIR}/network`, network);
    writefile(`${CONFDIR}/firewall`, FIREWALL);
    u = cursor(CONFDIR, SAVEDIR);

    params = {
        proto: 'wireguard',
        force_rekey: false,
        manage_firewall: true,
        firewall_rule_id_template: '{{ iface_name }}_in',
        firewall_rule_name_template: 'Allow-Wan-{{ proto }}: {{ iface_name }}',
    };
    fn = module_internals(MODULE, {
        params: params,
        check_mode: false,
        diff_mode: false,
        fail_json: (result) => die(result.msg),
    });
}

function key_server(objects) {
    let data = {};
    for (let object in objects) {
        data[`${object}:genkey`] = { private: `NEW-${object}` };
        data[`${object}:genpsk`] = { preshared: `PSK-${object}` };
        data[`${object}:pubkey`] = (args) => ({ public: `pub(${args.private})` });
    }
    mock.global.patch('ubus', { data: data });
}

describe('wg_interface: ubus_call()', () => {
    beforeEach(() => setup(NETWORK));
    afterEach(() => mock.global.unpatch('ubus'));

    it('calls the requested object', () => {
        key_server([ 'wireguard', 'amneziawg' ]);
        assert.match({ private: 'NEW-amneziawg' }, fn.ubus_call('amneziawg', 'genkey', {}));
    });

    it('falls back to the wireguard object', () => {
        key_server([ 'wireguard' ]);
        assert.match({ private: 'NEW-wireguard' }, fn.ubus_call('amneziawg', 'genkey', {}));
    });

    it('returns null when no object answers', () => {
        key_server([]);
        assert.match(null, fn.ubus_call('amneziawg', 'genkey', {}));
    });

    it('returns null without a ubus connection', () => {
        mock.global.patch('ubus', { behavior: { connect: () => null } });
        assert.match(null, fn.ubus_call('wireguard', 'genkey', {}));
    });
});

describe('wg_interface: resolve_identity()', () => {
    beforeEach(() => setup(NETWORK));
    afterEach(() => mock.global.unpatch('ubus'));

    it('reuses the key of a managed interface', () => {
        key_server([ 'wireguard' ]);
        assert.match({ private: 'EXISTING', public: 'pub(EXISTING)' },
                     fn.resolve_identity(u, [ 'wg0', 'wg1' ], 'wireguard'));
    });

    it('generates a key when no managed interface has one', () => {
        key_server([ 'wireguard' ]);
        assert.match({ private: 'NEW-wireguard', public: 'pub(NEW-wireguard)' },
                     fn.resolve_identity(u, [ 'wg1', 'wg2' ], 'wireguard'));
    });

    it('generates a key with the requested protocol', () => {
        key_server([ 'wireguard', 'amneziawg' ]);
        assert.match('NEW-amneziawg', fn.resolve_identity(u, [ 'awg1' ], 'amneziawg').private);
    });

    it('fails when managed interfaces hold different keys', () => {
        key_server([ 'wireguard' ]);
        u.set('network', 'wg1', 'private_key', 'OTHER');
        assert.throws(() => fn.resolve_identity(u, [ 'wg0', 'wg1' ], 'wireguard'), 'identity key mismatch');
    });

    it('replaces the key with force_rekey', () => {
        key_server([ 'wireguard' ]);
        u.set('network', 'wg1', 'private_key', 'OTHER');
        params.force_rekey = true;
        assert.match('NEW-wireguard', fn.resolve_identity(u, [ 'wg0', 'wg1' ], 'wireguard').private);
    });

    it('fails without a key server', () => {
        key_server([]);
        assert.throws(() => fn.resolve_identity(u, [ 'wg1' ], 'wireguard'), 'wireguard.genkey');
    });
});

describe('wg_interface: interface_options()', () => {
    beforeEach(() => setup(NETWORK));

    it('has no AmneziaWG options for WireGuard', () => {
        let wanted = fn.interface_options({ listen_port: 51820, addresses: [ '10.0.0.1/24' ], awg_tuning: { awg_jc: 4 } }, 'wireguard');
        assert.match('wireguard', wanted.proto);
        assert.match(51820, wanted.listen_port);
        assert.match([ '10.0.0.1/24' ], wanted.addresses);
        assert.match(false, exists(wanted, 'awg_jc'));
    });

    it('clears the AmneziaWG options not tuned', () => {
        let wanted = fn.interface_options({ awg_tuning: { awg_jc: 4 } }, 'amneziawg');
        assert.match(4, wanted.awg_jc);
        assert.match('', wanted.awg_jmin);
        assert.match('', wanted.awg_disable_cookies);
    });
});

describe('wg_interface: upsert_interface()', () => {
    beforeEach(() => setup(NETWORK));

    it('writes the interface and its WAN ingress rule', () => {
        fn.upsert_interface(u, { name: 'wg2', listen_port: 51822, addresses: [ '10.2.0.1/24' ] }, 'wireguard');
        assert.match('interface', u.get('network', 'wg2'));
        assert.match('51822', u.get('network', 'wg2', 'listen_port'));
        assert.match([ '10.2.0.1/24' ], u.get('network', 'wg2', 'addresses'));
        assert.match('rule', u.get('firewall', 'wg2_in'));
        assert.match('Allow-Wan-wireguard: wg2', u.get('firewall', 'wg2_in', 'name'));
        assert.match('udp', u.get('firewall', 'wg2_in', 'proto'));
        assert.match('51822', u.get('firewall', 'wg2_in', 'dest_port'));
        assert.match('ACCEPT', u.get('firewall', 'wg2_in', 'target'));
    });

    it('keeps the private key of an existing interface', () => {
        fn.upsert_interface(u, { name: 'wg0', listen_port: 51999 }, 'wireguard');
        assert.match('EXISTING', u.get('network', 'wg0', 'private_key'));
        assert.match('51999', u.get('network', 'wg0', 'listen_port'));
    });

    it('writes no rule without a listen port', () => {
        fn.upsert_interface(u, { name: 'wg2' }, 'wireguard');
        assert.match(null, u.get('firewall', 'wg2_in'));
    });

    it('writes no rule when the firewall is not managed', () => {
        params.manage_firewall = false;
        fn.upsert_interface(u, { name: 'wg2', listen_port: 51822 }, 'wireguard');
        assert.match(null, u.get('firewall', 'wg2_in'));
    });

    it('fails when the rule id renders empty', () => {
        params.firewall_rule_id_template = '{{ nothing }}';
        assert.throws(() => fn.upsert_interface(u, { name: 'wg2', listen_port: 51822 }, 'wireguard'),
                      'rendered an empty section name');
    });
});

describe('wg_interface: delete_interface()', () => {
    beforeEach(() => setup(NETWORK));

    it('removes the interface, its peers and its WAN ingress rule', () => {
        fn.delete_interface(u, { name: 'wg0' }, 'wireguard');
        assert.match(null, u.get('network', 'wg0'));
        assert.match(null, u.get('network', 'peer_wg0'));
        assert.match(null, u.get('firewall', 'wg0_in'));
    });

    it('keeps the peers of other interfaces', () => {
        fn.delete_interface(u, { name: 'wg0' }, 'wireguard');
        assert.match('wireguard_wg1', u.get('network', 'peer_wg1'));
        assert.match('interface', u.get('network', 'wg1'));
    });

    it('removes only the peers of its protocol', () => {
        fn.delete_interface(u, { name: 'wg0' }, 'amneziawg');
        assert.match('wireguard_wg0', u.get('network', 'peer_wg0'));
    });

    it('keeps the rule when the firewall is not managed', () => {
        params.manage_firewall = false;
        fn.delete_interface(u, { name: 'wg0' }, 'wireguard');
        assert.match('rule', u.get('firewall', 'wg0_in'));
    });
});
