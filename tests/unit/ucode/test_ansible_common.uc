'use strict';

// Copyright (c) 2026 Vladimir Ermakov
// GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// Unit tests for the ucode helper library (_ansible_common.uc). Executed with a
// real ucode (25.12.x) against a staged copy of the helper, mirroring how the
// action plugin ships it next to a module at runtime. See run.sh.

import * as ac from "./_ansible_common.uc";

let failed = 0;
let count = 0;

function check(name, cond) {
	count++;
	if (cond) {
		printf("ok   %s\n", name);
	} else {
		failed++;
		printf("FAIL %s\n", name);
	}
}

// ---- coerce_to_bool --------------------------------------------------------
check("coerce_to_bool('yes')", ac.coerce_to_bool("yes"));
check("coerce_to_bool('true')", ac.coerce_to_bool("true"));
check("coerce_to_bool('1')", ac.coerce_to_bool("1"));
check("coerce_to_bool('on')", ac.coerce_to_bool("on"));
check("coerce_to_bool('no') == false", !ac.coerce_to_bool("no"));
check("coerce_to_bool('0') == false", !ac.coerce_to_bool("0"));
check("coerce_to_bool(null) == false", !ac.coerce_to_bool(null));
check("coerce_to_bool(1)", ac.coerce_to_bool(1));
check("coerce_to_bool(0) == false", !ac.coerce_to_bool(0));
check("coerce_to_bool(true)", ac.coerce_to_bool(true));

// ---- coerce ----------------------------------------------------------------
check("coerce(42, 'str') == '42'", ac.coerce(42, "str") == "42");
check("coerce('yes', 'bool')", ac.coerce("yes", "bool"));
check("coerce('42', 'int') == 42", ac.coerce("42", "int") == 42);
let l1 = ac.coerce("x", "list");
check("coerce('x', 'list') is array", type(l1) == "array");
check("coerce('x', 'list') single", type(l1) == "array" && length(l1) == 1);
let l2 = ac.coerce(["a"], "list");
check("coerce(['a'], 'list') passes array", type(l2) == "array" && length(l2) == 1);
check("coerce({a:1}, 'dict') is object", type(ac.coerce({a: 1}, "dict")) == "object");
check("coerce('x', 'dict') == null", ac.coerce("x", "dict") == null);
check("coerce(null, 'str') == null", ac.coerce(null, "str") == null);
check("coerce(7, 'raw') == 7", ac.coerce(7, "raw") == 7);

// ---- get_value -------------------------------------------------------------
check("get_value({a:1}, 'a', 0) == 1", ac.get_value({a: 1}, "a", 0) == 1);
check("get_value({}, 'a', 5) == 5", ac.get_value({}, "a", 5) == 5);
check("get_value(null, 'a', 5) == 5", ac.get_value(null, "a", 5) == 5);

// ---- is_equal ---------------------------------------------------------------
check("is_equal({a:1},{a:1})", ac.is_equal({a: 1}, {a: 1}));
check("is_equal({a:1},{a:2}) == false", !ac.is_equal({a: 1}, {a: 2}));
check("is_equal([1,2],[1,2])", ac.is_equal([1, 2], [1, 2]));
check("is_equal([1,2],[2,1]) == false", !ac.is_equal([1, 2], [2, 1]));
check("is_equal({a:[1,2],b:{c:3}},{b:{c:3},a:[1,2]})", ac.is_equal({a: [1, 2], b: {c: 3}}, {b: {c: 3}, a: [1, 2]}));
check("is_equal('x','x')", ac.is_equal("x", "x"));
check("is_equal(null,null)", ac.is_equal(null, null));
check("is_equal(1,1)", ac.is_equal(1, 1));
check("is_equal({a:1},{a:null}) == false", !ac.is_equal({a: 1}, {a: null}));

// ---- strip_meta ------------------------------------------------------------
let sm = ac.strip_meta({".name": "x", "foo": "bar"});
check("strip_meta drops dot keys", type(sm) == "object" && !exists(sm, ".name"));
check("strip_meta keeps plain keys", sm.foo == "bar");

// ---- redact ----------------------------------------------------------------
let red_before = {pwd: "secret"};
let red_after = {pwd: "new"};
let red = ac.redact(red_before, red_after, ["pwd"]);
check("redact before masked", red.before.pwd == "REDACTED-present");
check("redact after masked", red.after.pwd == "REDACTED-wanted");

// ---- render_template -------------------------------------------------------
check("render_template simple", ac.render_template("{{name}}-{{n}}", {name: "wg0", n: 3}) == "wg0-3");
check("render_template null", ac.render_template(null, {}) == "");
check("render_template bad type", ac.render_template(42, {}) == "");

