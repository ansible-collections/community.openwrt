// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// Helpers to run _basic.uc's AnsibleModule() inside a utest worker.
//
// A module reads its arguments from the file named by ARGV[0] and ends the
// process through exit(). In a worker, ARGV belongs to utest and exit() would
// kill the worker, so both are replaced: the arguments file is served by the
// fs mock, and exit() is turned into an exception carrying the printed result.

import { mock } from 'utest';
import { readfile } from 'fs';
import { AnsibleModule } from '_basic';

export const ARGS_FILE = '/tmp/ansible-module/args.json';

// Call fn(). Returns { exited: false, value } when it returns, or
// { exited: true, rc, result } when it ends the module through exit().
export function capture_exit(fn) {
    let printed = [];
    let rc = null;
    let value;

    try {
        mock.inject_builtin('printf', (fmt, ...args) => push(printed, sprintf(fmt, ...args)), () => {
            mock.inject_builtin('exit', (code) => { rc = code; die('module exited'); }, () => {
                value = fn();
            });
        });
    } catch (e) {
        if (rc == null)
            die(e);
    }

    if (rc == null)
        return { exited: false, value: value };

    return { exited: true, rc: rc, result: json(trim(join('', printed))) };
};

// Build a module from `args`, as ucode_wrapper.sh would. ARGV stays patched
// afterwards, since the module keeps using it; call reset() in afterEach.
export function ansible_module(args, opts) {
    let data = {};
    data[ARGS_FILE] = sprintf('%J', args);

    mock.global.patch_builtin('ARGV', [ ARGS_FILE ]);
    mock.global.patch('fs', { data: data });
    let outcome = capture_exit(() => AnsibleModule(opts));
    mock.global.unpatch('fs');

    return outcome;
};

export function reset() {
    mock.global.unpatch_builtin('ARGV');
};

// Get hold of the functions private to the module at `path`, as an object
// keyed by function name. A module's top-level functions are local to it, and
// only exist once execution has passed their definition. So the module is
// compiled with `return { <every top-level function> };` inserted right before
// its `// MAIN` marker line, and run that far, with AnsibleModule() mocked out
// so that nothing of _basic runs. Errors raised by the module's preamble are
// ignored.
export function module_internals(path) {
    let source = readfile(path);
    if (source == null)
        die(`cannot read module ${path}`);

    let lines = split(source, '\n');
    let names = [];
    let insert_at = null;
    for (let i = 0; i < length(lines) && insert_at == null; i++) {
        let found = match(lines[i], /^function ([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(/);
        if (found)
            push(names, found[1]);
        else if (match(lines[i], /\/\/ +MAIN( .*)?$/))
            insert_at = i;
    }
    if (insert_at == null)
        die(`module ${path} has no '// MAIN' marker line`);
    splice(lines, insert_at, 0, `return { ${join(', ', names)} };`);
    let main = loadstring(join('\n', lines));

    let internals = null;
    let error = null;

    mock.global.patch('_basic', { behavior: { AnsibleModule: () => ({ params: {}, result: {} }) } });
    try {
        internals = main();
    } catch (e) {
        error = e;
    }
    mock.global.unpatch('_basic');

    if (internals == null)
        die(`module ${path} stopped before its functions were defined: ${error?.message}`);

    return internals;
};
