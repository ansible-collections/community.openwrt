#!/usr/bin/ucode
// WANT_JSON — args passed as a JSON file whose path is ARGV[0]; output on stdout.
// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// uc_uci — ucode-based alternative to the shell `uci` module.
//
// Unlike the shell implementation (uci.sh, driven through wrapper.sh + jshn),
// this module reads/writes UCI through the native `uci` ucode module (cursor())
// and emits Ansible module JSON directly, avoiding the JSON corruption that
// affects long diffs in the shell path.
//
// It supports the same commands as community.openwrt.uci and adds:
//   - `redact_keys`: list of option names to mask in the diff output.
//   - `operations`: list of sub-operations executed in a single invocation.

'use strict';

import { cursor } from 'uci';
import { popen } from 'fs';
import * as ac from './_ansible_common.uc';

/**
 * @typedef {ReturnType<typeof cursor>} UciCursor
 */
/**
 * @typedef {object} UciKey
 * @property {string|null} config
 * @property {string|null} section
 * @property {string|null} option
 */
/**
 * @typedef {object} UciOp
 * @property {string|null} [command]
 * @property {string|null} [config]
 * @property {string|null} [section]
 * @property {string|null} [option]
 * @property {string|null} [key]
 * @property {*} [value]
 * @property {*} [find]
 * @property {string|null} [name]
 * @property {string|null} [type]
 * @property {boolean|null} [unique]
 * @property {boolean|null} [merge]
 * @property {boolean|null} [autocommit]
 * @property {boolean|null} [set_find]
 * @property {boolean|null} [_ansible_check_mode]
 * @property {boolean|null} [_ansible_diff]
 * @property {array|null} [redact_keys]
 */

// Declaratively validate/coerce the expected operation arguments (mirrors
// Ansible's argument_spec). Applied to the top-level call and to each entry of
// `operations`. `_ansible_*` internal flags flow through unchanged.
let OP_SPEC = {
	command: {
		type: 'str',
		aliases: ['cmd'],
		choices: [ 'get', 'set', 'delete', 'add', 'add_list', 'del_list', 'rename',
		           'reorder', 'commit', 'revert', 'changes', 'export', 'show',
		           'import', 'batch', 'find', 'find_all', 'section', 'ensure', 'absent' ],
	},
	config: { type: 'str' },
	section: { type: 'str' },
	option: { type: 'str' },
	key: { type: 'str' },
	type: { type: 'str' },
	name: { type: 'str' },
	value: { type: 'raw' },
	find: { type: 'raw', aliases: ['find_by', 'search'] },
	replace: { type: 'bool', default: false },
	keep_keys: { type: 'list', elements: 'str', aliases: ['keep'] },
	unique: { type: 'bool', default: false },
	merge: { type: 'bool', default: false },
	autocommit: { type: 'bool', default: false },
	set_find: { type: 'bool', default: false },
	redact_keys: { type: 'list', elements: 'str' },
};
let ARGS_SPEC = { ...OP_SPEC, operations: { type: 'list', options: OP_SPEC } };

let raw_args = ac.load_args();

// Ansible-internal flags are not part of the module's argspec; read them
// directly so they cannot be influenced by user-provided arguments.
let check_mode = ac.is_check_mode(raw_args);
let diff_enabled = ac.is_diff_enabled(raw_args);

let validated = ac.validate_argument_spec(raw_args, ARGS_SPEC);
if (!validated.ok)
	ac.fail_json(ac.new_result(), validated.error);
let args = validated.values;

let result = ac.new_result({ diff: [] });

// ---- small utilities ------------------------------------------------------

// Shell-quote a string for use in a single-command popen.
function shq(s) {
	return "'" + replace(s, "'", "'\\''") + "'";
}

// Run a shell command, returning its combined stdout+stderr.
function run_shell(cmd) {
	let f = popen(cmd + ' 2>&1', 'r');
	let out = f ? f.read('all') : '';
	let rc = f ? int(f.close()) : 1;
	return { out: out != null ? out : '', rc: rc };
}

