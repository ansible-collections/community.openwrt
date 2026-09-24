// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { cursor } from 'uci';
import { AnsibleModule, shell_quote } from '_basic';
import {
    diff_entry,
    equal,
    list_append,
    list_get,
    list_remove,
    normalize_value,
    section_values,
    upsert_section
} from '_uci';

const COMMANDS = [
    'absent', 'add', 'add_list', 'batch', 'changes', 'commit', 'del_list',
    'delete', 'ensure', 'export', 'find', 'find_all', 'get', 'import',
    'rename', 'reorder', 'revert', 'section', 'set', 'show',
];

const OPERATION_SPEC = {
    autocommit: { type: 'bool', default: false },
    command: { type: 'str', choices: COMMANDS, aliases: [ 'cmd' ] },
    config: { type: 'str' },
    find: { type: 'raw', aliases: [ 'find_by', 'search' ] },
    keep_keys: { type: 'raw', aliases: [ 'keep' ] },
    key: { type: 'str' },
    merge: { type: 'bool', default: false },
    name: { type: 'str' },
    option: { type: 'str' },
    redact_keys: { type: 'list', elements: 'str' },
    replace: { type: 'bool', default: false },
    section: { type: 'str' },
    set_find: { type: 'bool', default: true },
    type: { type: 'str' },
    unique: { type: 'bool', default: false },
    value: { type: 'raw' },
};

const module = AnsibleModule({
    argument_spec: {
        ...OPERATION_SPEC,
        operations: { type: 'list', elements: 'dict', options: OPERATION_SPEC },
    },
    supports_check_mode: true,
});

const params = module.params;
let output = {};
let diffs = [];

function fail(msg, fields) {
    module.fail_json({ ...output, ...(fields ?? {}), msg: msg });
}

function has_entries(value) {
    return value != null && length(keys(value)) > 0;
}

function cursor_call(u, value, action, result) {
    if (value == null)
        fail(`${action}: ${u.error() ?? 'UCI operation failed'}`, result);
    return value;
}

function load_all(u, result) {
    let configs = cursor_call(u, u.configs(), 'cannot list UCI configurations', result);
    for (let config in configs)
        cursor_call(u, u.load(config), `cannot load UCI configuration ${config}`, result);
}

function save_changes(u, config, result) {
    cursor_call(u, config != null ? u.save(config) : u.save(), 'cannot save UCI changes', result);
}

function commit_changes(u, config, result) {
    if (config == null)
        load_all(u, result);
    cursor_call(u, config != null ? u.commit(config) : u.commit(), 'cannot commit UCI changes', result);
}

function key_name(key) {
    if (key.config == null)
        return null;
    return key.config + (key.section != null ? `.${key.section}` : '')
        + (key.option != null ? `.${key.option}` : '');
}

function resolve_key(op) {
    let resolved = { config: op.config, section: op.section, option: op.option };
    if (op.key != null && op.key != '') {
        let parts = split(op.key, '.');
        resolved.config = parts[0];
        resolved.section = parts[1];
        resolved.option = parts[2];
    }
    return resolved;
}

function resolve_command(op) {
    return op.command ?? (op.value != null ? 'set' : 'get');
}

function operation(raw) {
    let op = { ...raw, command: resolve_command(raw) };
    if (type(op.keep_keys) == 'string')
        op.keep_keys = filter(split(replace(trim(op.keep_keys), /[ ,]+/g, ','), ','), (item) => item != '');
    else if (type(op.keep_keys) == 'array')
        op.keep_keys = map(op.keep_keys, (item) => sprintf('%s', item));
    else if (op.keep_keys != null)
        fail('keep_keys must be a list or string');
    return op;
}

function add_diff(config, section, section_type, before, after, redact_keys) {
    if (!module.diff_mode || equal(before, after))
        return;
    push(diffs, diff_entry(config, section, section_type, before, after,
                           redact_keys ?? params.redact_keys));
}

function command_get(u, op, key, result) {
    let value = u.get(key.config, key.section, key.option);
    if (value == null)
        fail(`uci get failed for ${key.config}.${key.section}${key.option != null ? '.' + key.option : ''}`,
             { ...result, result: '' });

    if (type(value) == 'array') {
        result.result_list = value;
        result.result = join(' ', value);
    } else {
        result.result = sprintf('%s', value);
        result.result_list = [ result.result ];
    }
}