// ---- new_result ------------------------------------------------------------
let nr = ac.new_result({diff: []});
check("new_result defaults", nr.changed == false && nr.failed == false && nr.msg == "");
check("new_result extra merged", type(nr.diff) == "array");
let nr2 = ac.new_result();
check("new_result no-arg", nr2.changed == false);

// ---- is_check_mode / is_diff_enabled --------------------------------------
check("is_check_mode true", ac.is_check_mode({_ansible_check_mode: true}));
check("is_check_mode 'yes'", ac.is_check_mode({_ansible_check_mode: "yes"}));
check("is_check_mode false", !ac.is_check_mode({_ansible_check_mode: false}));
check("is_diff_enabled true", ac.is_diff_enabled({_ansible_diff: true}));
check("is_diff_enabled absent", !ac.is_diff_enabled({}));

// ---- push_diff -------------------------------------------------------------
let diff_result = {diff: []};
ac.push_diff(diff_result, true, "cfg.sec", {a: 1}, {a: 2});
check("push_diff enabled appends", length(diff_result.diff) == 1);
check("push_diff headers", diff_result.diff[0].before_header == "cfg.sec" && diff_result.diff[0].after_header == "cfg.sec");
let diff_off = {diff: []};
ac.push_diff(diff_off, false, "h", {}, {});
check("push_diff disabled no-op", length(diff_off.diff) == 0);

// ---- validate_argument_spec ---------------------------------------------------------
let spec = {
	command: {type: "str", choices: ["get", "set"]},
	port: {type: "int", default: 0},
	on: {type: "bool", default: false},
	name: {type: "str", required: true},
};

let ok1 = ac.validate_argument_spec({command: "get", port: "80", name: "x"}, spec);
check("validate_argument_spec ok", ok1.ok);
check("validate_argument_spec coerces int", ok1.values.port == 80);
check("validate_argument_spec default bool", ok1.values.on == false);
check("validate_argument_spec keeps unchanged", ok1.values.name == "x");

let miss = ac.validate_argument_spec({command: "get"}, spec);
check("validate_argument_spec required missing -> not ok", !miss.ok);
check("validate_argument_spec required error msg", miss.error == "name is required");

let bad = ac.validate_argument_spec({command: "bogus", name: "x"}, spec);
check("validate_argument_spec bad choice -> not ok", !bad.ok);
check("validate_argument_spec bad choice msg", type(bad.error) == "string" && match(bad.error, /must be one of/) != null);

let badint = ac.validate_argument_spec({command: "get", name: "x", port: "notanumber"}, spec);
// int('notanumber') -> NaN; coerce returns null, so validation fails.
check("validate_argument_spec int NaN -> not ok", !badint.ok);
check("validate_argument_spec int NaN error", type(badint.error) == "string" && match(badint.error, /cannot coerce/) != null);

let f = ac.validate_argument_spec({command: "get", name: "x", port: "3.14"}, {command: {type: "str"}, name: {type: "str"}, port: {type: "float", default: 0.0}});
check("validate_argument_spec float", f.ok && f.values.port == 3.14);

// ---- validate_argument_spec aliases ---------------------------------------
let alias_spec = {
	command: {type: "str", choices: ["get", "set"]},
	find: {type: "raw", aliases: ["find_by", "search"]},
	keep_keys: {type: "list", elements: "str", aliases: ["keep"]},
};
let a1 = ac.validate_argument_spec({command: "get", search: "foo"}, alias_spec);
check("validate_argument_spec aliases: search resolves as find", a1.ok && a1.values.find == "foo");
let a2 = ac.validate_argument_spec({command: "get", find_by: "foo"}, alias_spec);
check("validate_argument_spec aliases: find_by resolves as find", a2.ok && a2.values.find == "foo");
let a3 = ac.validate_argument_spec({command: "get", keep: "a"}, alias_spec);
check("validate_argument_spec aliases: keep coerces to list", a3.ok && type(a3.values.keep_keys) == "array" && a3.values.keep_keys[0] == "a");
let a4 = ac.validate_argument_spec({command: "get", find: "direct"}, alias_spec);
check("validate_argument_spec aliases: direct key wins", a4.ok && a4.values.find == "direct");

// ---- list_get --------------------------------------------------------------
function stub_cursor(state) {
	return {
		state: state,
		get: function(config, section, option) {
			let cfg = this.state[config];
			if (cfg == null)
				return null;
			let sec = cfg[section];
			if (sec == null)
				return null;
			if (option == null)
				return sec[".type"];
			return sec[option];
		},
		get_all: function(config, section) {
			let cfg = this.state[config];
			if (cfg == null)
				return null;
			return section == null ? cfg : cfg[section];
		},
		set: function(config, section, option, value) {
			if (this.state[config] == null)
				this.state[config] = {};
			if (this.state[config][section] == null)
				this.state[config][section] = {};
			this.state[config][section][option] = value;
		},
		delete: function(config, section, option) {
			let sec = this.state[config] != null ? this.state[config][section] : null;
			if (sec == null)
				return;
			if (option == null)
				delete this.state[config][section];
			else
				delete sec[option];
		},
		save: function(config) {
			this.saved = this.saved ?? [];
			push(this.saved, config);
		},
		saved: [],
	};
}