// ---- key resolution -------------------------------------------------------

/**
 * Resolve the effective key components. `key` takes precedence.
 * @param {UciOp} op
 * @returns {UciKey}
 */
function resolve_key(op) {
	let config = op.config;
	let section = op.section;
	let option = op.option;
	if (op.key != null && length(op.key) > 0) {
		// ucode-lsp disable-next-line incompatible-function-argument
		let parts = split(op.key, '.');
		config = parts[0];
		section = parts[1];
		option = parts[2];
	}
	return { config: config, section: section, option: option };
}

/**
 * Determine the command; default to `set` if value given else `get`.
 * @param {UciOp} op
 * @returns {string}
 */
function resolve_command(op) {
	let cmd = op.command;
	if (cmd != null)
		return cmd;
	return op.value != null ? 'set' : 'get';
}

// Append a displayable diff entry for a changed config/section, applying the
// operation's redact_keys to the before/after maps. The header is shaped like
// `uci export` output: <config>.<section>=<type> (e.g. network.lan=interface).
function record_diff(config, section, section_type, before, after, redact_keys) {
	let b = before;
	let a = after;
	if (redact_keys != null && length(redact_keys) > 0) {
		b = {};
		for (let k in before)
			b[k] = before[k];
		a = {};
		for (let k in after)
			a[k] = after[k];
		ac.redact(b, a, redact_keys);
	}
	let header = `${config}.${section}`;
	if (section_type != null && length(section_type) > 0)
		header = `${header}=${section_type}`;
	ac.push_diff(result, diff_enabled, header, b, a);
}

// ---- command implementations ----------------------------------------------

function cmd_get(u, op, key) {
	let v = u.get(key.config, key.section, key.option);
	if (v == null)
		ac.fail_json(result, `uci get failed for ${key.config}.${key.section}${key.option != null ? '.' + key.option : ''}`);
	if (type(v) == 'array') {
		result.result_list = v;
		result.result = length(v) > 0 ? v[0] : '';
	} else {
		result.result = sprintf('%s', v);
	}
}

function cmd_set(u, op, key) {
	let value = op.value;
	if (key.config == null || key.section == null)
		ac.fail_json(result, 'config and section required for set');
	let before = {};
	let before_section = u.get_all(key.config, key.section);
	if (before_section != null)
		before = ac.strip_meta(before_section);

	// Determine which options this `set` owns; they are kept under `replace`.
	let set_keys = {};
	if (type(value) == 'array') {
		// Replace the list option with the given values.
		if (key.option == null)
			ac.fail_json(result, 'config, section and option required for set');
		u.delete(key.config, key.section, key.option);
		for (let i = 0; i < length(value); i++)
			ac.list_append(u, key.config, key.section, key.option, sprintf('%s', value[i]));
		set_keys[key.option] = true;
	} else if (type(value) == 'object') {
		// Set a set of options on the section (parity with community.openwrt.uci).
		if (key.option != null)
			ac.fail_json(result, 'config and section but not option required for set');
		for (let k in value) {
			let tv = value[k];
			if (tv == null)
				continue;
			u.set(key.config, key.section, sprintf('%s', k), tv);
			set_keys[sprintf('%s', k)] = true;
		}
	} else {
		u.set(key.config, key.section, key.option, sprintf('%s', value));
		set_keys[key.option] = true;
	}

	// `replace`: delete section options not being set (or listed in keep_keys),
	// parity with community.openwrt.uci's uci_cleanup_section.
	if (ac.coerce_to_bool(op.replace)) {
		let keep = {};
		for (let k in set_keys)
			keep[k] = true;
		if (op.keep_keys != null) {
			for (let i = 0; i < length(op.keep_keys); i++)
				keep[sprintf('%s', op.keep_keys[i])] = true;
		}
		for (let k in before) {
			if (!keep[k])
				u.set(key.config, key.section, k, '');
		}
	}

	// Detect change from the full section state.
	let after = {};
	let after_section = u.get_all(key.config, key.section);
	if (after_section != null)
		after = ac.strip_meta(after_section);
	if (sprintf('%J', before) != sprintf('%J', after))
		result.changed = true;

	if (result.changed && diff_enabled) {
		let sec_type = u.get(key.config, key.section);
		record_diff(key.config, key.section, sec_type, before, after, op.redact_keys != null ? op.redact_keys : args.redact_keys);
	}
}