function command_set(u, op, key, result) {
    if (key.config == null || key.section == null)
        fail('config and section required for set', result);

    let before = section_values(u.get_all(key.config, key.section));
    let after = { ...before };
    let kept = {};

    if (type(op.value) == 'array') {
        if (key.option == null)
            fail('config, section and option required for set', result);
        let value = normalize_value(op.value);
        if (length(value) == 0)
            delete after[key.option];
        else
            after[key.option] = value;
        kept[key.option] = true;
    } else if (type(op.value) == 'object') {
        if (key.option != null)
            fail('config and section but not option required for set', result);
        for (let name in op.value) {
            let value = normalize_value(op.value[name]);
            kept[name] = true;
            if (value == null || value == '')
                delete after[name];
            else
                after[name] = value;
        }
    } else if (key.option != null) {
        let value = normalize_value(op.value);
        kept[key.option] = true;
        if (value == null || value == '')
            delete after[key.option];
        else
            after[key.option] = value;
    } else {
        let current_type = u.get(key.config, key.section);
        let wanted_type = normalize_value(op.value);
        if (current_type != wanted_type) {
            cursor_call(u, u.set(key.config, key.section, wanted_type),
                        `cannot set ${key.config}.${key.section}`, result);
            result.changed = true;
        }
        return;
    }

    if (op.replace) {
        for (let name in op.keep_keys ?? [])
            kept[name] = true;
        for (let name in after)
            if (!kept[name])
                delete after[name];
    }

    if (equal(before, after))
        return;

    for (let name in before)
        if (after[name] == null)
            cursor_call(u, u.delete(key.config, key.section, name),
                        `cannot delete ${key.config}.${key.section}.${name}`, result);
    for (let name in after)
        if (!equal(before[name], after[name]))
            cursor_call(u, u.set(key.config, key.section, name, after[name]),
                        `cannot set ${key.config}.${key.section}.${name}`, result);

    result.changed = true;
}

function command_delete(u, op, key, result) {
    if (key.config == null)
        fail('key required for delete', result);

    if (key.option != null && op.value != null) {
        let wanted = sprintf('%s', normalize_value(op.value));
        let present = wanted in list_get(u, key.config, key.section, key.option);
        if (present) {
            cursor_call(u, list_remove(u, key.config, key.section, key.option, wanted),
                        `cannot remove list value from ${key_name(key)}`, result);
            result.changed = true;
        }
    } else if (key.option != null) {
        if (u.get(key.config, key.section, key.option) != null) {
            cursor_call(u, u.delete(key.config, key.section, key.option),
                        `cannot delete ${key_name(key)}`, result);
            result.changed = true;
        }
    } else if (key.section != null) {
        if (u.get_all(key.config, key.section) != null) {
            cursor_call(u, u.delete(key.config, key.section),
                        `cannot delete ${key_name(key)}`, result);
            result.changed = true;
        }
    } else {
        fail('key required for delete', result);
    }
}

function command_add(u, op, key, result) {
    let section_type = op.type ?? key.section ?? op.value;
    let name = op.name ?? (op.type != null ? key.section : null);
    if (key.config == null || section_type == null)
        fail('config and type required for add', result);

    if (name != null) {
        let existing = u.get_all(key.config, name);
        if (existing != null) {
            if (existing['.type'] != section_type)
                fail(`${key.config}.${name} exists with ${existing['.type']} instead of ${section_type}`, result);
            result.result = name;
            return;
        }
    }

    cursor_call(u, u.get_all(key.config), `cannot load UCI configuration ${key.config}`, result);
    let section = u.add(key.config, section_type);
    if (section == null)
        fail(`uci add failed for ${key.config} type ${section_type}`, result);
    if (name != null) {
        cursor_call(u, u.rename(key.config, section, name),
                    `cannot rename ${key.config}.${section} to ${name}`, result);
        section = name;
    }
    result.result = section;
    result.changed = true;
}

function command_add_list(u, op, key, result) {
    let value = sprintf('%s', normalize_value(op.value));
    let current = list_get(u, key.config, key.section, key.option);
    if (op.unique && value in current)
        return;
    cursor_call(u, list_append(u, key.config, key.section, key.option, value),
                `cannot append list value to ${key_name(key)}`, result);
    result.changed = true;
}

