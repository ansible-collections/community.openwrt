#!/usr/bin/ucode
// WANT_JSON — args passed as a JSON file whose path is ARGV[0]; output on stdout.
// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// wg_interface — manage WireGuard/AmneziaWG identity keys, interface UCI
// sections and the WAN ingress firewall rule for each interface's listen port.
//
// Written in ucode and run directly on the target. Resolves the host identity
// key (via ubus), writes the interface UCI section (including AWG 3.x/3.1
// options when the proto is amneziawg), and ensures the WAN ingress ACCEPT rule
// for the interface listen port. Reports the host public key so peer sections
// can be wired from controller facts.

'use strict';

import { cursor } from 'uci';
import { connect } from 'ubus';
import * as ac from './_ansible_common.uc';

let raw_args = ac.load_args();
let check_mode = ac.is_check_mode(raw_args);
let diff_enabled = ac.is_diff_enabled(raw_args);

// Declaratively validate/coerce the expected arguments (mirrors Ansible's
// argument_spec). Applied to the top-level call and to sub-elements.
let WG_SPEC = {
	proto: { type: 'str', choices: ['wireguard', 'amneziawg'], default: 'wireguard' },
	state: { type: 'str', choices: ['present', 'absent'], default: 'present' },
	interfaces: { type: 'list', options: {
		name: { type: 'str', required: true },
		state: { type: 'str', choices: ['present', 'absent'] },
		proto: { type: 'str', choices: ['wireguard', 'amneziawg'] },
		listen_port: { type: 'int' },
		addresses: { type: 'list' },
		mtu: { type: 'int' },
		metric: { type: 'int' },
		dns: { type: 'list' },
		peerdns: { type: 'bool' },
		dns_metric: { type: 'int' },
		awg_tuning: { type: 'dict' },
	} },
	managed_interfaces: { type: 'list' },
	force_rekey: { type: 'bool', default: false },
	force_psk_rekey: { type: 'bool', default: false },
	manage_firewall: { type: 'bool', default: true },
	peers: { type: 'list', options: {
		iface: { type: 'str' },
		proto: { type: 'str' },
		section: { type: 'str' },
		force_psk_rekey: { type: 'bool', default: false },
	} },
	firewall_rule_id_tpl: { type: 'str', default: '{{ iface_name }}_in' },
	firewall_rule_name_tpl: { type: 'str', default: 'Allow-Wan-{{ proto }}: {{ iface_name }}' },
	peer_id_tpl: { type: 'str', default: '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}' },
};
let validated = ac.validate_argument_spec(raw_args, WG_SPEC);
if (!validated.ok)
	ac.fail_json(ac.new_result(), validated.error);
let args = validated.values;
let result = ac.new_result({
	diff: [],
	public_key: '',
	interfaces: [],
	psks: [],
	firewall_changed: false,
	removed_interfaces: [],
});

// Defaults for the templated options (must live in the module, not just docs).
// ---- ubus key helpers (module-local; only this module uses ubus) ---------

function ubus_call(obj, method, payload) {
	let conn = connect();
	if (!conn)
		return null;
	try {
		return conn.call(obj, method, payload ? payload : {});
	} catch (e) {
		warn(`ubus ${obj}.${method}: ${e}${'\n'}`);
		return null;
	}
}

// Call `obj.method`, falling back to the `wireguard` object when `obj` is
// absent (amneziawg is a copy of the wireguard plugin, so wireguard is a safe
// fallback when the requested object is not present).
function ubus_key_call(obj, method, payload) {
	let r = ubus_call(obj, method, payload);
	if (r == null && obj != 'wireguard')
		r = ubus_call('wireguard', method, payload);
	return r;
}