function cmd_delete(u, op, key) {
	let value = op.value;
	if (key.option == null || value == null) {
		if (key.option != null)
			u.delete(key.config, key.section, key.option);
		else if (key.section != null)
			u.delete(key.config, key.section);
		else
			ac.fail_json(result, 'key required for delete');
	} else {
		// delete <key>=<value> deletes a list item.
		ac.list_remove(u, key.config, key.section, key.option, sprintf('%s', value));
	}
	result.changed = true;
}

function cmd_add(u, op, key) {
	let section_type = op.type != null ? op.type : key.section;
	if (section_type == null)
		ac.fail_json(result, 'type required for add');
	let name = op.name;
	// Parity with community.openwrt.uci's uci_check_type: if the named section
	// already exists, reuse it (same type) or fail (different type).
	if (name != null && length(name) > 0) {
		let existing = u.get_all(key.config, name);
		if (existing != null) {
			let t = existing['.type'];
			if (t != null && length(t) > 0 && t != section_type)
				ac.fail_json(result, `${name} exists with ${t} instead of ${section_type}`);
			result.result = sprintf('%s', name);
			result.changed = false;
			return;
		}
	}
	u.load(key.config);
	let sid = u.add(key.config, section_type);
	if (sid == null)
		ac.fail_json(result, `uci add failed for ${key.config} type ${section_type}`);
	if (name != null && length(name) > 0) {
		u.rename(key.config, sid, sprintf('%s', name));
		sid = sprintf('%s', name);
	}
	result.result = sid;
	result.changed = true;
}

function cmd_add_list(u, op, key) {
	let value = sprintf('%s', op.value);
	let unique = ac.coerce_to_bool(op.unique);
	if (unique) {
		let cur = ac.list_get(u, key.config, key.section, key.option);
		for (let i = 0; i < length(cur); i++) {
			if (cur[i] == value)
				return;
		}
	}
	ac.list_append(u, key.config, key.section, key.option, value);
	result.changed = true;
}

function cmd_del_list(u, op, key) {
	let value = sprintf('%s', op.value);
	// Only report a change if the value is actually present in the list.
	// list_get normalizes a scalar option (e.g. a single entry created by the
	// 23.05 list_append fallback) to a one-element array.
	let cur = ac.list_get(u, key.config, key.section, key.option);
	let found = false;
	for (let i = 0; i < length(cur); i++) {
		if (cur[i] == value) {
			found = true;
			break;
		}
	}
	if (found) {
		ac.list_remove(u, key.config, key.section, key.option, value);
		result.changed = true;
	}
}

function cmd_rename(u, op, key) {
	let name = op.name != null ? op.name : op.value;
	if (name == null)
		ac.fail_json(result, 'name or value required for rename');
	if (key.option != null)
		u.rename(key.config, key.section, key.option, sprintf('%s', name));
	else
		u.rename(key.config, key.section, sprintf('%s', name));
	result.changed = true;
}

function cmd_reorder(u, op, key) {
	u.reorder(key.config, key.section, int(op.value));
	result.changed = true;
}

function cmd_commit(u, op, key) {
	// Only report a change if there are pending changes to commit.
	let pending = key.config != null ? u.changes(key.config) : u.changes();
	// ucode-lsp disable-next-line incompatible-function-argument
	if (pending != null && length(keys(pending)) > 0) {
		if (!check_mode) {
			let rc = key.config != null ? u.commit(key.config) : u.commit();
			if (rc == null)
				ac.fail_json(result, 'uci commit failed');
		}
		result.changed = true;
	}
}