function command_del_list(u, op, key, result) {
    let value = sprintf('%s', normalize_value(op.value));
    if (!(value in list_get(u, key.config, key.section, key.option)))
        return;
    cursor_call(u, list_remove(u, key.config, key.section, key.option, value),
                `cannot remove list value from ${key_name(key)}`, result);
    result.changed = true;
}

function section_matches(values, option, wanted) {
    if (option != null) {
        let actual = values[option];
        if (wanted == null)
            return actual != null;
        return equal(type(actual) == 'array' ? actual : [ actual ],
                     type(wanted) == 'array' ? normalize_value(wanted) : [ normalize_value(wanted) ]);
    }
    if (type(wanted) == 'object') {
        for (let name in wanted)
            if (!equal(values[name], normalize_value(wanted[name])))
                return false;
        return true;
    }
    if (type(wanted) == 'array') {
        for (let name in wanted)
            if (values[name] == null)
                return false;
        return true;
    }
    return wanted == null;
}

function command_find(u, op, key, result, find_all) {
    let section_type = op.type ?? key.section;
    if (key.config == null || section_type == null)
        fail('config and type required for find', result);
    if (!find_all && key.option == null && op.find == null)
        fail('config, type and option required for find', result);

    let config = u.get_all(key.config);
    if (config == null)
        fail(`config not found: ${key.config}`, result);

    let matches = [];
    let index = 0;
    for (let section in config) {
        let values = config[section];
        if (values['.type'] != section_type)
            continue;

        if (section_matches(values, key.option, op.find)) {
            push(matches, `@${section_type}[${index}]`);
            if (!find_all)
                break;
        }
        index++;
    }

    result.result = find_all ? '' : (matches[0] ?? '');
    if (find_all)
        result.result_list = matches;
    else if (length(matches) == 0)
        fail(`no matching section found in ${key.config}`, result);
    else
        result.section = matches[0];
}

function find_section(u, op, key, section_type) {
    let config = u.get_all(key.config) ?? {};
    let index = 0;
    for (let section in config) {
        let values = config[section];
        if (values['.type'] != section_type)
            continue;
        if (section_matches(values, key.option, op.find))
            return { id: section, positional: `@${section_type}[${index}]` };
        index++;
    }
    return null;
}

function command_ensure(u, op, key, result) {
    let section_type = op.type ?? key.section;
    if (key.config == null || section_type == null)
        fail(`config and type required for ${op.command}`, result);

    let name = op.name ?? (op.type != null ? key.section : null);
    let section = name ?? key.section;
    let existing = section != null ? u.get_all(key.config, section) : null;
    if (existing != null && existing['.type'] != section_type)
        fail(`${key.config}.${section} exists with ${existing['.type']} instead of ${section_type}`, result);

    if (existing == null && op.find != null) {
        let found = find_section(u, op, key, section_type);
        section = found != null ? found.positional : null;
        existing = found != null ? u.get_all(key.config, found.id) : null;
        if (existing != null && name != null && section != name) {
            cursor_call(u, u.rename(key.config, found.id, name),
                        `cannot rename ${key.config}.${section} to ${name}`, result);
            section = name;
            result.changed = true;
        }
    }

    let created = false;
    if (existing == null) {
        if (name != null) {
            cursor_call(u, u.set(key.config, name, section_type),
                        `cannot create ${key.config}.${name}`, result);
            section = name;
        } else {
            cursor_call(u, u.get_all(key.config), `cannot load UCI configuration ${key.config}`, result);
            section = u.add(key.config, section_type);
        }
        if (section == null)
            fail(`could not create ${section_type} section in ${key.config}`, result);
        created = true;
    }

    let wanted = {};
    if (op.set_find && type(op.find) == 'object')
        for (let name in op.find)
            wanted[name] = op.find[name];
    if (op.set_find && key.option != null && op.find != null)
        wanted[key.option] = op.find;
    if (type(op.value) == 'object')
        for (let name in op.value)
            wanted[name] = op.value[name];
    else if (op.value != null && key.option != null)
        wanted[key.option] = op.value;

    let dropped = {};
    if (op.replace) {
        let kept = {};
        for (let name in wanted)
            kept[name] = true;
        for (let name in op.keep_keys ?? [])
            kept[name] = true;
        for (let name in section_values(existing))
            if (!kept[name])
                dropped[name] = true;
    }

    let update = upsert_section(u, key.config, section, section_type, wanted, dropped);
    if (update.error != null)
        fail(`cannot update ${key.config}.${section}: ${update.error}`, result);
    result.changed = result.changed || created || update.changed;
    result.result = section;
    result.section = section;
}

