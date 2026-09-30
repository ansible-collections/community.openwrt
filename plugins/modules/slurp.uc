// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2017 Markus Weippert
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { access, error, readfile, stat } from 'fs';
import { AnsibleModule } from '_basic';

const module = AnsibleModule({
    argument_spec: {
        src: { type: 'str', required: true, aliases: [ 'path' ] },
    },
    supports_check_mode: true,
});

const src = module.params.src;

if (stat(src) == null)
    module.fail_json(`file not found: ${src}`);
if (!access(src, 'r'))
    module.fail_json(`file not readable: ${src}`);

let data = readfile(src);
if (data == null)
    module.fail_json(`cannot read ${src}: ${error()}`);

// The encoded content is broken into lines of 76 characters, as base64(1) does.
let encoded = b64enc(data);
let lines = [];
for (let i = 0; i < length(encoded); i += 76)
    push(lines, substr(encoded, i, 76));

module.exit_json({ source: src, content: join('\n', lines), encoding: 'base64' });