function cmd_revert(u, op, key) {
	// Only report a change if there are pending changes to revert.
	let pending = key.config != null ? u.changes(key.config) : u.changes();
	// ucode-lsp disable-next-line incompatible-function-argument
	if (pending != null && length(keys(pending)) > 0) {
		if (!check_mode) {
			if (key.config != null)
				u.revert(key.config);
			else
				u.revert();
		}
		result.changed = true;
	}
}

function cmd_changes(u, op, key) {
	result.changes = key.config != null ? u.changes(key.config) : u.changes();
}

function cmd_export(u, op, key) {
	let cmd = key.config != null ? 'uci export ' + shq(key.config) : 'uci export';
	result.result = run_shell(cmd).out;
}

function cmd_show(u, op, key) {
	let cmd = key.config != null ? 'uci show ' + shq(key.config) : 'uci show';
	result.result = run_shell(cmd).out;
}

function cmd_import(u, op, key) {
	if (check_mode)
		return;
	let merge = ac.coerce_to_bool(op.merge);
	let cmd = 'printf %s ' + shq(sprintf('%s', op.value)) + ' | uci ' + (merge ? '-m ' : '') + 'import';
	if (key.config != null)
		cmd += ' ' + shq(key.config);
	let r = run_shell(cmd);
	if (r.rc != 0)
		ac.fail_json(result, `uci import failed: ${r.out}`);
	result.changed = true;
}

function cmd_batch(u, op, key) {
	if (check_mode)
		return;
	let cmd = 'printf %s ' + shq(sprintf('%s', op.value)) + ' | uci batch';
	let r = run_shell(cmd);
	if (r.rc != 0)
		ac.fail_json(result, `uci batch failed: ${r.out}`);
	result.changed = true;
}

// Match sections of a type against the `find` spec.
function match_find(u, config, sid, sec, option, find) {
	if (option != null && type(find) != 'array') {
		let got = sec[option];
		if (find == null)
			return got != null;
		return ac.is_equal(got, find);
	}
	if (find == null)
		return true;
	if (type(find) == 'object') {
		for (let k in find) {
			if (!ac.is_equal(sec[k], find[k]))
				return false;
		}
		return true;
	}
	if (type(find) == 'array') {
		if (option != null) {
			// compare the option's list to the find list, in order
			let got = sec[option];
			if (got == null)
				return false;
			let gl = type(got) == 'array' ? got : [got];
			if (length(gl) != length(find))
				return false;
			for (let i = 0; i < length(find); i++) {
				if (gl[i] != find[i])
					return false;
			}
			return true;
		}
		// each value must exist as an option name
		for (let i = 0; i < length(find); i++) {
			if (sec[find[i]] == null)
				return false;
		}
		return true;
	}
	return false;
}

function cmd_find(u, op, key, is_all) {
	let section_type = op.type != null ? op.type : key.section;
	let find = op.find;

	if (section_type == null)
		ac.fail_json(result, 'config and type required for find');

	// find_all allows searching by type alone; find requires a discriminator.
	if (!is_all && key.option == null && find == null && type(find) != 'array' && type(find) != 'object')
		ac.fail_json(result, 'config, type and option required for find');

	let all = u.get_all(key.config);
	if (all == null)
		ac.fail_json(result, `config not found: ${key.config}`);

	let matches = [];
	let idx = 0;
	for (let sid in all) {
		let sec = all[sid];
		if (sec['.type'] != section_type)
			continue;
		if (match_find(u, key.config, sid, sec, key.option, find)) {
			let c = `@${section_type}[${idx}]`;
			push(matches, c);
			if (!is_all)
				break;
		}
		idx++;
	}

	if (is_all) {
		result.result_list = matches;
		result.result = '';
		return;
	}
	if (length(matches) == 0) {
		result.result = '';
		ac.fail_json(result, `no matching section found in ${key.config}`);
	}
	result.result = matches[0];
	result.section = matches[0];
}

