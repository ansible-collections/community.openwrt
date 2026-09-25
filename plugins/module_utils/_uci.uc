// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// Helpers shared by modules using OpenWrt's native ucode UCI bindings.

// UCI stores scalar values as strings. Normalize inputs before comparing or
// writing them so bool and numeric playbook values remain idempotent.
export function normalize_value(value) {
    if (type(value) == 'bool')
        return value ? '1' : '0';
    if (type(value) in [ 'int', 'double' ])
        return sprintf('%s', value);
    if (type(value) == 'array')
        return map(value, (item) => normalize_value(item));
    return value;
};

export function equal(left, right) {
    return sprintf('%J', left) == sprintf('%J', right);
};

// Remove metadata such as .name and .type from cursor.get_all() output.
export function section_values(section) {
    let values = {};
    if (section == null)
        return values;

    for (let name in section)
        if (substr(name, 0, 1) != '.')
            values[name] = section[name];

    return values;
};

function copy_object(value) {
    let copied = {};
    for (let name in value)
        copied[name] = value[name];
    return copied;
}

// Return redacted copies, leaving the state used for change detection intact.
export function redact(before, after, redact_keys) {
    let safe_before = copy_object(before);
    let safe_after = copy_object(after);

    if (redact_keys == null)
        return { before: safe_before, after: safe_after };

    for (let name in redact_keys) {
        let old_value = safe_before[name];
        let new_value = safe_after[name];
        let had_old = old_value != null;
        let has_new = new_value != null;

        if (had_old)
            safe_before[name] = has_new && equal(old_value, new_value)
                ? 'REDACTED' : 'REDACTED-present';
        if (has_new)
            safe_after[name] = had_old && equal(old_value, new_value)
                ? 'REDACTED' : 'REDACTED-wanted';
    }

    return { before: safe_before, after: safe_after };
};

export function diff_entry(config, section, section_type, before, after, redact_keys) {
    let safe = redact(before, after, redact_keys);
    let header = `${config}.${section}`;
    if (section_type != null && section_type != '')
        header += `=${section_type}`;

    return {
        before: safe.before,
        after: safe.after,
        before_header: header,
        after_header: header,
    };
};

export function list_get(cursor, config, section, option) {
    let value = cursor.get(config, section, option);
    if (value == null)
        return [];
    return type(value) == 'array' ? value : [ value ];
};

// list_append/list_remove were added after the oldest supported OpenWrt. Use
// read-modify-write when the cursor does not expose them.
export function list_append(cursor, config, section, option, value) {
    if (type(cursor.list_append) == 'function') {
        return cursor.list_append(config, section, option, value);
    }

    let values = list_get(cursor, config, section, option);
    push(values, value);
    return cursor.set(config, section, option, values);
};

export function list_remove(cursor, config, section, option, value) {
    if (type(cursor.list_remove) == 'function') {
        return cursor.list_remove(config, section, option, value);
    }

    let values = filter(list_get(cursor, config, section, option), (item) => item != value);
    if (length(values) == 0)
        return cursor.delete(config, section, option);
    return cursor.set(config, section, option, values);
};

// Apply a complete option map and an explicit set of removals. The cursor is
// deliberately mutated in check mode too, but save() is skipped; this lets
// later operations in one batch observe the simulated state.
export function upsert_section(cursor, config, section, section_type, wanted, dropped) {
    let before = section_values(cursor.get_all(config, section));
    let after = copy_object(before);

    for (let name in wanted) {
        let value = normalize_value(wanted[name]);
        if (value == null || value == '' || (type(value) == 'array' && length(value) == 0)) {
            dropped[name] = true;
            delete after[name];
        } else {
            after[name] = value;
        }
    }
    for (let name in dropped)
        delete after[name];

    let changed = !equal(before, after);
    if (changed) {
        if (cursor.set(config, section, section_type) == null)
            return { error: cursor.error(), changed: false, before: before, after: before };
        for (let name in wanted) {
            if (dropped[name])
                continue;
            if (cursor.set(config, section, name, normalize_value(wanted[name])) == null)
                return { error: cursor.error(), changed: false, before: before, after: before };
        }
        for (let name in dropped)
            if (before[name] != null && cursor.delete(config, section, name) == null)
                return { error: cursor.error(), changed: false, before: before, after: before };
    }

    return { changed: changed, before: before, after: after };
};
