#!/usr/bin/ucode
// WANT_JSON — args passed as a JSON file whose path is ARGV[0]; output on stdout.
// Copyright (c) 2026, Alexei Znamensky (@russoz)
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
import { ac_load_args, ac_bool, ac_get, ac_same, ac_strip_meta, ac_redact, ac_upsert_section, ac_push_diff, ac_result, ac_exit, ac_fail, ac_trace } from './ansible_common.uc';

let args = ac_load_args();
let check_mode = ac_bool(args._ansible_check_mode);
let diff_enabled = ac_bool(args._ansible_diff);
let result = ac_result({ diff: [] });

// ---- small utilities ------------------------------------------------------

// Shell-quote a string for use in a single-command popen.
function shq(s) {
	return "'" + replace(s, "'", "'\\''") + "'";
}

// Run a shell command, returning its combined stdout+stderr.
function run_shell(cmd) {
	let f = popen(cmd + ' 2>&1', 'r');
	let out = f ? f.read('all') : '';
	if (f)
		f.close();
	return out != null ? out : '';
}

// ---- key resolution -------------------------------------------------------

// Resolve the effective key components. `key` takes precedence.
function resolve_key(op) {
	let config = op.config;
	let section = op.section;
	let option = op.option;
	if (op.key != null && length(op.key) > 0) {
		let parts = split(op.key, '.');
		config = parts[0];
		section = parts[1];
		option = parts[2];
	}
	return { config: config, section: section, option: option };
}

// Determine the command; default to `set` if value given else `get`.
function resolve_command(op) {
	if (op.command != null)
		return op.command;
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
		ac_redact(b, a, redact_keys);
	}
	let header = `${config}.${section}`;
	if (section_type != null && length(section_type) > 0)
		header = `${header}=${section_type}`;
	ac_push_diff(result, header, b, a, diff_enabled);
}

// ---- command implementations ----------------------------------------------

function cmd_get(u, op, key) {
	let v = u.get(key.config, key.section, key.option);
	if (v == null)
		ac_fail(result, 'uci get failed for ' + key.config + '.' + key.section + (key.option != null ? '.' + key.option : ''));
	if (type(v) == 'array') {
		result.result_list = v;
		result.result = length(v) > 0 ? v[0] : '';
	} else {
		result.result = sprintf('%s', v);
	}
}

function cmd_set(u, op, key) {
	let value = op.value;
	let before_value;
	if (type(value) == 'array') {
		// Replace the list option with the given values.
		before_value = u.get(key.config, key.section, key.option);
		u.delete(key.config, key.section, key.option);
		for (let i = 0; i < length(value); i++)
			u.list_append(key.config, key.section, key.option, sprintf('%s', value[i]));
	} else {
		before_value = u.get(key.config, key.section, key.option);
		u.set(key.config, key.section, key.option, sprintf('%s', value));
	}
	let after_value = u.get(key.config, key.section, key.option);
	if (!ac_same(before_value, after_value))
		result.changed = true;

	if (result.changed && diff_enabled) {
		let b = {};
		let a = {};
		b[key.option] = before_value != null ? sprintf('%s', before_value) : '';
		a[key.option] = after_value != null ? sprintf('%s', after_value) : '';
		let sec_type = u.get(key.config, key.section);
		record_diff(key.config, key.section, sec_type, b, a, args.redact_keys);
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
			ac_fail(result, 'key required for delete');
	} else {
		// delete <key>=<value> deletes a list item.
		u.list_remove(key.config, key.section, key.option, sprintf('%s', value));
	}
	result.changed = true;
}

function cmd_add(u, op, key) {
	let section_type = op.type != null ? op.type : key.section;
	if (section_type == null)
		ac_fail(result, 'type required for add');
	u.load(key.config);
	let sid = u.add(key.config, section_type);
	if (sid == null)
		ac_fail(result, 'uci add failed for ' + key.config + ' type ' + section_type);
	result.result = sid;
	result.changed = true;
}

function cmd_add_list(u, op, key) {
	let value = sprintf('%s', op.value);
	let unique = ac_bool(op.unique);
	if (unique) {
		let cur = u.get(key.config, key.section, key.option);
		if (cur != null && type(cur) == 'array') {
			for (let i = 0; i < length(cur); i++) {
				if (cur[i] == value)
					return;
			}
		}
	}
	u.list_append(key.config, key.section, key.option, value);
	result.changed = true;
}

function cmd_del_list(u, op, key) {
	u.list_remove(key.config, key.section, key.option, sprintf('%s', op.value));
	result.changed = true;
}

function cmd_rename(u, op, key) {
	let name = op.name != null ? op.name : op.value;
	if (name == null)
		ac_fail(result, 'name or value required for rename');
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
	if (pending != null && length(keys(pending)) > 0) {
		if (!check_mode) {
			let rc = key.config != null ? u.commit(key.config) : u.commit();
			if (rc == null)
				ac_fail(result, 'uci commit failed');
		}
		result.changed = true;
	}
}

function cmd_revert(u, op, key) {
	if (!check_mode) {
		if (key.config != null)
			u.revert(key.config);
		else
			u.revert();
	}
	result.changed = true;
}

function cmd_changes(u, op, key) {
	result.changes = key.config != null ? u.changes(key.config) : u.changes();
}

function cmd_export(u, op, key) {
	let cmd = key.config != null ? 'uci export ' + key.config : 'uci export';
	result.result = run_shell(cmd);
}