// Ensure a section of `type` exists. `name` is the desired section name when
// given; otherwise the section is found by `find` or created anonymously.
// Resolve the section (existing / found / created), then ensure its options
// using upsert_section (idempotent, diff-aware) and record a displayable
// diff entry. Handles `section`, `ensure` and `absent` commands.
function cmd_ensure(u, op, key, is_absent) {
	let section_type = op.type != null ? op.type : key.section;
	if (section_type == null)
		ac.fail_json(result, `config, type and name required for ${is_absent ? 'absent' : 'section'}`);
	if (key.config == null)
		ac.fail_json(result, `config, type and name required for ${is_absent ? 'absent' : 'section'}`);

	let name = op.name != null ? op.name : key.section;
	let section = null;

	// If a name is given and such a named section already exists, use it.
	if (name != null && length(name) > 0) {
		let existing = u.get_all(key.config, name);
		if (existing != null) {
			let t = existing['.type'];
			if (t != null && length(t) > 0 && t != section_type)
				ac.fail_json(result, `${name} exists with ${t} instead of ${section_type}`);
			section = name;
		}
	}

	// Find a matching section when no name given (or name lookup failed).
	if (section == null && op.find != null) {
		let all = u.get_all(key.config);
		if (all != null) {
			for (let sid in all) {
				let sec = all[sid];
				if (sec['.type'] != section_type)
					continue;
				if (match_find(u, key.config, sid, sec, key.option, op.find)) {
					section = sid;
					break;
				}
			}
		}
	}

	// Create the section if not found.
	let created = false;
	if (section == null) {
		if (is_absent)
			return null; // nothing to delete
		if (name != null && length(name) > 0)
			u.set(key.config, name, section_type);
		else
			section = u.add(key.config, section_type);
		if (section == null && name != null && length(name) > 0)
			section = name;
		created = true;
	}

	if (is_absent) {
		if (section == null)
			return null;
		// Without `value`, remove the whole section. With `value`, remove only
		// what it refers to (parity with community.openwrt.uci): a list names
		// options to delete, an object lists (option, value) pairs to remove
		// from list options, and a scalar names a single option to delete.
		if (op.value != null) {
			if (type(op.value) == 'array' && length(op.value) > 0) {
				for (let i = 0; i < length(op.value); i++) {
					let opt = sprintf('%s', op.value[i]);
					if (u.get(key.config, section, opt) != null) {
						u.delete(key.config, section, opt);
						result.changed = true;
					}
				}
			} else if (type(op.value) == 'object') {
				for (let k in op.value) {
					let opt = sprintf('%s', k);
					if (u.get(key.config, section, opt) == null)
						continue;
					let val = sprintf('%s', op.value[k]);
					let cur = ac.list_get(u, key.config, section, opt);
					let found = false;
					for (let i = 0; i < length(cur); i++) {
						if (cur[i] == val) {
							found = true;
							break;
						}
					}
					if (found) {
						ac.list_remove(u, key.config, section, opt, val);
						result.changed = true;
					}
				}
			} else {
				let opt = sprintf('%s', op.value);
				if (u.get(key.config, section, opt) != null) {
					u.delete(key.config, section, opt);
					result.changed = true;
				}
			}
			if (result.changed && !check_mode)
				u.save(key.config);
			return section;
		}
		u.delete(key.config, section);
		result.changed = true;
		if (!check_mode)
			u.save(key.config);
		return section;
	}

	// Build the desired option map from `find` (set_find) and `value`.
	let want = {};
	let set_find = ac.coerce_to_bool(ac.get_value(op, 'set_find', true));
	if (set_find && op.find != null && type(op.find) == 'object') {
		for (let k in op.find)
			want[k] = type(op.find[k]) == 'string' || type(op.find[k]) == 'array' ? op.find[k] : sprintf('%s', op.find[k]);
	}
	if (op.value != null && type(op.value) == 'object') {
		for (let k in op.value) {
			let tv = op.value[k];
			if (tv == null)
				continue;   // null means "absent" -> leave out of want (handled as drop)
			want[k] = type(tv) == 'string' || type(tv) == 'array' ? tv : sprintf('%s', tv);
		}
	} else if (op.value != null) {
		want['value'] = sprintf('%s', op.value);
	}

	// `replace`: delete section options not in `want` (or `keep_keys`), for
	// parity with community.openwrt.uci. Keys in `want` are kept; `keep_keys`
	// lists additional options to preserve.
	let drop = {};
	if (ac.coerce_to_bool(op.replace) && !created) {
		let cur = u.get_all(key.config, section);
		if (cur != null) {
			let keep = {};
			for (let k in want)
				keep[k] = true;
			if (op.keep_keys != null) {
				for (let i = 0; i < length(op.keep_keys); i++)
					keep[sprintf('%s', op.keep_keys[i])] = true;
			}
			for (let k in cur) {
				// ucode-lsp disable-next-line incompatible-function-argument   # `k` is a string key here
				if (substr(k, 0, 1) == '.')
					continue;
				if (!keep[k])
					drop[k] = true;
			}
		}
	}

	let r = ac.upsert_section(u, key.config, section, section_type, want, {
		check_mode: check_mode,
		diff: diff_enabled,
		force_save: created,
		drop: drop,
	});
	// A freshly created section is always a change, even if `want` is empty
	// (e.g. `section` with no `value`/`find`), so the section is persisted.
	if (created || r.changed)
		result.changed = true;
	record_diff(key.config, section, section_type, r.before, r.after, op.redact_keys != null ? op.redact_keys : args.redact_keys);

	result.result = section;
	result.section = section;
	return section;
}

