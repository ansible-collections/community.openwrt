// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2026 Ilya Bogdanov
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        path:   { type: 'str' },
        prefix: { type: 'str', default: 'ansible' },
        state:  { type: 'str', default: 'file' },
    },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;

if (!(params.state in [ 'file', 'directory' ]))
    module.fail_json('unknown state option');

let cmd = [ 'mktemp' ];
if (params.state == 'directory')
    push(cmd, '-d');
push(cmd, '-p', params.path ? params.path : '/tmp');
if (module.check_mode)
    push(cmd, '-u');
if (params.prefix)
    push(cmd, `${params.prefix}.XXXXXX`);

let res = module.run_command(cmd);
let path = trim(res.stdout, '\n');
if (path == '')
    module.fail_json(trim(res.stderr, '\n'));

result.update({ path: path });
result.changed();
module.exit_json();
