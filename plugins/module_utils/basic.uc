// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// basic.uc — ucode counterpart of Ansible's AnsibleModule.
//
// ucode has no classes, so AnsibleModule() is a factory returning an object that
// carries the parsed parameters together with the methods acting on them:
//
//   import { AnsibleModule } from 'basic';
//
//   const module = AnsibleModule({
//           argument_spec: {
//                   name:  { type: 'str', required: true },
//                   state: { type: 'str', default: 'present', choices: [ 'present', 'absent' ] },
//           },
//           supports_check_mode: true,
//   });
//
//   module.exit_json({ changed: false, name: module.params.name });

import { dirname, popen, readfile, readlink, unlink } from 'fs';

const ANSIBLE_PREFIX = '_ansible_';
const COLLECTION_NAME = 'community.openwrt';

// ---- result output --------------------------------------------------------

// Print a result object as JSON and terminate the module, exiting non-zero
// when the result says the module failed. A result without a `failed` status
// is a bug in the caller, and dies loudly rather than assuming success.
function emit(result) {
    if (result.failed == null)
        die('result is missing the "failed" status');

    printf('%J\n', result);
    exit(result.failed ? 1 : 0);
}

// Terminate with a JSON failure. Used for errors detected while the module
// object is still being built, when fail_json() is not available yet.
function abort(msg) {
    emit({ failed: true, changed: false, msg: msg });
}

// Interpret the argument of exit_json()/fail_json(): a dict contributes its
// fields to the result, anything else stands for the message.
function result_fields(extra) {
    if (extra == null)
        return {};

    return type(extra) == 'object' ? { ...extra } : { msg: sprintf('%s', extra) };
}

// ---- argument parsing -----------------------------------------------------

// Read and parse the arguments file whose path Ansible passes as ARGV[0].
function load_args() {
    if (length(ARGV) < 1)
        abort('no argument file provided');

    let raw = readfile(ARGV[0]);
    if (raw == null)
        abort(`cannot read argument file ${ARGV[0]}`);

    let args;
    try {
        args = json(raw);
    } catch (e) {
        args = null;
    }
    if (type(args) != 'object')
        abort(`cannot parse argument file ${ARGV[0]} as JSON`);

    return args;
}

// Convert `value` to the type `want`. Returns { ok: true, value: ... } on
// success, { ok: false } when the value has no representation in that type.
function coerce(value, want) {
    switch (want) {
    case 'raw':
        return { ok: true, value: value };

    case 'str':
        if (type(value) == 'object' || type(value) == 'array')
            return { ok: false };
        return { ok: true, value: sprintf('%s', value) };

    case 'bool':
        switch (type(value)) {
        case 'bool':
            return { ok: true, value: value };
        case 'int':
        case 'double':
            return { ok: true, value: value != 0 };
        case 'string':
            if (value == 'true' || value == 'yes' || value == 'on' || value == '1')
                return { ok: true, value: true };
            if (value == 'false' || value == 'no' || value == 'off' || value == '0')
                return { ok: true, value: false };
        }
        return { ok: false };

    case 'int':
        if (type(value) == 'int')
            return { ok: true, value: value };
        if (type(value) == 'double')
            return { ok: true, value: int(value) };
        if (type(value) == 'string' && match(value, /^[+-]?[0-9]+$/))
            return { ok: true, value: int(value) };
        return { ok: false };

    case 'float':
        if (type(value) == 'int' || type(value) == 'double')
            return { ok: true, value: value + 0.0 };
        if (type(value) == 'string' && match(value, /^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$/))
            return { ok: true, value: value + 0.0 };
        return { ok: false };

    case 'list':
        if (type(value) == 'array')
            return { ok: true, value: value };
        if (type(value) == 'string')
            return { ok: true, value: split(value, ',') };
        return { ok: true, value: [ value ] };

    case 'dict':
        if (type(value) == 'object')
            return { ok: true, value: value };
        if (type(value) == 'string') {
            let parsed;
            try {
                parsed = json(value);
            } catch (e) {
                parsed = null;
            }
            if (type(parsed) == 'object')
                return { ok: true, value: parsed };
        }
        return { ok: false };
    }

    return { ok: false };
}

