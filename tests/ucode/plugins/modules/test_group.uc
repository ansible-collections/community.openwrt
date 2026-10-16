// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert } from 'utest';
import { module_internals } from 'utils.ansible_module';

const to_id = module_internals('../../plugins/modules/group.uc').to_id;

describe('group: to_id()', () => {
    it('reads digits as an ID', () => assert.match(1000, to_id('1000')));
    it('reads leading zeros as decimal', () => assert.match(7, to_id('007')));
    it('reads an empty field as 0', () => assert.match(0, to_id('')));

    it('rejects anything but digits', () => {
        for (let value in [ '-1', '+1', '1a', ' 1', '1 ', '1.5', 'x' ])
            assert.match(null, to_id(value), value);
    });
});