// Resolve/derive the identity key across all managed interfaces.
// In normal mode: reuse the single existing key; generate if none present;
// fail on a hard mismatch (two distinct keys).
// With force_rekey: generate a fresh key regardless of existing state and
// replace it on every managed interface.
function resolve_identity(u, managed, force_rekey, proto) {
	let identity_key = '';
	let distinct = {};

	for (let name in managed) {
		let v = u.get('network', name, 'private_key');
		if (v != null && length(v) > 0) {
			distinct[v] = true;
			if (length(identity_key) == 0)
				identity_key = v;
		}
	}

	if (!force_rekey) {
		let distinct_keys = keys(distinct);
		if (length(distinct_keys) > 1)
			ac.fail_json(result, `identity key mismatch across managed interfaces: ${length(distinct_keys)} distinct keys; use force_rekey to replace`);
	}

	if (length(identity_key) == 0 || force_rekey) {
		let gen = ubus_key_call(proto, 'genkey', {});
		if (!gen || !gen.private)
			ac.fail_json(result, `failed to generate identity key via ubus ${proto}.genkey`);
		// ucode-lsp disable-next-line UC5006   # gen guarded above; LSP can't see fail_json()
		identity_key = gen.private;
		result.changed = true;
	}

	let pub = ubus_key_call(proto, 'pubkey', { private: identity_key });
	if (!pub || !pub.public)
		ac.fail_json(result, `failed to derive public key via ubus ${proto}.pubkey`);

	// ucode-lsp disable-next-line UC5006   # pub guarded above; LSP can't see fail_json()
	return { key: identity_key, public_key: pub.public };
}

// Ensure a WAN ingress ACCEPT rule for the given listen_port. The section id
// and description are rendered from ucode templates (firewall_rule_id_tpl /
// firewall_rule_name_tpl) so callers control both the section name and the
// rule label.
function upsert_firewall_rule(u, iface, listen_port, proto, scope) {
	let cfg = 'firewall';
	let sid = ac.render_template(args.firewall_rule_id_tpl, scope);
	let name = ac.render_template(args.firewall_rule_name_tpl, scope);

	let want = {
		name: name,
		src: 'wan',
		proto: 'udp',
		dest_port: sprintf('%s', listen_port),
		target: 'ACCEPT',
	};

	let r = ac.upsert_section(u, cfg, sid, 'rule', want, { check_mode: check_mode, diff: diff_enabled });
	if (r.changed) {
		result.changed = true;
		result.firewall_changed = true;
	}
	ac.push_diff(result, diff_enabled, `firewall.${sid}`, r.before, r.after);
}

// Delete an interface section, its peer sections (config type <proto>_<name>)
// and its WAN ingress rule. Returns true if anything was removed. The firewall
// rule id is rendered from the firewall_rule_id_tpl template (same as when the
// rule is created).
function delete_interface(u, name, proto, manage_firewall, listen_port) {
	let removed = false;

	let peer_type = `${proto}_${name}`;
	let all = u.get_all('network');
	if (all != null) {
		for (let sid in all) {
			let sec = all[sid];
			if (sec['.type'] == peer_type) {
				u.delete('network', sid);
				if (!check_mode)
					u.save('network');
				result.changed = true;
				removed = true;
			}
		}
	}

	if (manage_firewall) {
		let fw_sid = ac.render_template(args.firewall_rule_id_tpl, {
			iface_name: name,
			proto: proto,
			listen_port: listen_port,
		});
		let fw = u.get_all('firewall', fw_sid);
		if (fw != null) {
			u.delete('firewall', fw_sid);
			if (!check_mode)
				u.save('firewall');
			result.changed = true;
			result.firewall_changed = true;
			removed = true;
		}
	}

	let iface = u.get_all('network', name);
	if (iface != null) {
		u.delete('network', name);
		if (!check_mode)
			u.save('network');
		result.changed = true;
		removed = true;
	}

	return removed;
}

// ---- main -----------------------------------------------------------------