// Interpret an Ansible-supplied flag (_ansible_check_mode and friends).
function truthy(value) {
    let conv = coerce(value, 'bool');
    return conv.ok ? conv.value : false;
}

// Map every declared alias to the parameter name it stands for.
function alias_map(argument_spec) {
    let aliases = {};
    for (let name in argument_spec) {
        let declared = argument_spec[name].aliases;
        if (declared == null)
            continue;
        for (let i = 0; i < length(declared); i++)
            aliases[declared[i]] = name;
    }
    return aliases;
}

// Return the value supplied for `name`, looking through its aliases.
function supplied_value(args, name, aliases) {
    if (args[name] != null)
        return args[name];
    for (let alias in aliases) {
        if (aliases[alias] == name && args[alias] != null)
            return args[alias];
    }
    return null;
}

// Validate `args` against `argument_spec` and return the parameter map, keyed
// by canonical name. Parameters the caller did not set are present with a null
// value, mirroring AnsibleModule's None. Terminates the module on failure.
function build_params(args, argument_spec) {
    let aliases = alias_map(argument_spec);

    let unsupported = [];
    for (let name in args) {
        if (substr(name, 0, length(ANSIBLE_PREFIX)) == ANSIBLE_PREFIX)
            continue;
        if (argument_spec[name] == null && aliases[name] == null)
            push(unsupported, name);
    }
    if (length(unsupported) > 0)
        abort('Unsupported parameters: ' + join(', ', sort(unsupported)));

    let params = {};
    let missing = [];
    let errors = [];

    for (let name in argument_spec) {
        let spec = argument_spec[name];
        let want = spec.type != null ? spec.type : 'str';
        let value = supplied_value(args, name, aliases);
        if (value == null)
            value = spec.default;

        if (value == null) {
            if (spec.required)
                push(missing, name);
            else
                params[name] = null;
            continue;
        }

        let conv = coerce(value, want);
        if (!conv.ok) {
            push(errors, sprintf('cannot convert %J to %s for parameter %s', value, want, name));
            continue;
        }
        params[name] = conv.value;
    }

    if (length(missing) > 0)
        abort('missing required arguments: ' + join(', ', sort(missing)));

    for (let name in argument_spec) {
        let choices = argument_spec[name].choices;
        if (choices == null || params[name] == null)
            continue;

        let allowed = false;
        for (let i = 0; i < length(choices); i++) {
            if (choices[i] == params[name]) {
                allowed = true;
                break;
            }
        }
        if (!allowed)
            push(errors, sprintf('value of %s must be one of: %s, got: %s',
                                 name, join(', ', choices), params[name]));
    }

    if (length(errors) > 0)
        abort(join('; ', errors));

    return params;
}

function Result() {
    let data = { changed: false, failed: false, msg: '' };

    return {
        // Add or modify several fields at once.
        update: function(fields) {
            for (let key in fields)
                data[key] = fields[key];
        },

        // Mark the result as changed, or pass false to clear the flag.
        changed: function(value) {
            data.changed = value != null ? value : true;
        },

        // Record a deprecation. The version the feature is removed in is
        // mandatory, so that every deprecation carries a removal target.
        deprecate: function(msg, version) {
            if (version == null)
                abort(`deprecation of "${msg}" is missing the removal version`);

            if (type(data.deprecations) != 'array')
                data.deprecations = [];
            push(data.deprecations, {
                msg: msg,
                version: version,
                collection_name: COLLECTION_NAME,
            });
        },

        // Snapshot the accumulated fields for output, with `extra` merged on top.
        render: function(extra) {
            return extra ? { ...data, ...extra } : { ...data };
        },
    };
}

// ---- command execution ----------------------------------------------------

// Quote a value for use as a single shell word.
function shell_quote(value) {
    return `'${replace(sprintf('%s', value), /'/g, "'\\''")}'`;
}

