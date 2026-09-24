// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        data: { type: 'raw' },
    },
});

const params = module.params;

// The special value makes the module crash, without a result to report.
if (params.data == 'crash')
    die('boom');

let result = { ping: 'pong' };
if (params.data != null)
    result.data = params.data;

module.exit_json(result);
