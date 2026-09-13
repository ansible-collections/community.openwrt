#!/usr/bin/ucode
// WANT_JSON — args passed as a JSON file whose path is ARGV[0]; output on stdout.
// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// wg_peer — write WireGuard/AmneziaWG peer UCI sections for an interface. Takes
// the peer's resolved key material (public key, optional PSK, endpoint) from
// controller facts; the interface itself must already exist (wg_interface).

'use strict';

import { cursor } from 'uci';
import * as ac from './_ansible_common.uc';

// Declaratively validate/coerce the expected arguments.
let ARGS_SPEC = {
	peers: { type: 'list', options: {
		iface: { type: 'str', required: true },
		proto: { type: 'str' },
		state: { type: 'str', choices: ['present', 'absent'], default: 'present' },
		section: { type: 'str' },
		description: { type: 'str' },
		public_key: { type: 'str' },
		preshared_key: { type: 'str' },
		endpoint_host: { type: 'str' },
		endpoint_port: { type: 'int' },
		persistent_keepalive: { type: 'int' },
		route_allowed_ips: { type: 'str' },
		allowed_ips: { type: 'list' },
	} },
	peer_id_tpl: { type: 'str', default: '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}' },
};

let raw_args = ac.load_args();
let check_mode = ac.is_check_mode(raw_args);
let diff_enabled = ac.is_diff_enabled(raw_args);
let validated = ac.validate_argument_spec(raw_args, ARGS_SPEC);
if (!validated.ok)
	ac.fail_json(ac.new_result(), validated.error);
let args = validated.values;

let result = ac.new_result({ diff: [], peers: [], removed: [] });

// Default for the peer section id template.
// Resolve the peer UCI section id from the peer_id_tpl template. Placeholders
// in scope: iface_name, section, proto.
function peer_sid(iface, peer, proto) {
	let section = peer.section != null ? peer.section : '';
	return ac.render_template(args.peer_id_tpl, {
		iface_name: iface,
		section: section,
		proto: proto,
	});
}

// Read the proto of an interface section (defaults to wireguard).
function interface_proto(u, iface) {
	let sec = u.get_all('network', iface);
	if (sec != null && sec['proto'] != null)
		return sec['proto'];
	return 'wireguard';
}

// Write one peer section of type <proto>_<iface>.
function upsert_peer(u, iface, peer) {
	// Derive the peer proto from the interface section when not given, so the
	// peer section type matches the interface (e.g. amneziawg_awg1).
	let proto = peer.proto != null ? peer.proto : interface_proto(u, iface);
	if (proto != 'wireguard' && proto != 'amneziawg')
		ac.fail_json(result, `unsupported proto "${proto}" for peer ${iface}; only wireguard and amneziawg are supported`);
	let sid = peer_sid(iface, peer, proto);
	let sec_type = `${proto}_${iface}`;

	let section = peer.section != null ? peer.section : '';
	let want = {};
	let drop = {};
	let peer_label = peer.description != null ? peer.description : (
		length(section) > 0 ? section : (
			peer.host != null ? peer.host : (
				peer.peer_host != null ? peer.peer_host : iface
			)
		)
	);
	want['description'] = peer_label;
	want['public_key'] = peer.public_key;
	if (peer.preshared_key != null && length(peer.preshared_key) > 0)
		want['preshared_key'] = peer.preshared_key;
	else
		drop['preshared_key'] = true;
	want['endpoint_host'] = peer.endpoint_host != null ? peer.endpoint_host : '';
	want['endpoint_port'] = peer.endpoint_port != null ? sprintf('%s', peer.endpoint_port) : '';
	want['persistent_keepalive'] = peer.persistent_keepalive != null
		? sprintf('%s', peer.persistent_keepalive) : '';
	want['route_allowed_ips'] = peer.route_allowed_ips != null
		? sprintf('%s', peer.route_allowed_ips) : '0';
	want['allowed_ips'] = peer.allowed_ips != null ? peer.allowed_ips : ['0.0.0.0/0', '::/0'];

	let r = ac.upsert_section(u, 'network', sid, sec_type, want, {
		check_mode: check_mode,
		diff: diff_enabled,
		drop: drop,
		redact_keys: ['preshared_key'],
	});
	if (r.changed)
		result.changed = true;
	ac.push_diff(result, diff_enabled, `network.${sid}`, r.before, r.after);

	return sid;
}

// ---- main -----------------------------------------------------------------

try {
	let u = cursor();
	if (u == null)
		ac.fail_json(result, 'failed to open UCI cursor');
	let peers = args.peers != null ? args.peers : [];

	for (let p in peers) {
		let iface = p.iface;
		let proto = p.proto != null ? p.proto : interface_proto(u, iface);
		let state = p.state != null ? p.state : 'present';

		if (state == 'absent') {
			let sid = peer_sid(iface, p, proto);
			// ucode-lsp disable-next-line UC5006   # u != null guarded by fail_json above
			let sec = u.get_all('network', sid);
			if (sec != null) {
				// ucode-lsp disable-next-line UC5006   # u != null guarded by fail_json above
				u.delete('network', sid);
				if (!check_mode)
					// ucode-lsp disable-next-line UC5006   # u != null guarded by fail_json above
					u.save('network');
				result.changed = true;
				// ucode-lsp disable-next-line incompatible-function-argument   # result.removed is an array (new_result)
				push(result.removed, sid);
			}
			continue;
		}

		let sid = upsert_peer(u, iface, p);
		// ucode-lsp disable-next-line incompatible-function-argument   # result.peers is an array (new_result)
		push(result.peers, sid);
	}

	if (!check_mode)
		// ucode-lsp disable-next-line UC5006   # u != null guarded by fail_json above
		u.commit('network');

	result.msg = 'wg peers configured';
	ac.exit_json(result);
} catch (e) {
	ac.fail_json(result, `wg_peer error: ${e}\n${ac.trace()}`);
}