// Render the command line. An array is quoted element by element, so that no
// argument is ever interpreted by the shell; a string is handed to the shell
// as it stands, the equivalent of run_command(use_unsafe_shell=True).
function command_line(args) {
    if (type(args) == 'array')
        return join(' ', map(args, shell_quote));
    return sprintf('%s', args);
}

// ucode has no getpid(); Linux exposes the process id through /proc/self.
function process_id() {
    let pid = readlink('/proc/self');
    return pid != null ? pid : 'unknown';
}

let stderr_seq = 0;

// popen() exposes a single stream, so a command's stderr is redirected into a
// file inside the module's own temporary directory - the one holding the
// arguments file ucode was started with. That directory belongs to the task,
// but nothing guarantees the module is alone in it: runs against the same host
// can overlap. The name is therefore unique per process (the process id), per
// moment (a nanosecond timestamp) and per call (a counter), so that concurrent
// commands never read each other's stderr. math.rand() is deliberately not
// used: it lives in a separate ucode module and seeds itself from the clock
// with millisecond resolution, so processes starting together share its
// sequence.
function stderr_file() {
    let now = clock(true);
    stderr_seq++;

    return sprintf('%s/.ansible_stderr.%s.%d.%d.%d', dirname(ARGV[0]),
                   process_id(), now[0], now[1], stderr_seq);
}

// ---- module object --------------------------------------------------------

// Build the module object. Recognized options:
//   argument_spec        parameter definitions (type, required, default, choices)
//   supports_check_mode  whether the module honours check mode (default false)
export function AnsibleModule(opts) {
    if (opts == null)
        opts = {};

    let args = load_args();
    let params = build_params(args, opts.argument_spec != null ? opts.argument_spec : {});
    let check_mode = truthy(args._ansible_check_mode);
    let result = Result();

    if (check_mode && !opts.supports_check_mode)
        emit({ changed: false, failed: false, skipped: true,
               msg: 'remote module does not support check mode' });

    // Print the accumulated result and exit. Takes a dict of fields to merge
    // on top of it, or a message.
    let exit_json = function(extra) {
        emit(result.render(result_fields(extra)));
    };

    // Print a failed result and exit. Takes a dict of fields or a message.
    let fail_json = function(extra) {
        let fields = result_fields(extra);
        fields.failed = true;
        emit(result.render(fields));
    };

    // Run a command and return { rc, stdout, stderr }, the counterpart of
    // AnsibleModule.run_command(). `args` is an array of arguments (each one
    // quoted, so the shell cannot reinterpret it) or a shell command line.
    // Recognized options:
    //   check_rc  end the module in failure when the command exits non-zero
    let run_command = function(args, options) {
        if (options == null)
            options = {};

        let cmd = command_line(args);
        let errfile = stderr_file();

        let proc = popen(`${cmd} 2>${shell_quote(errfile)}`, 'r');
        if (proc == null)
            fail_json(`cannot execute command: ${cmd}`);

        let stdout = proc.read('all');
        let rc = proc.close();
        let stderr = readfile(errfile);
        unlink(errfile);

        let outcome = {
            rc: rc,
            stdout: stdout != null ? stdout : '',
            stderr: stderr != null ? stderr : '',
        };

        if (options.check_rc && rc != 0) {
            let msg = rtrim(outcome.stderr);
            fail_json({
                msg: msg != '' ? msg : `command failed with rc=${rc}: ${cmd}`,
                cmd: args,
                rc: rc,
                stdout: outcome.stdout,
                stderr: outcome.stderr,
            });
        }

        return outcome;
    };

    return {
        params: params,
        check_mode: check_mode,
        diff_mode: truthy(args._ansible_diff),
        result: result,

        // Record a deprecation, reported by ansible-core once the module ends.
        deprecate: function(msg, version) {
            result.deprecate(msg, version);
        },

        exit_json: exit_json,
        fail_json: fail_json,
        run_command: run_command,
    };
};
