// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach, afterEach } from 'utest';
import { ansible_module, capture_exit, reset } from 'utils.ansible_module';

// Raw bytes are built with chr(): a "\xff" escape does not stand for the byte
// on every ucode release.
const BAD = '�';

let module;

// The value of `field` in the result the module prints on exit_json().
function emitted(field, value) {
    let fields = {};
    fields[field] = value;
    return capture_exit(() => module.exit_json(fields)).result[field];
}

function kept(name, text) {
    it(`keeps ${name}`, () => assert.match(text, emitted('out', text)));
}

function replaced(name, text, expected) {
    it(`replaces ${name}`, () => assert.match(expected, emitted('out', text)));
}

describe('AnsibleModule() result output', () => {
    beforeEach(() => {
        module = ansible_module({}, {}).value;
    });

    afterEach(() => reset());

    describe('valid UTF-8', () => {
        kept('ASCII', 'plain text\n');
        kept('two-byte characters', `caf${chr(0xc3, 0xa9)}`);
        kept('three-byte characters', chr(0xe2, 0x82, 0xac));
        kept('four-byte characters', chr(0xf0, 0x9f, 0x98, 0x80));
        kept('a NUL byte', `a${chr(0)}b`);
    });

    describe('invalid UTF-8', () => {
        replaced('a lone high byte', `a${chr(0xff)}b`, `a${BAD}b`);
        replaced('a stray continuation byte', `a${chr(0x80)}b`, `a${BAD}b`);
        replaced('a truncated sequence at the end', `a${chr(0xc3)}`, `a${BAD}`);
        replaced('a lead byte followed by ASCII', `${chr(0xe2, 0x82)}x`, `${BAD}${BAD}x`);
        replaced('an overlong form', chr(0xc0, 0xaf), `${BAD}${BAD}`);
        replaced('a surrogate', chr(0xed, 0xa0, 0x80), `${BAD}${BAD}${BAD}`);
        replaced('a code point above U+10FFFF', chr(0xf4, 0x90, 0x80, 0x80), `${BAD}${BAD}${BAD}${BAD}`);
        replaced('only the invalid bytes', `${chr(0xc3, 0xa9)}${chr(0xff)}${chr(0xc3, 0xa9)}`,
                 `${chr(0xc3, 0xa9)}${BAD}${chr(0xc3, 0xa9)}`);
    });

    it('replaces invalid bytes in nested values and keys', () => {
        let key = `k${chr(0xff)}`;
        let fields = { nested: { list: [ `x${chr(0xfe)}`, 1, true, null ] } };
        fields.nested[key] = 'v';

        let result = capture_exit(() => module.exit_json(fields)).result;
        assert.match([ `x${BAD}`, 1, true, null ], result.nested.list);
        assert.match('v', result.nested[`k${BAD}`]);
    });

    it('replaces invalid bytes in a failure', () => {
        let outcome = capture_exit(() => module.fail_json({ msg: `bad ${chr(0xff)}` }));
        assert.match(1, outcome.rc);
        assert.match(`bad ${BAD}`, outcome.result.msg);
    });
});