function command_absent(u, op, key, result) {
    if (op.find == null && op.value == null) {
        command_delete(u, op, key, result);
        return;
    }

    let section_type = op.type ?? key.section;
    if (key.config == null || (op.find != null && section_type == null))
        fail('config and type required for absent', result);
    let section = op.name ?? (op.find == null || op.type != null ? key.section : null);
    let existing = section != null ? u.get_all(key.config, section) : null;
    if (existing != null && op.type != null && existing['.type'] != section_type)
        fail(`${key.config}.${section} exists with ${existing['.type']} instead of ${section_type}`, result);
    if (existing == null && op.find != null) {
        let found = find_section(u, op, key, section_type);
        if (found == null)
            return;
        section = found.positional;
    } else if (existing == null) {
        return;
    }

    let selected = { config: key.config, section: section, option: key.option };
    if (op.value == null) {
        command_delete(u, op, selected, result);
    } else if (type(op.value) == 'array') {
        for (let option in op.value)
            command_delete(u, { ...op, value: null }, { ...selected, option: option }, result);
    } else if (type(op.value) == 'object') {
        for (let option in op.value)
            command_delete(u, { ...op, value: op.value[option] }, { ...selected, option: option }, result);
    } else {
        command_delete(u, { ...op, value: null }, { ...selected, option: sprintf('%s', op.value) }, result);
    }
    result.section = section;
    result.result = section;
}

