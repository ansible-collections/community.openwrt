// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert } from 'utest';
import { deep_equal } from '_basic';

function equal(name, left, right) {
    it(`equal: ${name}`, () => assert.match(true, deep_equal(left, right)));
}

function not_equal(name, left, right) {
    it(`not equal: ${name}`, () => assert.match(false, deep_equal(left, right)));
}

describe('deep_equal()', () => {
    describe('scalars', () => {
        equal('same strings', 'a', 'a');
        not_equal('different strings', 'a', 'b');
        equal('null and null', null, null);
        not_equal('null and empty string', null, '');
        not_equal('string and number', '1', 1);
        equal('int and double of same value', 1, 1.0);
        not_equal('int and different double', 1, 1.5);
        equal('same bools', true, true);
        not_equal('bool and int', true, 1);
    });

    describe('arrays compare in order', () => {
        equal('same arrays', [ 'a', 'b' ], [ 'a', 'b' ]);
        not_equal('arrays in different order', [ 'a', 'b' ], [ 'b', 'a' ]);
        not_equal('arrays of different length', [ 'a' ], [ 'a', 'a' ]);
        equal('empty arrays', [], []);
        not_equal('array and object', [], {});
        not_equal('array and string', [ 'a' ], 'a');
    });

    describe('objects compare regardless of key order', () => {
        equal('same objects', { a: '1', b: '2' }, { a: '1', b: '2' });
        equal('objects with keys in different order', { a: '1', b: '2' }, { b: '2', a: '1' });

        let readded = { a: '1', b: '2' };
        delete readded.a;
        readded.a = '1';
        equal('object with a key removed and set again', { a: '1', b: '2' }, readded);

        not_equal('objects with different values', { a: '1', b: '2' }, { a: '1', b: '3' });
        not_equal('object with an extra key', { a: '1' }, { a: '1', b: '2' });
        not_equal('object with a missing key', { a: '1', b: '2' }, { a: '1' });
        not_equal('same size, different keys', { a: '1' }, { b: '1' });
        not_equal('null value and missing key', { a: null }, { b: null });
        equal('empty objects', {}, {});
    });

    describe('nesting', () => {
        equal('nested, keys in different order',
              { x: [ 'a', { p: '1', q: '2' } ], y: 'z' }, { y: 'z', x: [ 'a', { q: '2', p: '1' } ] });
        not_equal('nested, differing leaf',
                  { x: [ 'a', { p: '1' } ] }, { x: [ 'a', { p: '2' } ] });
    });
});
