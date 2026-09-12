// Copyright (c) Ansible Project
// GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// ansible_common.uc — shared helper library for ucode-based community.openwrt
// modules. Modules `import { ... } from './ansible_common.uc'` and use these
// helpers to implement the Ansible module contract (result object, failure,
// change detection), plus ucode/UCI utilities.
//
// ucode notes (see docs/docsite/rst/mod_dev_guide.rst):
//   - `export function name(...) {...};` must end with a semicolon.
//   - Functions are not hoisted: define before use, no forward declarations.
//   - Arrays use the global helpers (push, sort, length); not array methods.
//   - Strings are not []-indexable; use substr(s, i, 1).
//   - JSON: decode with json(str), encode with sprintf("%J", obj).

'use strict';

import { readfile } from 'fs';

// ---- argument / value coercion -------------------------------------------

// Coerce a JSON value to a ucode boolean. Accepts bool, int and common
// string representations ("true", "yes", "1", "on").
export function ac_bool(v) {
	if (v == null)
		return false;
	switch (type(v)) {
	case 'bool':
		return v;
	case 'int':
	case 'double':
		return v != 0;
	case 'string':
		return v == 'true' || v == 'yes' || v == '1' || v == 'on';
	default:
		return false;
	}
};

// Return the JSON value under `key`, or `dflt` when absent/null.
export function ac_get(obj, key, dflt) {
	if (obj == null)
		return dflt;
	let v = obj[key];
	return v != null ? v : dflt;
};

// ---- change detection / diff helpers --------------------------------------

// Deep-compare two values via sorted-key equality. Used to decide whether a
// UCI section/option actually changed (idempotency).
export function ac_same(a, b) {
	if (a == null || b == null)
		return a == b;
	if (type(a) != type(b))
		return false;
	if (type(a) != 'object') {
		if (type(a) == 'array')
			return sprintf('%J', a) == sprintf('%J', b);
		return a == b;
	}
	let ak = sort(keys(a));
	let bk = sort(keys(b));
	if (length(ak) != length(bk))
		return false;
	for (let i = 0; i < length(ak); i++) {
		if (ak[i] != bk[i])
			return false;
		if (!ac_same(a[ak[i]], b[bk[i]]))
			return false;
	}
	return true;
};

// Drop UCI meta keys (".name", ".type", ".anonymous", ".index") from a section
// dict returned by cursor().get_all(), so it compares cleanly against the
// desired option map.
export function ac_strip_meta(s) {
	let out = {};
	for (let k in s) {
		if (substr(k, 0, 1) == '.')
			continue;
		out[k] = s[k];
	}
	return out;
};

// Mask sensitive option values in a before/after diff pair. For each key in
// `redact_keys`, if the value differs, replace it with "REDACTED-wanted"/"
// REDACTED-present"; if equal (or absent), keep a single "REDACTED" marker.
// The real value must never appear in module output.
export function ac_redact(before, after, redact_keys) {
	for (let i = 0; i < length(redact_keys); i++) {
		let key = redact_keys[i];
		let b = before != null ? before[key] : null;
		let a = after != null ? after[key] : null;
		let have_b = b != null && length(sprintf('%s', b)) > 0;
		let have_a = a != null && length(sprintf('%s', a)) > 0;
		if (have_b)
			before[key] = have_a && b == a ? 'REDACTED' : 'REDACTED-present';
		if (have_a)
			after[key] = have_b && b == a ? 'REDACTED' : 'REDACTED-wanted';
	}
	return { before: before, after: after };
};

// ---- Ansible module result contract --------------------------------------

// Render a ucode template string (Jinja-style ``{{ ... }}`` / ``{% ... %}``)
// against the given scope and return the output as a string. Uses ucode's
// native template engine via ``loadstring(str, { raw_mode: false })`` +
// ``render()``; template variables are read from the global scope, so the
// scope dict is bound globally for the duration of the render and restored
// afterwards. Returns an empty string on error.
export function ac_render_template(str, scope) {
	if (str == null)
		return '';
	let saved = {};
	for (let k in scope) {
		saved[k] = global[k];
		global[k] = scope[k];
	}
	let out;
	try {
		out = render(loadstring(str, { raw_mode: false }));
	} catch (e) {
		out = null;
	}
	for (let k in saved)
		global[k] = saved[k];
	return out != null ? out : '';
};