function execute(u, op) {
    let key = resolve_key(op);
    let result = { changed: false, command: op.command, result: '' };
    if (key.config != null)
        result.config = key.config;
    if (key.section != null)
        result.section = key.section;
    if (key.option != null)
        result.option = key.option;

    if (op.command in [ 'batch', 'import' ] && op.value == null)
        fail(`value required for ${op.command}`, result);
    if (op.command in [ 'add_list', 'del_list', 'rename', 'reorder' ]
        && (key.config == null || key.section == null || op.value == null))
        fail(`key and value required for ${op.command}`, result);

    let before_section = key.section;
    if (op.command in [ 'section', 'ensure', 'add' ] && op.name != null)
        before_section = op.name;
    let before_state = key.config != null && before_section != null
        ? section_values(u.get_all(key.config, before_section)) : {};
    let before_type = key.config != null && before_section != null
        ? u.get(key.config, before_section) : null;

    switch (op.command) {
    case 'get':
        command_get(u, op, key, result);
        break;
    case 'set':
        command_set(u, op, key, result);
        break;
    case 'delete':
        command_delete(u, op, key, result);
        break;
    case 'add':
        command_add(u, op, key, result);
        break;
    case 'add_list':
        command_add_list(u, op, key, result);
        break;
    case 'del_list':
        command_del_list(u, op, key, result);
        break;
    case 'rename': {
        let name = op.name ?? op.value;
        if (key.option != null)
            cursor_call(u, u.rename(key.config, key.section, key.option, sprintf('%s', name)),
                        `cannot rename ${key_name(key)}`, result);
        else
            cursor_call(u, u.rename(key.config, key.section, sprintf('%s', name)),
                        `cannot rename ${key_name(key)}`, result);
        if (key.option == null)
            result.section = sprintf('%s', name);
        result.changed = true;
        break;
    }
    case 'reorder': {
        let current = u.get_all(key.config, key.section);
        if (current != null && current['.index'] != int(op.value)) {
            cursor_call(u, u.reorder(key.config, key.section, int(op.value)),
                        `cannot reorder ${key_name(key)}`, result);
            result.changed = true;
        }
        break;
    }
    case 'commit': {
        if (key.config == null)
            load_all(u, result);
        let pending = key.config != null ? u.changes(key.config) : u.changes();
        if (has_entries(pending)) {
            if (!module.check_mode)
                commit_changes(u, key.config, result);
            result.changed = true;
        }
        break;
    }
    case 'revert': {
        if (key.config == null)
            load_all(u, result);
        let pending = key.config != null ? u.changes(key.config) : u.changes();
        if (has_entries(pending)) {
            if (!module.check_mode) {
                if (key.section != null) {
                    let response = module.run_command([ 'uci', 'revert', key_name(key) ]);
                    if (response.rc != 0)
                        fail(trim(response.stderr), { ...result, ...response });
                    u.unload(key.config);
                } else {
                    cursor_call(u, key.config != null ? u.revert(key.config) : u.revert(),
                                'cannot revert UCI changes', result);
                }
            }
            result.changed = true;
        }
        break;
    }
    case 'changes': {
        result.changes = key.config != null ? u.changes(key.config) : u.changes();
        let command = [ 'uci', 'changes' ];
        if (key.config != null)
            push(command, key.config);
        let response = module.run_command(command);
        if (response.rc != 0)
            fail(trim(response.stderr), { ...result, ...response });
        result.result = response.stdout;
        break;
    }
    case 'export':
    case 'show': {
        let command = [ 'uci', op.command ];
        if (key_name(key) != null)
            push(command, key_name(key));
        let response = module.run_command(command);
        if (response.rc != 0)
            fail(trim(response.stderr), { ...result, ...response });
        result.result = response.stdout;
        break;
    }
    case 'import':
    case 'batch': {
        let state_path = null;
        if (module.check_mode) {
            let temporary = module.run_command([ 'mktemp', '-d' ]);
            if (temporary.rc != 0)
                fail('could not create check-mode UCI state directory', { ...result, ...temporary });
            state_path = trim(temporary.stdout);
        }

        let before = module.run_command([ 'uci', ...(state_path != null ? [ '-P', state_path ] : []), 'changes' ]);
        let command = `printf %s ${shell_quote(op.value)} | uci `;
        if (state_path != null)
            command += `-P ${shell_quote(state_path)} `;
        if (op.command == 'import' && op.merge)
            command += '-m ';
        command += op.command;
        if (key.config != null)
            command += ` ${shell_quote(key.config)}`;
        let response = module.run_command(command);
        let after = module.run_command([ 'uci', ...(state_path != null ? [ '-P', state_path ] : []), 'changes' ]);
        if (state_path != null)
            module.run_command([ 'rm', '-rf', state_path ]);
        if (response.rc != 0)
            fail(trim(response.stderr), { ...result, ...response });

        result.changed = before.stdout != after.stdout;
        if (state_path == null && result.changed && op.autocommit) {
            let commit = [ 'uci', 'commit' ];
            if (key.config != null)
                push(commit, key.config);
            response = module.run_command(commit);
            if (response.rc != 0)
                fail(trim(response.stderr), { ...result, ...response });
        }
        if (state_path == null) {
            if (key.config != null) {
                u.unload(key.config);
            } else {
                for (let config in u.configs() ?? [])
                    u.unload(config);
            }
        }
        break;
    }
    case 'find':
        command_find(u, op, key, result, false);
        break;
    case 'find_all':
        command_find(u, op, key, result, true);
        break;
    case 'section':
    case 'ensure':
        command_ensure(u, op, key, result);
        break;
    case 'absent':
        command_absent(u, op, key, result);
        break;
    }

    let stages_changes = !(op.command in [ 'commit', 'revert', 'changes', 'export', 'show', 'import', 'batch', 'get', 'find', 'find_all' ]);
    let after_section = result.section ?? key.section;
    if (result.changed && stages_changes && key.config != null && after_section != null) {
        let after_state = section_values(u.get_all(key.config, after_section));
        let after_type = u.get(key.config, after_section) ?? before_type;
        add_diff(key.config, after_section, after_type, before_state, after_state, op.redact_keys);
    }
    if (result.changed && stages_changes && !module.check_mode)
        save_changes(u, key.config, result);
    if (result.changed && op.autocommit && !module.check_mode
        && !(op.command in [ 'commit', 'revert', 'import', 'batch' ])) {
        commit_changes(u, key.config, result);
    }

    return result;
}

try {
    let u = cursor();
    if (u == null)
        fail('failed to open UCI cursor');

    if (params.operations != null) {
        output.operations = [];
        for (let raw in params.operations) {
            let result = execute(u, operation(raw));
            push(output.operations, result);
            if (result.changed)
                output.changed = true;
        }
        if (output.changed && !module.check_mode) {
            if (params.autocommit)
                commit_changes(u, null, output);
        }
    } else {
        output = execute(u, operation(params));
    }

    if (length(diffs) > 0)
        output.diff = diffs;
    module.exit_json(output);
} catch (e) {
    fail(`uci error: ${e}`);
}
