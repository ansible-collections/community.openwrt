// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// Usage: ucode -S -L <module_utils dir> test_basic.uc
// Prints one line per failed check and exits non-zero when any check fails.

import { deep_equal } from '_basic';

let failures = [];
let checks = 0;

function check(name, actual, expected) {
    checks++;
    if (actual !== expected)
        push(failures, sprintf('%s: got %J, expected %J', name, actual, expected));
}

function check_true(name, value) {
    check(name, value, true);
}

function check_false(name, value) {
    check(name, value, false);
}

// scalars
check_true('same strings', deep_equal('a', 'a'));
check_false('different strings', deep_equal('a', 'b'));
check_true('null and null', deep_equal(null, null));
check_false('null and empty string', deep_equal(null, ''));
check_false('string and number', deep_equal('1', 1));
check_true('int and double of same value', deep_equal(1, 1.0));
check_false('int and different double', deep_equal(1, 1.5));
check_true('same bools', deep_equal(true, true));
check_false('bool and int', deep_equal(true, 1));

// arrays compare in order
check_true('same arrays', deep_equal([ 'a', 'b' ], [ 'a', 'b' ]));
check_false('arrays in different order', deep_equal([ 'a', 'b' ], [ 'b', 'a' ]));
check_false('arrays of different length', deep_equal([ 'a' ], [ 'a', 'a' ]));
check_true('empty arrays', deep_equal([], []));
check_false('array and object', deep_equal([], {}));
check_false('array and string', deep_equal([ 'a' ], 'a'));

// objects compare regardless of key order
check_true('same objects', deep_equal({ a: '1', b: '2' }, { a: '1', b: '2' }));
check_true('objects with keys in different order', deep_equal({ a: '1', b: '2' }, { b: '2', a: '1' }));
let readded = { a: '1', b: '2' };
delete readded.a;
readded.a = '1';
check_true('object with a key removed and set again', deep_equal({ a: '1', b: '2' }, readded));
check_false('objects with different values', deep_equal({ a: '1', b: '2' }, { a: '1', b: '3' }));
check_false('object with an extra key', deep_equal({ a: '1' }, { a: '1', b: '2' }));
check_false('object with a missing key', deep_equal({ a: '1', b: '2' }, { a: '1' }));
check_false('same size, different keys', deep_equal({ a: '1' }, { b: '1' }));
check_false('null value and missing key', deep_equal({ a: null }, { b: null }));
check_true('empty objects', deep_equal({}, {}));

// nesting
check_true('nested, keys in different order',
           deep_equal({ x: [ 'a', { p: '1', q: '2' } ], y: 'z' }, { y: 'z', x: [ 'a', { q: '2', p: '1' } ] }));
check_false('nested, differing leaf',
            deep_equal({ x: [ 'a', { p: '1' } ] }, { x: [ 'a', { p: '2' } ] }));

for (let line in failures)
    print(line, '\n');
printf('%d checks, %d failed\n', checks, length(failures));
exit(length(failures) > 0 ? 1 : 0);
