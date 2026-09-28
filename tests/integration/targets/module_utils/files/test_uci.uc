// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// Usage: ucode -S -L <module_utils dir> test_uci.uc <scratch dir>
// Prints one line per failed check and exits non-zero when any check fails.

import { cursor } from 'uci';
import { mkdir, open } from 'fs';
import { deep_equal } from '_basic';
import { normalize_value, section_values, upsert_section } from '_uci';

let failures = [];
let checks = 0;

function check(name, actual, expected) {
    checks++;
    if (!deep_equal(actual, expected))
        push(failures, sprintf('%s: got %J, expected %J', name, actual, expected));
}

function check_true(name, value) {
    check(name, value, true);
}

function check_false(name, value) {
    check(name, value, false);
}

// normalize_value()
check('normalize_value: true', normalize_value(true), '1');
check('normalize_value: false', normalize_value(false), '0');
check('normalize_value: int', normalize_value(42), '42');
check('normalize_value: string', normalize_value('abc'), 'abc');
check('normalize_value: array', normalize_value([ 1, true, 'x' ]), [ '1', '1', 'x' ]);
check('normalize_value: null', normalize_value(null), null);

// section_values()
check('section_values: drops metadata',
      section_values({ '.name': 'main', '.type': 'uhttpd', '.anonymous': false, a: '1' }), { a: '1' });
check('section_values: null section', section_values(null), {});

// upsert_section() against a scratch UCI config
let scratch = ARGV[0];
let confdir = `${scratch}/config`;
let savedir = `${scratch}/delta`;
mkdir(confdir);
mkdir(savedir);
let fd = open(`${confdir}/test`, 'w');
fd.write("config main 'main'\n\toption b '2'\n\toption a '1'\n\tlist l 'x'\n\tlist l 'y'\n");
fd.close();

let u = cursor(confdir, savedir);
let update = upsert_section(u, 'test', 'main', 'main', { a: '1', b: '2', l: [ 'x', 'y' ] }, {});
check_false('upsert_section: same values in different order', update.changed);
update = upsert_section(u, 'test', 'main', 'main', { a: 1, b: 2 }, {});
check_false('upsert_section: numbers equal to stored strings', update.changed);
update = upsert_section(u, 'test', 'main', 'main', { l: [ 'y', 'x' ] }, {});
check_true('upsert_section: reordered list', update.changed);
check('upsert_section: reordered list stored', u.get('test', 'main', 'l'), [ 'y', 'x' ]);
update = upsert_section(u, 'test', 'main', 'main', {}, { b: true });
check_true('upsert_section: dropped option', update.changed);
check('upsert_section: dropped option removed', u.get('test', 'main', 'b'), null);
update = upsert_section(u, 'test', 'main', 'main', {}, { b: true });
check_false('upsert_section: dropping an absent option', update.changed);

for (let line in failures)
    print(line, '\n');
printf('%d checks, %d failed\n', checks, length(failures));
exit(length(failures) > 0 ? 1 : 0);