function cmd_show(u, op, key) {
	let cmd = key.config != null ? 'uci show ' + key.config : 'uci show';
	result.result = run_shell(cmd);
}

function cmd_import(u, op, key) {
	if (check_mode)
		return;
	let merge = ac_bool(op.merge);
	let cmd = 'printf %s ' + shq(sprintf('%s', op.value)) + ' | uci ' + (merge ? '-m ' : '') + 'import';
	if (key.config != null)
		cmd += ' ' + key.config;
	run_shell(cmd);
	result.changed = true;
}

function cmd_batch(u, op, key) {
	if (check_mode)
		return;
	let cmd = 'printf %s ' + shq(sprintf('%s', op.value)) + ' | uci batch';
	run_shell(cmd);
	result.changed = true;
}

// Match sections of a type against the `find` spec.
function match_find(u, config, sid, sec, option, find) {
	if (option != null && type(find) != 'array') {
		let got = sec[option];
		if (find == null)
			return got != null;
		return ac_same(got, find);
	}
	if (find == null)
		return true;
	if (type(find) == 'object') {
		for (let k in find) {
			if (!ac_same(sec[k], find[k]))
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
		ac_fail(result, 'config and type required for find');

	// find_all allows searching by type alone; find requires a discriminator.
	if (!is_all && key.option == null && find == null && type(find) != 'array' && type(find) != 'object')
		ac_fail(result, 'config, type and option required for find');

	let all = u.get_all(key.config);
	if (all == null)
		ac_fail(result, 'config not found: ' + key.config);

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
		ac_fail(result, 'no matching section found in ' + key.config);
	}
	result.result = matches[0];
	result.section = matches[0];
}

// Ensure a section of `type` exists. `name` is the desired section name when
// given; otherwise the section is found by `find` or created anonymously.
// Resolve the section (existing / found / created), then ensure its options
// using ac_upsert_section (idempotent, diff-aware) and record a displayable
// diff entry. Handles `section`, `ensure` and `absent` commands.
function cmd_ensure(u, op, key, is_absent) {
	let section_type = op.type != null ? op.type : key.section;
	if (section_type == null)
		ac_fail(result, 'config, type and name required for ' + (is_absent ? 'absent' : 'section'));
	if (key.config == null)
		ac_fail(result, 'config, type and name required for ' + (is_absent ? 'absent' : 'section'));

	let name = op.name != null ? op.name : key.section;
	let section = null;

	// If a name is given and such a named section already exists, use it.
	if (name != null && length(name) > 0) {
		let existing = u.get_all(key.config, name);
		if (existing != null) {
			let t = existing['.type'];
			if (t != null && length(t) > 0 && t != section_type)
				ac_fail(result, name + ' exists with ' + t + ' instead of ' + section_type);
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
	if (section == null) {
		if (is_absent)
			return null; // nothing to delete
		if (name != null && length(name) > 0)
			u.set(key.config, name, section_type);
		else
			section = u.add(key.config, section_type);
		if (section == null && name != null && length(name) > 0)
			section = name;
	}

	if (is_absent) {
		if (section == null)
			return null;
		u.delete(key.config, section);
		result.changed = true;
		return section;
	}

	// Build the desired option map from `find` (set_find) and `value`.
	let want = {};
	let set_find = ac_bool(ac_get(op, 'set_find', true));
	if (set_find && op.find != null && type(op.find) == 'object') {
		for (let k in op.find)
			want[k] = type(op.find[k]) == 'string' ? op.find[k] : sprintf('%s', op.find[k]);
	}
	if (op.value != null && type(op.value) == 'object') {
		for (let k in op.value)
			want[k] = type(op.value[k]) == 'string' ? op.value[k] : sprintf('%s', op.value[k]);
	} else if (op.value != null) {
		want['value'] = sprintf('%s', op.value);
	}

	let r = ac_upsert_section(u, key.config, section, section_type, want, {
		check_mode: check_mode,
		diff: diff_enabled,
	});
	if (r.changed)
		result.changed = true;
	record_diff(key.config, section, section_type, r.before, r.after, args.redact_keys);

	result.result = section;
	result.section = section;
	return section;
}

// Execute a single operation against the cursor, capturing its result.
function execute_operation(u, op) {
	// Propagate the top-level Ansible internal flags into the op so command
	// handlers honour diff mode and check mode consistently across operations.
	if (op._ansible_diff == null)
		op._ansible_diff = args._ansible_diff;
	if (op._ansible_check_mode == null)
		op._ansible_check_mode = args._ansible_check_mode;

	let command = resolve_command(op);
	let key = resolve_key(op);

	// Snapshot the current global result fields and reset for this op.
	let changed_before = result.changed;
	let op_result = ac_result();
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
		ac_fail(result, 'unknown command: ' + command);
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
	if (!check_mode && ac_bool(op.autocommit) && command != 'commit' && command != 'revert') {
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

	// Operations mode: run a list of sub-operations on a single cursor.
	if (args.operations != null && type(args.operations) == 'array') {
		result.operations = [];
		for (let i = 0; i < length(args.operations); i++) {
			let op = args.operations[i];
			let op_result = execute_operation(u, op);
			push(result.operations, op_result);
		}
		// Commit once at the end if autocommit is set at the top level.
		if (!check_mode && ac_bool(args.autocommit))
			u.commit();
		ac_exit(result, 0);
	}

	// Single operation mode.
	let op_result = execute_operation(u, args);
	ac_exit(result, 0);
} catch (e) {
	ac_fail(result, 'uc_uci error: ' + e + '\n' + ac_trace());
}