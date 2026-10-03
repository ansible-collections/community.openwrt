// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach, afterEach, mock, contains, regex } from 'utest';
import { ansible_module, capture_exit, reset } from 'utils.ansible_module';

let module;
let commands = [];
let removed = [];

// Replace the command runner: popen() answers with `outcome`, and the file
// run_command() redirects stderr into reads back as outcome.stderr.
function fake_command(outcome) {
    mock.global.patch('fs', { behavior: {
        popen: (cmd, mode) => {
            push(commands, cmd);
            return outcome.no_process ? null : {
                read: () => outcome.stdout ?? '',
                close: () => outcome.rc ?? 0,
            };
        },
        readfile: (path) => outcome.stderr ?? '',
        unlink: (path) => { push(removed, path); return true; },
    } });
}

describe('AnsibleModule().run_command()', () => {
    beforeEach(() => {
        commands = [];
        removed = [];
        module = ansible_module({}, {}).value;
    });

    afterEach(() => reset());

    it('returns rc, stdout and stderr', () => {
        fake_command({ rc: 3, stdout: 'out\n', stderr: 'err\n' });
        assert.match({ rc: 3, stdout: 'out\n', stderr: 'err\n' }, module.run_command('true'));
    });

    it('quotes each item of an argument list', () => {
        fake_command({});
        module.run_command([ 'echo', 'a b', "it's" ]);
        assert.match(regex(/^'echo' 'a b' 'it'\\''s' 2>/), commands[0]);
    });

    it('passes a command line to the shell as is', () => {
        fake_command({});
        module.run_command('echo $HOME | wc -c');
        assert.match(regex(/^echo \$HOME \| wc -c 2>/), commands[0]);
    });

    it('collects stderr through a file next to the arguments file and removes it', () => {
        fake_command({});
        module.run_command('true');
        assert.match(1, length(removed));
        assert.match(regex(/^\/tmp\/ansible-module\/\.ansible_stderr\./), removed[0]);
        assert.match(`true 2>'${removed[0]}'`, commands[0]);
    });

    it('fails the module on a non-zero rc with check_rc, reporting stderr', () => {
        fake_command({ rc: 2, stdout: 'partial', stderr: 'boom\n' });
        let outcome = capture_exit(() => module.run_command([ 'false' ], { check_rc: true }));
        assert.match(1, outcome.rc);
        assert.match(contains({ failed: true, msg: 'boom', rc: 2, stdout: 'partial', cmd: [ 'false' ] }),
                     outcome.result);
    });

    it('fails the module with a generic message when stderr is empty', () => {
        fake_command({ rc: 2 });
        let outcome = capture_exit(() => module.run_command('false', { check_rc: true }));
        assert.match(contains({ failed: true, msg: 'command failed with rc=2: false' }), outcome.result);
    });

    it('fails the module when the command cannot be started', () => {
        fake_command({ no_process: true });
        let outcome = capture_exit(() => module.run_command('true'));
        assert.match(contains({ failed: true, msg: 'cannot execute command: true' }), outcome.result);
    });
});
