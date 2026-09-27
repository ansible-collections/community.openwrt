// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { stat } from 'fs';
import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        name:    { type: 'str', required: true },
        state:   { type: 'str', choices: [ 'reloaded', 'restarted', 'started', 'stopped' ] },
        enabled: { type: 'bool' },
        pattern: { type: 'str' },
    },
    supports_check_mode: true,
});

const params = module.params;
const result = module.result;
const init_script = `/etc/init.d/${params.name}`;

function succeeds(args) {
    return module.run_command(args).rc == 0;
}

// Both output streams, as a message reports them.
function output_of(res) {
    return trim(res.stdout + res.stderr);
}

function is_running() {
    if (params.pattern)
        return succeeds([ 'pgrep', '-f', params.pattern ]);
    return succeeds([ init_script, 'running' ]);
}

function is_enabled() {
    return succeeds([ init_script, 'enabled' ]);
}

function set_enabled() {
    let status = is_enabled();

    if (status != params.enabled) {
        result.changed();

        if (!module.check_mode) {
            let action = params.enabled ? 'enable' : 'disable';
            let res = module.run_command([ init_script, action ]);
            status = is_enabled();
            if (status != params.enabled)
                module.fail_json(`Unable to ${action} service ${params.name}: ${output_of(res)}`);
        }
    }

    // In check mode, this is still the state the service was found in.
    result.update({ enabled: status ? 'yes' : 'no' });
}

function set_state() {
    let action = null;

    switch (params.state) {
    case 'started':
        if (!is_running())
            action = 'start';
        break;
    case 'stopped':
        if (is_running())
            action = 'stop';
        break;
    case 'restarted':
        action = 'restart';
        break;
    case 'reloaded':
        action = 'reload';
        break;
    }

    if (action == null)
        return;

    result.changed();

    if (!module.check_mode) {
        let res = module.run_command([ init_script, action ]);
        if (res.rc != 0)
            module.fail_json(`Unable to ${action} service ${params.name}: ${output_of(res)}`);
    }
}

// ---- main -----------------------------------------------------------------

let info = stat(init_script);
if (info == null || info.type != 'file')
    module.fail_json(`service ${params.name} does not exist`);

result.update({ name: params.name });
if (params.state != null)
    result.update({ state: params.state });

if (params.enabled != null)
    set_enabled();
if (params.state != null)
    set_state();

module.exit_json();