try {
	let u = cursor();

	let force_rekey = ac.coerce_to_bool(args.force_rekey);

	// Determine the protocol/ubus server. Only wireguard and amneziawg are
	// supported; both may coexist on a host. The global proto (defaults to
	// wireguard) is the base; an explicitly-set interface proto overrides it.
	let interfaces = args.interfaces != null ? args.interfaces : [];
	let proto = args.proto;
	for (let iface in interfaces) {
		if (iface.proto != null)
			proto = iface.proto;
	}

	// The managed set is used for identity-key consistency. When not given
	// explicitly, derive it from the interfaces being kept (state != absent),
	// so a pure-removal run manages nothing and performs no key handling.
	let managed = args.managed_interfaces != null ? args.managed_interfaces : [];
	if (type(managed) != 'array')
		managed = [managed];
	if (length(managed) == 0) {
		let seen = {};
		for (let iface in interfaces) {
			let st = iface.state != null ? iface.state : args.state;
			if (st != 'absent' && iface.name != null && !seen[iface.name]) {
				seen[iface.name] = true;
				// ucode-lsp disable-next-line incompatible-function-argument   # managed is an array
				push(managed, iface.name);
			}
		}
	}

	// A pure-removal run (every interface state=absent and no managed
	// interfaces) has nothing to keep or apply an identity key to. Skip key
	// resolution/generation entirely so a cleanup does not spin a fresh key or
	// report a spurious change.
	let any_present = false;
	for (let iface in interfaces) {
		let st = iface.state != null ? iface.state : args.state;
		if (st != 'absent') {
			any_present = true;
			break;
		}
	}
	let need_key = any_present || length(managed) > 0;

	// Phase 1: identity key (once, shared across all interfaces on the host).
	let identity = need_key ? resolve_identity(u, managed, force_rekey, proto) : null;
	result.public_key = identity != null ? identity.public_key : '';

	// Ensure the identity key is applied to every managed interface, even those
	// not being (re)configured below.
	if (need_key) {
	for (let mname in managed) {
		// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
		let cur = u.get('network', mname, 'private_key');
		if (force_rekey || cur == null || length(cur) == 0) {
			let before = {};
			// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
			let sec = u.get_all('network', mname);
			if (sec != null)
				before = ac.strip_meta(sec);
			// ucode-lsp disable-next-line UC5006   # identity non-null when need_key
			if (before['private_key'] != identity.key) {
				if (sec == null)
					// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
					u.set('network', mname, 'interface');
				// ucode-lsp disable-next-line UC5006   # identity non-null when need_key
				u.set('network', mname, 'private_key', identity.key);
				if (!check_mode)
					// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
					u.save('network');
				result.changed = true;
			}
		}
	}
	}

	// Phase 2: interface sections + tuning. Each interface entry has a state
	// (present by default); state=absent deletes the interface, its peer
	// sections and its WAN ingress rule.
	let manage_firewall = args.manage_firewall != null ? ac.coerce_to_bool(args.manage_firewall) : true;

	for (let iface in interfaces) {
		let name = iface.name;
		let iproto = iface.proto != null ? iface.proto : args.proto;
		let state = iface.state != null ? iface.state : args.state;

		if (state == 'absent') {
			let removed = delete_interface(u, name, iproto, manage_firewall, iface.listen_port);
			if (removed)
				// ucode-lsp disable-next-line incompatible-function-argument   # result.removed_interfaces is an array
				push(result.removed_interfaces, name);
			continue;
		}

		let options = {};
		options['proto'] = iproto;
		options['listen_port'] = iface.listen_port != null ? sprintf('%s', iface.listen_port) : '';
		options['addresses'] = iface.addresses;
		if (iface.mtu != null)
			options['mtu'] = sprintf('%s', iface.mtu);
		if (iface.metric != null)
			options['metric'] = sprintf('%s', iface.metric);
		if (iface.dns != null)
			options['dns'] = iface.dns;
		if (iface.peerdns != null)
			options['peerdns'] = iface.peerdns;
		if (iface.dns_metric != null)
			options['dns_metric'] = iface.dns_metric;

		// AWG tuning (amneziawg only). Every known awg_* key defaults to an
		// empty string so a key omitted from `awg_tuning` is dropped from the
		// generated config; provided keys override it. Ignored for wireguard.
		if (iproto == 'amneziawg') {
			let awg_defaults = [
				'awg_jc', 'awg_jmin', 'awg_jmax',
				'awg_s1', 'awg_s2', 'awg_s3', 'awg_s4',
				'awg_h1', 'awg_h2', 'awg_h3', 'awg_h4',
				'awg_i1', 'awg_i2', 'awg_i3', 'awg_i4', 'awg_i5',
				'awg_header_protection_key',
				'awg_content_padding_addition',
				'awg_rekey_after_time', 'awg_rekey_timeout',
				'awg_reject_after_time', 'awg_keepalive_timeout',
				'awg_max_handshake_attempts',
				'awg_random_trailers', 'awg_disable_cookies',
			];
			for (let k in awg_defaults)
				options[k] = '';
			let tuning = iface.awg_tuning != null ? iface.awg_tuning : {};
			for (let k in tuning) {
				if (tuning[k] != null)
					options[k] = type(tuning[k]) == 'string' ? tuning[k] : sprintf('%s', tuning[k]);
			}
		}

		let r = ac.upsert_section(u, 'network', name, 'interface', options, {
			check_mode: check_mode,
			diff: diff_enabled,
			redact_keys: ['private_key'],
		});
		if (r.changed)
			result.changed = true;
		ac.push_diff(result, diff_enabled, `network.${name}`, r.before, r.after);

		// Firewall ingress rule (skippable via manage_firewall=false).
		if (manage_firewall && iface.listen_port != null) {
			upsert_firewall_rule(u, name, iface.listen_port, iproto, {
				iface_name: name,
				proto: iproto,
				listen_port: iface.listen_port,
			});
		}

		// ucode-lsp disable-next-line incompatible-function-argument   # result.interfaces is an array
		push(result.interfaces, name);
	}

	// Phase 3: resolve (not store) peer PSKs. For each peer section, reuse an
	// existing PSK if already on-device, otherwise generate one via ubus and
	// return it as a list parallel to the `peers` input (psks[i] matches
	// peers[i]). The controller distributes the shared key to both ends (the
	// peer section is written by wg_peer).
	let force_psk_rekey = ac.coerce_to_bool(args.force_psk_rekey);

	let psks = [];
	let peers = args.peers != null ? args.peers : [];
	for (let pr in peers) {
		let iface = pr.iface;
		let pproto = pr.proto != null ? pr.proto : args.proto;
		if (pproto != 'wireguard' && pproto != 'amneziawg')
			ac.fail_json(result, `unsupported proto "${pproto}" for peer on ${iface}; only wireguard and amneziawg are supported`);

		// Resolve the peer section id (used to locate a reusable on-device
		// PSK) from the peer_id_tpl template. The returned list is parallel to
		// `peers`, so multi-peer interfaces do not collide.
		let section = pr.section != null ? pr.section : '';
		let sid = ac.render_template(args.peer_id_tpl, {
			iface_name: iface,
			section: section,
			proto: pproto,
		});

		let rekey = force_psk_rekey || ac.coerce_to_bool(pr.force_psk_rekey);

		let cur = '';
		if (!rekey) {
			// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
			let got = u.get('network', sid, 'preshared_key');
			if (got != null)
				cur = got;
		}
		if (length(cur) == 0) {
			let gen = ubus_key_call(pproto, 'genpsk', {});
			if (!gen || !gen.preshared)
				ac.fail_json(result, `failed to generate PSK via ubus ${pproto}.genpsk`);
			// ucode-lsp disable-next-line UC5006   # gen guarded above; LSP can't see fail_json()
			cur = gen.preshared;
			result.changed = true;
		}
		push(psks, cur);
	}
	if (length(peers) > 0)
		result.psks = psks;

	// Commit the configs once at the end.
	if (!check_mode) {
		// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
		u.commit('network');
		if (manage_firewall)
			// ucode-lsp disable-next-line UC5006   # u != null (cursor) guarded by fail_json
			u.commit('firewall');
	}

	result.msg = 'wg interfaces configured';
	ac.exit_json(result);
} catch (e) {
	ac.fail_json(result, `wg_interface error: ${e}\n${ac.trace()}`);
}
