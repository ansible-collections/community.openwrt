// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2021 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { chdir, glob } from 'fs';
import { AnsibleModule, monotonic, shell_quote, Time } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        cmd:        { type: 'str', required: true, aliases: [ 'raw_params', '_raw_params' ] },
        uses_shell: { type: 'bool', default: false, aliases: [ '_uses_shell' ] },
        chdir:      { type: 'str' },
        executable: { type: 'str', default: '/bin/sh' },
        creates:    { type: 'str' },
        removes:    { type: 'str' },
    },
});

const params = module.params;
const result = module.result;

// Whether a filename or glob pattern matches anything.
function file_exists(pattern) {
    let matches = glob(pattern);
    return matches != null && length(matches) > 0;
}

// A timestamp as the module reports it, from a Time.
function timestamp(when) {
    let t = localtime(when.epoch());
    return sprintf('%04d-%02d-%02d %02d:%02d:%02d.%06d',
                   t.year, t.mon, t.mday, t.hour, t.min, t.sec, when.usec());
}

// The time between two Time readings, as hours, minutes and seconds.
function elapsed(start_time, end_time) {
    let delta = end_time.minus(start_time);

    return sprintf('%d:%02d:%02d.%06d', delta.hours(), delta.minutes(), delta.seconds(), delta.usec());
}

// ---- main -----------------------------------------------------------------

result.update({ cmd: params.cmd, start: '', end: '', delta: '', stdout: '', stderr: '' });

if (params.chdir != null && !chdir(params.chdir))
    module.fail_json(`cd ${params.chdir}: unable to change directory`);

if (params.creates != null && file_exists(params.creates))
    module.exit_json({ stdout: `skipped, since ${params.creates} exists` });

if (params.removes != null && !file_exists(params.removes))
    module.exit_json({ stdout: `skipped, since ${params.removes} does not exist` });

let command_args;

if (!params.uses_shell) {
    // Let xargs split the arguments, but execute them separately so that its
    // status codes do not replace the command's own exit status.
    let parsed = module.run_command(`printf '%s\\n' ${shell_quote(params.cmd)} | xargs -r printf '%s\\0'`);
    if (parsed.rc != 0)
        module.fail_json(`Unable to parse command arguments: ${rtrim(parsed.stderr, '\n')}`);

    let argv = split(parsed.stdout, chr(0));
    pop(argv); // Drop the empty field after the final NUL separator.
    if (length(argv) == 0)
        module.fail_json('Command is empty');

    command_args = [ 'exec', ...argv ];
}
else
    command_args = [ params.executable, '-c', params.cmd ];

let ts_start = Time(...clock());
let mono_start = Time(...monotonic());
let res = module.run_command(command_args);

let ts_end = Time(...clock());
let mono_end = Time(...monotonic());

result.update({
    start: timestamp(ts_start),
    end: timestamp(ts_end),
    delta: elapsed(mono_start, mono_end),
    // Trailing newlines are dropped, the way the command output was captured
    // through a shell substitution before.
    stdout: rtrim(res.stdout, '\n'),
    stderr: rtrim(res.stderr, '\n'),
    rc: res.rc,
});
result.changed();

if (res.rc != 0)
    module.fail_json('non-zero return code');

module.exit_json();