// Execute a single operation against the cursor, capturing its result.
function execute_operation(u, op) {
	// Inherit the Ansible-internal flags set at the module level so command
	// handlers honour diff mode and check mode consistently across operations.
	if (op._ansible_diff == null)
		op._ansible_diff = diff_enabled;
	if (op._ansible_check_mode == null)
		op._ansible_check_mode = check_mode;

	let command = resolve_command(op);
	let key = resolve_key(op);

	// Validate required arguments per command (parity with community.openwrt.uci).
	switch (command) {
	case 'batch':
	case 'import':
		if (op.value == null)
			ac.fail_json(result, `value required for ${command}`);
		break;
	case 'add_list':
	case 'del_list':
	case 'rename':
	case 'reorder':
		if (key.config == null || key.section == null || op.value == null)
			ac.fail_json(result, `key and value required for ${command}`);
		break;
	case 'add':
	case 'get':
	case 'delete':
	case 'ensure':
	case 'section':
	case 'absent':
		if (key.config == null)
			ac.fail_json(result, `key required for ${command}`);
		break;
	}

	// Snapshot the current global result fields and reset for this op.
	let changed_before = result.changed;
	result.changed = false;
	// Snapshot pending changes so `changed` reflects an actual UCI delta,
	// matching community.openwrt.uci's hash-of-`uci changes` semantics.
	let changes_before = sprintf('%J', key.config != null ? u.changes(key.config) : u.changes());
	let op_result = ac.new_result();
	op_result.command = command;
	if (key.config != null)
		op_result.config = key.config;
	if (key.section != null)
		op_result.section = key.section;
	if (key.option != null)
		op_result.option = key.option;

	// Clear per-op fields (diff/changes/result) so handlers write fresh; the
	// shared `result.diff` accumulates across operations.
	delete result.result;
	delete result.result_list;
	delete result.changes;
	result.command = command;
	if (key.config != null)
		result.config = key.config;
	if (key.section != null)
		result.section = key.section;
	if (key.option != null)
		result.option = key.option;

	switch (command) {
	case 'get':
		cmd_get(u, op, key);
		break;
	case 'set':
		cmd_set(u, op, key);
		break;
	case 'delete':
		cmd_delete(u, op, key);
		break;
	case 'add':
		cmd_add(u, op, key);
		break;
	case 'add_list':
		cmd_add_list(u, op, key);
		break;
	case 'del_list':
		cmd_del_list(u, op, key);
		break;
	case 'rename':
		cmd_rename(u, op, key);
		break;
	case 'reorder':
		cmd_reorder(u, op, key);
		break;
	case 'commit':
		cmd_commit(u, op, key);
		break;
	case 'revert':
		cmd_revert(u, op, key);
		break;
	case 'changes':
		cmd_changes(u, op, key);
		break;
	case 'export':
		cmd_export(u, op, key);
		break;
	case 'show':
		cmd_show(u, op, key);
		break;
	case 'import':
		cmd_import(u, op, key);
		break;
	case 'batch':
		cmd_batch(u, op, key);
		break;
	case 'find':
		cmd_find(u, op, key, false);
		break;
	case 'find_all':
		cmd_find(u, op, key, true);
		break;
	case 'section':
	case 'ensure':
		cmd_ensure(u, op, key, false);
		break;
	case 'absent':
		cmd_ensure(u, op, key, true);
		break;
	default:
		ac.fail_json(result, `unknown command: ${command}`);
	}

// Derive `changed` from whether pending changes actually grew for the commands
// that stage a delta without persisting (the ones uci.sh derives from a
// hash of `uci changes` before/after). Handlers mark `result.changed`
// optimistically; a command that operated on nothing (e.g. deleting a
// nonexistent option) must report no change. Commands that persist via
// `u.save()` inside the handler (set/section/ensure) are excluded, because
// save() flushes the pending delta and the comparison would be meaningless.
	let flush_snapshot = command == 'delete' || command == 'add'
		|| command == 'add_list' || command == 'del_list'
		|| command == 'rename' || command == 'reorder'
		// In check mode revert does not clear the pending delta, so the
		// before/after comparison would wrongly downgrade `changed`; the
		// handler already reports `changed` only when something is pending.
		|| (command == 'revert' && !check_mode);
	if (flush_snapshot && result.changed) {
		let changes_after = sprintf('%J', key.config != null ? u.changes(key.config) : u.changes());
		if (changes_after == changes_before)
			result.changed = false;
	}

	// Persist changes as a delta (like `uci set` does) unless this op is
	// commit/revert. Without this, changes stay in-memory and are lost when the
	// module process exits. commit() is applied only under autocommit (or an
	// explicit commit op).
	if (!check_mode && command != 'commit' && command != 'revert' && result.changed) {
		if (key.config != null)
			u.save(key.config);
		else
			u.save();
	}

	// Autocommit for this operation.
	if (!check_mode && ac.coerce_to_bool(op.autocommit) && command != 'commit' && command != 'revert') {
		if (key.config != null)
			u.commit(key.config);
		else
			u.commit();
	}

	// Capture the op's outcome into its own result object.
	op_result.changed = result.changed;
	if (result.result != null)
		op_result.result = result.result;
	if (result.result_list != null)
		op_result.result_list = result.result_list;
	if (result.changes != null)
		op_result.changes = result.changes;

	// Restore changed flag from before this op (only true if any op changed).
	result.changed = result.changed || changed_before;
	return op_result;
}

// ---- main -----------------------------------------------------------------

try {
	let u = cursor();
	if (u == null)
		ac.fail_json(result, 'failed to open UCI cursor');

	// Operations mode: run a list of sub-operations on a single cursor.
	if (args.operations != null && type(args.operations) == 'array') {
		result.operations = [];
		for (let i = 0; i < length(args.operations); i++) {
			// Each op was already validated/coerced by validate_argument_spec via the
			// `operations` -> `options` sub-spec.
			let op_result = execute_operation(u, args.operations[i]);
			push(result.operations, op_result);
		}
		// Commit once at the end if autocommit is set at the top level.
		if (!check_mode && ac.coerce_to_bool(args.autocommit))
			// ucode-lsp disable-next-line UC5006   # u == null is guarded above; ac.fail_json() exits
			u.commit();
		ac.exit_json(result);
	}

	// Single operation mode.
	let op_result = execute_operation(u, args);
	ac.exit_json(result);
} catch (e) {
	ac.fail_json(result, `uc_uci error: ${e}\n${ac.trace()}`);
}
