// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        command: { type: 'str', required: true, aliases: [ 'cmd' ] },
        delay:   { type: 'int', default: 0 },
    },
});

const params = module.params;
const result = module.result;

let cmd = [ '/sbin/start-stop-daemon', '-Sbqp', '/dev/null', '-x', '/bin/sh', '--', '-c',
            `sleep ${params.delay}; ${params.command}` ];

let res = module.run_command(cmd);
if (res.rc != 0)
    module.fail_json(`${join(' ', cmd)}: ${rtrim(res.stdout + res.stderr, '\n')}`);

result.changed();
module.exit_json();
