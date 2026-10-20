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
        state: 'present',
        interfaces: [],
        force_rekey: false,
        manage_firewall: true,
        firewall_rule_id_template: '{{ iface_name }}_in',
        firewall_rule_name_template: 'Allow-Wan-{{ proto }}: {{ iface_name }}',
        peer_id_template: '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}',
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

describe('wg_interface: key_protocol()', () => {
    beforeEach(() => setup(NETWORK));

    it('defaults to the module-wide protocol', () => {
        params.interfaces = [ { name: 'wg0' } ];
        assert.match('wireguard', fn.key_protocol());
    });

    it('takes the protocol of the interfaces being kept', () => {
        params.interfaces = [ { name: 'awg1', proto: 'amneziawg' } ];
        assert.match('amneziawg', fn.key_protocol());
    });

    it('ignores the interfaces being removed', () => {
        params.interfaces = [ { name: 'wg0' }, { name: 'awg1', proto: 'amneziawg', state: 'absent' } ];
        assert.match('wireguard', fn.key_protocol());
    });

    it('fails when the interfaces being kept request different protocols', () => {
        params.interfaces = [ { name: 'wg0' }, { name: 'awg1', proto: 'amneziawg' } ];
        assert.throws(() => fn.key_protocol(), 'different protocols (amneziawg, wireguard)');
    });
});

describe('wg_interface: wanted_key()', () => {
    beforeEach(() => setup(NETWORK));

    const identity = { private: 'IDENTITY', public: 'pub(IDENTITY)' };

    it('keeps the key of the interface', () => assert.match('EXISTING', fn.wanted_key(u, 'wg0', identity)));
    it('gives the identity key to an interface without one', () => assert.match('IDENTITY', fn.wanted_key(u, 'wg1', identity)));

    it('gives the identity key to every interface with force_rekey', () => {
        params.force_rekey = true;
        assert.match('IDENTITY', fn.wanted_key(u, 'wg0', identity));
    });
});

describe('wg_interface: apply_key()', () => {
    beforeEach(() => setup(NETWORK));

    it('writes the key to an existing interface', () => {
        fn.apply_key(u, 'wg1', 'IDENTITY');
        assert.match('IDENTITY', u.get('network', 'wg1', 'private_key'));
        assert.match('wireguard', u.get('network', 'wg1', 'proto'));
    });

    it('skips an interface with no section', () => {
        fn.apply_key(u, 'wg9', 'IDENTITY');
        assert.match(null, u.get('network', 'wg9'));
    });
});

describe('wg_interface: render_option()', () => {
    beforeEach(() => setup(NETWORK));

    it('fails with the option name and the template error', () => {
        params.firewall_rule_name_template = '{{ iface_name ';
        assert.throws(() => fn.render_option('firewall_rule_name_template', { iface_name: 'wg0' }),
                      'firewall_rule_name_template: Unable to compile source string');
    });
});

describe('wg_interface: peer_id()', () => {
    beforeEach(() => setup(NETWORK));

    it('renders the peer section id', () => {
        assert.match('peer_wg0_spoke1', fn.peer_id({ iface: 'wg0', section: 'spoke1' }, 'wireguard'));
    });

    it('fails with the template error', () => {
        params.peer_id_template = '{{ iface_name ';
        assert.throws(() => fn.peer_id({ iface: 'wg0' }, 'wireguard'), 'peer_id_template: ');
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

    it('writes the given private key', () => {
        fn.upsert_interface(u, { name: 'wg2' }, 'wireguard', 'IDENTITY');
        assert.match('IDENTITY', u.get('network', 'wg2', 'private_key'));
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

    it('removes the rule of a listen port no longer set', () => {
        fn.upsert_interface(u, { name: 'wg0' }, 'wireguard');
        assert.match(null, u.get('network', 'wg0', 'listen_port'));
        assert.match(null, u.get('firewall', 'wg0_in'));
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

    it('removes the peers of either protocol', () => {
        u.set('network', 'peer_wg0_awg', 'amneziawg_wg0');
        u.set('network', 'peer_wg0_awg', 'public_key', 'PEERAWG');
        fn.delete_interface(u, { name: 'wg0' }, 'wireguard');
        assert.match(null, u.get('network', 'peer_wg0'));
        assert.match(null, u.get('network', 'peer_wg0_awg'));
    });

    it('renders the rule id with the protocol of the interface on the device', () => {
        params.firewall_rule_id_template = '{{ iface_name }}_{{ proto }}';
        u.set('firewall', 'wg0_wireguard', 'rule');
        fn.delete_interface(u, { name: 'wg0' }, 'amneziawg');
        assert.match(null, u.get('firewall', 'wg0_wireguard'));
    });

    it('keeps the rule when the firewall is not managed', () => {
        params.manage_firewall = false;
        fn.delete_interface(u, { name: 'wg0' }, 'wireguard');
        assert.match('rule', u.get('firewall', 'wg0_in'));
    });
});
