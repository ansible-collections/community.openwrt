// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, xit, assert, afterEach, contains } from 'utest';
import { ansible_module, reset } from 'utils.ansible_module';

function param(spec, value) {
    let outcome = ansible_module({ p: value }, { argument_spec: { p: spec } });
    assert.match(false, outcome.exited, `module exited: ${outcome.result?.msg}`);
    return outcome.value.params.p;
}

function conversion_error(spec, value) {
    let outcome = ansible_module({ p: value }, { argument_spec: { p: spec } });
    assert.match(true, outcome.exited, 'module did not exit');
    assert.match(1, outcome.rc);
    assert.match(contains({ failed: true }), outcome.result);
    return outcome.result.msg;
}

describe('AnsibleModule() type conversion', () => {
    afterEach(() => reset());

    describe('int', () => {
        it('converts a numeric string', () => {
            assert.match(-4, param({ type: 'int' }, '-3'));
        });

        it('truncates a double', () => {
            assert.match(3, param({ type: 'int' }, 3.7));
        });

        it('rejects a non-numeric string', () => {
            assert.match(`argument 'p' is of type str and we were unable to convert to int: "x"`,
                         conversion_error({ type: 'int' }, 'x'));
        });
    });

    describe('bool', () => {
        it('accepts the YAML-style true strings', () => {
            for (let value in [ 'yes', 'on', 'True', '1' ])
                assert.match(true, param({ type: 'bool' }, value), value);
        });

        it('accepts the YAML-style false strings', () => {
            for (let value in [ 'no', 'off', 'False', '0' ])
                assert.match(false, param({ type: 'bool' }, value), value);
        });

        it('rejects an unrecognized string', () => {
            assert.match(`argument 'p' is of type str and we were unable to convert to bool: "maybe"`,
                         conversion_error({ type: 'bool' }, 'maybe'));
        });
    });

    describe('float', () => {
        it('converts an int to a double', () => {
            let value = param({ type: 'float' }, 2);
            assert.match('double', type(value));
            assert.match(2.0, value);
        });

        it('converts decimal strings', () => {
            let cases = { '1.5': 1.5, '1.': 1.0, '.5': 0.5, '-.5': -0.5, '+2': 2.0 };
            for (let text, expected in cases) {
                let value = param({ type: 'float' }, text);
                assert.match('double', type(value), text);
                assert.match(expected, value, text);
            }
        });

        it('rejects a non-numeric string', () => {
            assert.match(`argument 'p' is of type str and we were unable to convert to float: "abc"`,
                         conversion_error({ type: 'float' }, 'abc'));
        });

        // ansible-core converts these with Python's float(); pending the
        // string-to-float rework deferred in #272.
        xit('converts exponent notation', () => {
            assert.match(1000.0, param({ type: 'float' }, '1e3'));
        });

        xit('ignores surrounding whitespace', () => {
            assert.match(1.5, param({ type: 'float' }, ' 1.5 '));
        });
    });

    describe('list', () => {
        it('splits a comma-separated string and trims the items', () => {
            assert.match([ 'a', 'b' ], param({ type: 'list' }, 'a, b'));
        });

        it('converts the elements', () => {
            assert.match([ 1, 2 ], param({ type: 'list', elements: 'int' }, '1,2'));
        });

        it('reports each element that cannot be converted', () => {
            assert.match(`Elements value for option 'p' is of type str and we were unable to convert to int: "x"`,
                         conversion_error({ type: 'list', elements: 'int' }, [ 1, 'x' ]));
        });
    });
});
