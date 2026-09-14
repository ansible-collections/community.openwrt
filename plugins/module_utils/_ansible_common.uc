// Copyright (c) Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// _ansible_common.uc — shared helper library for ucode-based modules.
// Modules use these helpers to implement the Ansible module contract
// (result object, failure, change detection), plus ucode/UCI utilities.

'use strict';

import { readfile } from 'fs';

// ---- argument / value coercion -------------------------------------------

/**
 * Coerce a JSON value to a ucode boolean. Accepts bool, int and common
 * string representations ("true", "yes", "1", "on").
 * @param {boolean|int|double|string|null} v value to coerce
 * @returns {boolean}
 */
export function coerce_to_bool(v) {
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

/**
 * Return the JSON value under `key`, or `dflt` when absent/null.
 * @param {object|null} obj object to read from
 * @param {string} key key to look up
 * @param {string|array|object|boolean|int|double|null} dflt fallback value
 * @returns {string|array|object|boolean|int|double|null}
 */
export function get_value(obj, key, dflt) {
	if (obj == null)
		return dflt;
	let v = obj[key];
	return v != null ? v : dflt;
};

/**
 * Coerce a value to the requested ucode type. Returns the coerced value, or
 * `null` when the value cannot be coerced. Supported types:
 *   - 'str'  -> sprintf("%s", v)          (null -> null)
 *   - 'path' -> sprintf("%s", v)          (alias of str; ucode has no path type)
 *   - 'bool' -> coerce_to_bool(v)
 *   - 'int'  -> int(v)                    (non-numeric -> null)
 *   - 'float'-> numeric to double (v * 1) (non-numeric -> null)
 *   - 'list' -> value as-is if array, else a single-element array
 *   - 'dict' -> value as-is if object, else null
 *   - 'raw'  -> value unchanged
 * @param {string|array|object|boolean|int|double|null} v value to coerce
 * @param {string} type_ one of 'str', 'path', 'bool', 'int', 'float', 'list',
 *                 'dict', 'raw'
 * @returns {string|array|object|boolean|int|double|null}
 */
export function coerce(v, type_) {
	if (v == null)
		return null;
	switch (type_) {
	case 'str':
	case 'path':
		return sprintf('%s', v);
	case 'bool':
		return coerce_to_bool(v);
	case 'int': {
		let n = int(v);
		return n == n ? n : null;
	}
	case 'float': {
		let f = v * 1;
		return f == f ? f : null;
	}
	case 'list':
		return type(v) == 'array' ? v : [ v ];
	case 'dict':
		return type(v) == 'object' ? v : null;
	default:
		return v;
	}
};

/**
 * Declaratively validate/coerce a set of input arguments against a spec, in the
 * spirit of Ansible's `argument_spec`. `spec` is a dict keyed by argument name;
 * each value is a `Spec`:
 *   { type: 'str'|'path'|'bool'|'int'|'float'|'list'|'dict'|'raw'
 *     (default 'str'),
 *     elements: element type when type == 'list',
 *     default, required, choices,
 *     aliases: [alt names],
 *     options: sub-spec for dict / list-of-dicts,
 *     apply_defaults: apply sub-option defaults when the parent is absent }
 *
 * Missing keys fall back to `default`; a `required` key that is absent/null is
 * an error. Values are coerced via coerce(); a coercible failure or a value not
 * in `choices` is also an error. For `type: 'list'` entries, each element is
 * coerced to `elements` and/or validated against `options` (Ansible-style
 * sub-elements). `type: 'dict'` entries with `options` validate the nested keys.
 *
 * Returns { ok: true, values } on success, or { ok: false, error } on the first
 * problem. The caller is expected to call fail_json() with the error string.
 * @param {object} args raw input args
 * @param {object} spec argument spec (name -> Spec)
 * @returns {{ok: boolean, values: object, error: string|null}}
 */
export function validate_argument_spec(args, spec) {
	let values = {};
	for (let name in spec) {
		let s = spec[name];
		let type_ = s.type != null ? s.type : 'str';

		// Resolve the value: the argument itself or one of its aliases. `exists`
		// distinguishes a present-but-null key from an absent one.
		let present = exists(args, name);
		let v = args[name];
		if (!present && s.aliases != null) {
			for (let i = 0; i < length(s.aliases); i++) {
				let alias = s.aliases[i];
				// ucode-lsp disable-next-line incompatible-function-argument
				if (exists(args, alias)) {
					present = true;
					v = args[alias];
					break;
				}
			}
		}

		if (!present)
			v = s.default;

		if (!present && s.required)
			return { ok: false, values: {}, error: `${name} is required` };

		// Coerce the resolved value (either the user-provided one or the default).
		let c = null;
		if (v != null) {
			c = coerce(v, type_);
		} else if (s.options != null && s.apply_defaults) {
			// apply_defaults: even when absent, build the sub-option defaults.
			// Empty input -> validate_argument_spec fills in every sub-option default.
			// If a sub-option is required (and thus has no default), ok=false
			// and we fall through with c == null.
			let d = validate_argument_spec({}, s.options);
			if (d.ok)
				c = d.values;
		}

		if (c == null && v != null)
			return { ok: false, values: {}, error: `cannot coerce ${name} to ${type_}` };

		// List handling: coerce each element to `elements` and/or validate
		// against `options`.
		if (type_ == 'list' && c != null) {
			let elems = [];
			// ucode-lsp disable-next-line nullable-argument   # `c` is an array here (type == 'list')
			for (let i = 0; i < length(c); i++) {
				let e = s.elements != null ? coerce(c[i], s.elements) : c[i];
				if (e == null)
					return { ok: false, values: {}, error: `${name}[${i}] cannot be coerced to ${s.elements}` };
				if (s.options != null) {
					let sub = validate_argument_spec(c[i], s.options);
					if (!sub.ok)
						return { ok: false, values: {}, error: `${name}[${i}]: ${sub.error}` };
					e = sub.values;
				}
				push(elems, e);
			}
			c = elems;
		}

		// Dict handling: validate nested keys against `options`.
		if (type_ == 'dict' && s.options != null && c != null) {
			let sub = validate_argument_spec(c, s.options);
			if (!sub.ok)
				return { ok: false, values: {}, error: `${name}: ${sub.error}` };
			c = sub.values;
		}

		if (s.choices != null && c != null) {
			let ok = false;
			for (let choice in s.choices) {
				if (sprintf('%J', choice) == sprintf('%J', c)) {
					ok = true;
					break;
				}
			}
			if (!ok)
				return { ok: false, values: {}, error: `${name} must be one of: ${sprintf('%J', s.choices)}` };
		}

		values[name] = c;
	}
	return { ok: true, values: values, error: null };
};

// ---- change detection / diff helpers --------------------------------------

/**
 * Deep-compare two values via sorted-key equality. Used to decide whether a
 * UCI section/option actually changed (idempotency). Recurses into nested
 * objects. Note: ucode has no function hoisting, so this is deliberately
 * self-recursive (no helper) to avoid a forward reference.
 * @param {string|array|object|null} a left value
 * @param {string|array|object|null} b right value
 * @returns {boolean}
 */
export function is_equal(a, b) {
	if (a == null || b == null)
		return a == b;
	if (type(a) != type(b))
		return false;
	if (type(a) != 'object') {
		if (type(a) == 'array')
			return sprintf('%J', a) == sprintf('%J', b);
		return a == b;
	}
	// ucode-lsp disable-next-line nullable-argument   # `a` is an object here (guarded above)
	let ak = sort(keys(a));
	// ucode-lsp disable-next-line nullable-argument   # `b` is an object here (guarded above)
	let bk = sort(keys(b));
	if (length(ak) != length(bk))
		return false;
	for (let i = 0; i < length(ak); i++) {
		if (ak[i] != bk[i])
			return false;
	}
	for (let k in a) {
		if (!is_equal(a[k], b[k]))
			return false;
	}
	return true;
};

/**
 * Drop UCI meta keys (".name", ".type", ".anonymous", ".index") from a section
 * dict returned by cursor().get_all(), so it compares cleanly against the
 * desired option map.
 * @param {object} s section dict
 * @returns {object}
 */
export function strip_meta(s) {
	let out = {};
	for (let k in s) {
		if (substr(k, 0, 1) == '.')
			continue;
		out[k] = s[k];
	}
	return out;
};

/**
 * Mask sensitive option values in a before/after diff pair. For each key in
 * `redact_keys`, if the value differs, replace it with "REDACTED-wanted"/"
 * REDACTED-present"; if equal (or absent), keep a single "REDACTED" marker.
 * The real value must never appear in module output.
 */
export function redact(before, after, redact_keys) {
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

/**
 * Render a ucode template string (Jinja-style ``{{ ... }}`` / ``{% ... %}``)
 * against the given scope and return the output as a string. Uses ucode's
 * native template engine via ``loadstring(str, { raw_mode: false })`` +
 * ``render()``; template variables are read from the global scope, so the
 * scope dict is bound globally for the duration of the render and restored
 * afterwards. Returns an empty string on error.
 * @param {string|null} str template source
 * @param {object} scope template variables
 * @returns {string}
 */
export function render_template(str, scope) {
	if (str == null)
		return '';
	if (type(str) != 'string')
		return '';
	let saved = {};
	let absent = {};
	for (let k in scope) {
		if (exists(global, k))
			saved[k] = global[k];
		else
			absent[k] = true;
		global[k] = scope[k];
	}
	let out = '';
	let compiled = loadstring(str, { raw_mode: false });
	if (compiled != null) {
		try {
			out = sprintf('%s', render(compiled));
		} catch (e) {
			out = '';
		}
	}
	for (let k in saved)
		global[k] = saved[k];
	for (let k in absent)
		delete global[k];
	return out;
};

/**
 * @typedef {object} UpsertOptions
 * @property {boolean} [check_mode] skip persisting (u.save) when true
 * @property {boolean} [diff] build the before/after diff (and redaction) when true
 * @property {object} [drop] keys that must be absent from the section
 * @property {array} [redact_keys] option names to mask in the diff output
 * @property {boolean} [force_save] persist the section even when nothing in
 *           `want` changed (used when a section was freshly created)
 */

/**
 * Idempotently write a named UCI section. Reads the current section, compares
 * against the desired `want` option map (plus optional `drop` keys that must be
 * absent), and only writes when something differs. Ensures the named section
 * exists with the given `type`, sets each `want` key, deletes `drop` keys, and
 * persists (unless check mode). Returns { before, after, changed }.
 *
 * Diff computation (building the `after` map and applying redaction) is skipped
 * unless `o.diff` is true, so callers with `diff: false` avoid the overhead.
 * When `o.redact_keys` is given, those option values are masked in the diff
 * via redact().
 * @param {object} u uci cursor
 * @param {string} config config name
 * @param {string} sid section id (or section name)
 * @param {string} sec_type section type
 * @param {object} want desired option map
 * @param {UpsertOptions} [opts] behaviour flags (see UpsertOptions)
 * @returns {{before: object, after: object, changed: boolean}}
 */
export function upsert_section(u, config, sid, sec_type, want, opts) {
	let o = opts ?? {};

	let before = {};
	let cur = u.get_all(config, sid);
	if (cur != null)
		before = strip_meta(cur);

	let drop = o.drop ?? {};
	let changed = false;
	for (let k in want) {
		// An empty value means "absent" (UCI removes an option set to ''): an
		// empty string or an empty list. Fold such keys into the drop set and
		// treat them as absent for the comparison, so they are not re-written
		// on every run.
		let t = type(want[k]);
		// ucode-lsp disable-next-line nullable-argument   # `want[k]` is a string/array here
		let empty_str = (t == 'string' && length(want[k]) == 0);
		// ucode-lsp disable-next-line nullable-argument   # `want[k]` is a string/array here
		let empty_arr = (t == 'array' && length(want[k]) == 0);
		let is_null = (want[k] == null);
		if (empty_str || empty_arr || is_null) {
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
		if (!coerce_to_bool(o.check_mode))
			u.save(config);
	} else if (coerce_to_bool(o.force_save)) {
		// A freshly created section is a change even when `want` is empty; make
		// sure it is persisted.
		changed = true;
		u.set(config, sid, sec_type);
		if (!coerce_to_bool(o.check_mode))
			u.save(config);
	}

	if (!coerce_to_bool(o.diff)) {
		// Diff disabled: only `changed` is needed, skip after/redaction.
		return { changed: changed };
	}

	let after = {};
	for (let k in want) {
		if (drop[k])
			continue;
		after[k] = want[k];
	}
	// Preserve unchanged options that exist before but are not in `want`; do
	// not overwrite the wanted (new) values already written above.
	for (let k in before) {
		if (drop[k] || exists(after, k))
			continue;
		after[k] = before[k];
	}

	if (o.redact_keys != null && length(o.redact_keys) > 0)
		redact(before, after, o.redact_keys);

	return { before: before, after: after, changed: changed };
};

/**
 * Append a diff entry to the result for Ansible's --diff display. `diff` must
 * be set on the result (e.g. result.diff = []). The entry carries a UCI-style
 * header (e.g. "network.wg0" or "firewall.wg0_in") and before/after mappings,
 * which Ansible serializes and shows as a unified diff. No-op when `enabled`
 * is false (diff mode off).
* @param {object} out result object (must carry a `diff` array)
  * @param {boolean} enabled whether diff mode is on
  * @param {string} header UCI-style diff header
  * @param {object|null} before before-state map
  * @param {object|null} after after-state map
  */
 export function push_diff(out, enabled, header, before, after) {
	if (out == null || out.diff == null || !coerce_to_bool(enabled))
		return;
	if (type(out.diff) != 'array')
		return;
	push(out.diff, {
		before: before,
		after: after,
		before_header: header,
		after_header: header,
	});
};

/**
 * Read a UCI option as a list (normalizes a scalar to a single-element list).
 * @param {object} u uci cursor
 * @param {string} config config name
 * @param {string} section section id
 * @param {string} option option name
 * @returns {array} list value (possibly empty)
 */
export function list_get(u, config, section, option) {
	let v = u.get(config, section, option);
	if (v == null)
		return [];
	if (type(v) == 'array')
		return v;
	return [ v ];
};

/**
 * Append a value to a UCI list option. Uses the native `list_append` when
 * available (OpenWrt 24.10+) and falls back to read-modify-write for older
 * targets (23.05) where the cursor lacks `list_append`.
 * @param {object} u uci cursor
 * @param {string} config config name
 * @param {string} section section id
 * @param {string} option option name
 * @param {string} value value to append
 */
export function list_append(u, config, section, option, value) {
	if (type(u.list_append) == 'function') {
		u.list_append(config, section, option, value);
		return;
	}
	let arr = list_get(u, config, section, option);
	push(arr, value);
	u.set(config, section, option, arr);
};

/**
 * Remove a value from a UCI list option (all occurrences). Uses the native
 * `list_remove` when available (24.10+), else read-modify-write.
 * @param {object} u uci cursor
 * @param {string} config config name
 * @param {string} section section id
 * @param {string} option option name
 * @param {string} value value to remove
 */
export function list_remove(u, config, section, option, value) {
	if (type(u.list_remove) == 'function') {
		u.list_remove(config, section, option, value);
		return;
	}
	let arr = [];
	for (let v in list_get(u, config, section, option)) {
		if (v != value)
			push(arr, v);
	}
	if (length(arr) == 0)
		u.delete(config, section, option);
	else
		u.set(config, section, option, arr);
};

/**
 * Load and parse the module args. Ansible passes the args as a JSON file whose
 * path is the first command-line argument (non_native_want_json style).
 * Returns the parsed args object or calls die() on error.
 * @returns {object}
 */
export function load_args() {
	if (length(ARGV) < 1)
		die('missing args file');
	let raw = readfile(ARGV[0]);
	if (raw == null)
		die(`cannot read args file ${ARGV[0]}`);
	let args = null;
	try {
		args = json(raw);
	} catch (e) {
		args = null;
	}
	if (args == null || type(args) != 'object')
		die('failed to parse args JSON');
	return args;
};

/**
 * Build the standard result object. `changed` and `failed` default to false.
 * Optional `extra` dict is spread into the result so callers can pre-initialize
 * fields (e.g. result({ diff: [], interfaces: [] })).
 */
export function new_result(extra) {
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

/**
 * Print the result as JSON and exit with code 0 (success).
 */
export function exit_json(result) {
	// Leading newline mirrors Python's AnsibleModule._return_formatted(), which
	// prints '\n%s' so the connection's stdout capture treats the result as a
	// fresh block regardless of buffering.
	printf('\n%J\n', result);
	exit(0);
};

/**
 * Mark the result as failed with a message, print it, and exit non-zero.
 */
export function fail_json(result, msg) {
	result.failed = true;
	result.msg = msg;
	printf('\n%J\n', result);
	exit(1);
};

/**
 * Determine whether the module runs in check mode from the args dict.
 * @param {object} args parsed module args
 * @returns {boolean}
 */
export function is_check_mode(args) {
	return coerce_to_bool(args._ansible_check_mode);
};

/**
 * Determine whether diff mode is enabled from the args dict.
 * @param {object} args parsed module args
 * @returns {boolean}
 */
export function is_diff_enabled(args) {
	return coerce_to_bool(args._ansible_diff);
};

/**
 * Return a stack trace string for error reporting. Uses the optional `debug`
 * ucode module when available (ucode-mod-debug); returns an empty string on
 * targets without it. Never aborts - failures degrade to a plain message.
 */
export function trace() {
	try {
		let dbg = require('debug');
		if (dbg == null || dbg.traceback == null)
			return '';
		return sprintf('%J\n', dbg.traceback(1));
	} catch (e) {
		return '';
	}
};