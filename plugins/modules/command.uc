// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2021 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { chdir, glob } from 'fs';
import { AnsibleModule, shell_quote } from '_basic';

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

// A timestamp as the module reports it, from a [ seconds, nanoseconds ] pair.
function timestamp(when) {
    let t = localtime(when[0]);
    return sprintf('%04d-%02d-%02d %02d:%02d:%02d.%06d',
                   t.year, t.mon, t.mday, t.hour, t.min, t.sec, when[1] / 1000);
}

// A reading of the monotonic clock, so that the duration stays right even if the
// wall clock is adjusted while the command runs. Falls back to the wall clock on
// systems without a monotonic one.
function monotonic() {
    return clock(true) ?? clock();
}

// The time between two [ seconds, nanoseconds ] readings, as hours, minutes and
// seconds.
function elapsed(from, to) {
    let seconds = to[0] - from[0];
    let usec = (to[1] - from[1]) / 1000;

    if (usec < 0) {
        seconds--;
        usec += 1000000;
    }

    return sprintf('%d:%02d:%02d.%06d', seconds / 3600, seconds % 3600 / 60, seconds % 60, usec);
}

// ---- main -----------------------------------------------------------------

result.update({ cmd: params.cmd, start: '', end: '', delta: '', stdout: '', stderr: '', rc: 0 });

if (params.chdir != null && !chdir(params.chdir))
    module.fail_json(`cd ${params.chdir}: unable to change directory`);

if (params.creates != null && file_exists(params.creates))
    module.exit_json({ stdout: `skipped, since ${params.creates} exists` });

if (params.removes != null && !file_exists(params.removes))
    module.exit_json({ stdout: `skipped, since ${params.removes} does not exist` });

let ts_start = clock();
let mono_start = monotonic();
let res;

if (!params.uses_shell)
    // Split the command into words without letting a shell interpret it, the
    // way `echo ... | xargs sh -c 'exec "$@"' --` does.
    res = module.run_command(`echo ${shell_quote(params.cmd)} | xargs sh -c 'exec "$@"' --`);
else
    res = module.run_command([ params.executable, '-c', params.cmd ]);

let ts_end = clock();
let mono_end = monotonic();

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