// Idempotently write a named UCI section. Reads the current section, compares
// against the desired `want` option map (plus optional `drop` keys that must be
// absent), and only writes when something differs. Ensures the named section
// exists with the given `type`, sets each `want` key, deletes `drop` keys, and
// persists (unless check mode). Returns { before, after, changed }.
//
// Diff computation (building the `after` map and applying redaction) is skipped
// unless `opts.diff` is true, so callers with `diff: false` avoid the overhead.
// When `opts.redact_keys` is given, those option values are masked in the diff
// via ac_redact().
export function ac_upsert_section(u, config, sid, sec_type, want, opts) {
	if (opts == null)
		opts = {};

	let before = {};
	let cur = u.get_all(config, sid);
	if (cur != null)
		before = ac_strip_meta(cur);

	let drop = opts.drop != null ? opts.drop : {};
	let changed = false;
	for (let k in want) {
		// An empty-string value means "absent" (UCI removes an option set to '').
		// Fold such keys into the drop set and treat them as absent for the
		// comparison, so they are not re-written on every run.
		if (type(want[k]) == 'string' && length(want[k]) == 0) {
			drop[k] = true;
			if (before[k] != null)
				changed = true;
			continue;
		}
		if (sprintf('%J', before[k]) != sprintf('%J', want[k]))
			changed = true;
	}
	for (let k in drop) {
		if (before[k] != null)
			changed = true;
	}

	if (changed) {
		u.set(config, sid, sec_type);
		for (let k in want) {
			if (drop[k])
				continue;
			u.set(config, sid, k, want[k]);
		}
		for (let k in drop) {
			// Setting an option to '' removes it in UCI; no explicit delete needed.
			u.set(config, sid, k, '');
		}
		if (!ac_bool(opts.check_mode))
			u.save(config);
	}

	if (!ac_bool(opts.diff)) {
		// Diff disabled: only `changed` is needed, skip after/redaction.
		return { changed: changed };
	}

	let after = {};
	for (let k in want)
		after[k] = want[k];
	for (let k in before) {
		if (!drop[k])
			after[k] = before[k];
	}

	if (opts.redact_keys != null && length(opts.redact_keys) > 0)
		ac_redact(before, after, opts.redact_keys);

	return { before: before, after: after, changed: changed };
};

// Append a diff entry to the result for Ansible's --diff display. `diff` must
// be set on the result (e.g. result.diff = []). The entry carries a UCI-style
// header (e.g. "network.wg0" or "firewall.wg0_in") and before/after mappings,
// which Ansible serializes and shows as a unified diff. No-op when `enabled`
// is false (diff mode off).
export function ac_push_diff(result, header, before, after, enabled) {
	if (result == null || result.diff == null || !ac_bool(enabled))
		return;
	push(result.diff, {
		before: before,
		after: after,
		before_header: header,
		after_header: header,
	});
};

// Load and parse the module args. Ansible passes the args as a JSON file whose
// path is the first command-line argument (non_native_want_json style).
// Returns the parsed args object or calls die() on error.
export function ac_load_args() {
	if (length(ARGV) < 1)
		die('missing args file');
	let raw = readfile(ARGV[0]);
	if (raw == null)
		die(`cannot read args file ${ARGV[0]}`);
	let args = json(raw);
	if (args == null)
		die('failed to parse args JSON');
	return args;
};

// Build the standard result object. `changed` and `failed` default to false.
// Optional `extra` dict is spread into the result so callers can pre-initialize
// fields (e.g. ac_result({ diff: [], interfaces: [] })).
export function ac_result(extra) {
	let r = {
		changed: false,
		failed: false,
		msg: '',
	};
	if (extra != null) {
		for (let k in extra)
			r[k] = extra[k];
	}
	return r;
};

// Print the result as JSON and exit. Non-zero rc marks failure.
export function ac_exit(result, rc) {
	printf('%J\n', result);
	exit(rc);
};

// Mark the result as failed with a message, print it, and exit non-zero.
export function ac_fail(result, msg) {
	result.failed = true;
	result.msg = msg;
	printf('%J\n', result);
	exit(1);
};

// Determine whether the module runs in check mode from the args dict.
export function ac_check_mode(args) {
	return ac_bool(args._ansible_check_mode);
};

// Return a stack trace string for error reporting. Uses the optional `debug`
// ucode module when available (ucode-mod-debug); returns an empty string on
// targets without it. Never aborts - failures degrade to a plain message.
export function ac_trace() {
	try {
		let dbg = require('debug');
		if (dbg == null || dbg.traceback == null)
			return '';
		return sprintf('%J\n', dbg.traceback(1));
	} catch (e) {
		return '';
	}
};