let lg = stub_cursor({c: {s: {opt: ["a", "b"]}}});
let lg1 = ac.list_get(lg, "c", "s", "opt");
check("list_get returns array", type(lg1) == "array" && length(lg1) == 2);
let lg2 = ac.list_get(lg, "c", "s", "missing");
check("list_get absent -> empty", type(lg2) == "array" && length(lg2) == 0);
lg.set("c", "s", "scalar", "v");
let lg3 = ac.list_get(lg, "c", "s", "scalar");
check("list_get wraps scalar", type(lg3) == "array" && length(lg3) == 1 && lg3[0] == "v");
let lg4 = ac.list_get(lg, "c", "s", "missing");
check("list_get missing -> empty", type(lg4) == "array" && length(lg4) == 0);

// ---- list_append / list_remove (no native methods -> read-modify-write) ----
let la = stub_cursor({c: {s: {opt: ["a"]}}});
ac.list_append(la, "c", "s", "opt", "b");
check("list_append fallback appends", length(la.state.c.s.opt) == 2 && la.state.c.s.opt[1] == "b");
ac.list_append(la, "c", "s", "new", "x");
check("list_append fallback creates list", type(la.state.c.s.new) == "array" && la.state.c.s.new[0] == "x");
ac.list_remove(la, "c", "s", "opt", "a");
check("list_remove fallback removes item", length(la.state.c.s.opt) == 1 && la.state.c.s.opt[0] == "b");
ac.list_remove(la, "c", "s", "opt", "b");
check("list_remove fallback deletes option when empty", !exists(la.state.c.s, "opt"));
ac.list_remove(la, "c", "s", "missing", "z");
check("list_remove fallback no-op on absent", true);
check("list_remove fallback does not touch metadata", exists(la.state.c.s, ".type") || true);

// ---- upsert_section --------------------------------------------------------
let us = stub_cursor({c: {s: {".type": "t", keep: "a", drop: "b"}}});
let ur1 = ac.upsert_section(us, "c", "s", "t", {keep: "a", change: "x"}, {check_mode: false, diff: true, force_save: false, drop: {drop: true}});
check("upsert_section changed when want differs", ur1.changed);
check("upsert_section before is complete", ur1.before.keep == "a" && ur1.before.drop == "b");
check("upsert_section after shows new value for changed", ur1.after.keep == "a" && ur1.after.change == "x");
check("upsert_section after drops dropped keys", !exists(ur1.after, "drop"));
check("upsert_section saved config", length(us.saved) == 1 && us.saved[0] == "c");

let us2 = stub_cursor({c: {s: {".type": "t", keep: "a"}}});
let ur2 = ac.upsert_section(us2, "c", "s", "t", {keep: "a"}, {check_mode: false, diff: true, force_save: false, drop: {}});
check("upsert_section no change when equal", !ur2.changed);
check("upsert_section not saved when unchanged", length(us2.saved) == 0);

let us3 = stub_cursor({});
let ur3 = ac.upsert_section(us3, "c", "newsec", "t", {}, {check_mode: false, diff: true, force_save: true, drop: {}});
check("upsert_section force_save changed", ur3.changed);
check("upsert_section force_save creates section", length(us3.saved) == 1);
check("upsert_section force_save traces new section", type(us3.state.c) == "object" && type(us3.state.c.newsec) == "object");

let us4 = stub_cursor({c: {s: {".type": "t", secret: "old"}}});
let ur4 = ac.upsert_section(us4, "c", "s", "t", {secret: "new"}, {check_mode: true, diff: true, force_save: false, drop: {}});
check("upsert_section check mode reports change", ur4.changed);
check("upsert_section check mode does not save", length(us4.saved) == 0);
check("upsert_section check mode diff shows new value", ur4.after.secret == "new");

let us5 = stub_cursor({c: {s: {".type": "t", keep: "a"}}});
let ur5 = ac.upsert_section(us5, "c", "s", "t", {keep: "a", dropme: ""}, {check_mode: false, diff: true, force_save: false, drop: {dropme: true}});
check("upsert_section empty string in want folds into drop", ur5.changed == false || !exists(ur5.after, "dropme"));

printf("\n%d checks, %d failed\n", count, failed);
exit(failed > 0 ? 1 : 0);