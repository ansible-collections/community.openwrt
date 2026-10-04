// Copyright (c) 2026, Alexei Znamensky (@russoz)
// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach } from 'utest';
import { cursor } from 'uci';
import { mkdir, writefile } from 'fs';
import { normalize_value, redact, section_values, upsert_section } from '_uci';

const SCRATCH = '/tmp/test_uci';
const CONFDIR = `${SCRATCH}/config`;
const SAVEDIR = `${SCRATCH}/delta`;

describe('normalize_value()', () => {
    it('turns true into "1"', () => assert.match('1', normalize_value(true)));
    it('turns false into "0"', () => assert.match('0', normalize_value(false)));
    it('turns an int into a string', () => assert.match('42', normalize_value(42)));
    it('keeps a string', () => assert.match('abc', normalize_value('abc')));
    it('normalizes each item of an array', () => assert.match([ '1', '1', 'x' ], normalize_value([ 1, true, 'x' ])));
    it('keeps null', () => assert.match(null, normalize_value(null)));
});

describe('section_values()', () => {
    it('drops metadata', () => {
        assert.match({ a: '1' }, section_values({ '.name': 'main', '.type': 'uhttpd', '.anonymous': false, a: '1' }));
    });

    it('turns a null section into an empty object', () => assert.match({}, section_values(null)));
});

describe('redact()', () => {
    it('marks an unchanged value as REDACTED, even when key order differs', () => {
        let safe = redact({ key: 'secret', other: 'x' }, { other: 'x', key: 'secret' }, [ 'key' ]);
        assert.match({ key: 'REDACTED', other: 'x' }, safe.before);
        assert.match({ key: 'REDACTED', other: 'x' }, safe.after);
    });

    it('marks a changed value as present before and wanted after', () => {
        let safe = redact({ key: 'old' }, { key: 'new' }, [ 'key' ]);
        assert.match({ key: 'REDACTED-present' }, safe.before);
        assert.match({ key: 'REDACTED-wanted' }, safe.after);
    });

    it('marks an unchanged list as REDACTED', () => {
        let safe = redact({ list: [ 'a', 'b' ] }, { list: [ 'a', 'b' ] }, [ 'list' ]);
        assert.match({ list: 'REDACTED' }, safe.after);
    });
});

describe('upsert_section()', () => {
    let u;

    beforeEach(() => {
        mkdir(SCRATCH);
        mkdir(CONFDIR);
        mkdir(SAVEDIR);
        writefile(`${CONFDIR}/test`, "config main 'main'\n\toption b '2'\n\toption a '1'\n\tlist l 'x'\n\tlist l 'y'\n");
        u = cursor(CONFDIR, SAVEDIR);
    });

    it('reports no change for the same values in a different order', () => {
        let update = upsert_section(u, 'test', 'main', 'main', { a: '1', b: '2', l: [ 'x', 'y' ] }, {});
        assert.match(false, update.changed);
    });

    it('reports no change for numbers equal to the stored strings', () => {
        let update = upsert_section(u, 'test', 'main', 'main', { a: 1, b: 2 }, {});
        assert.match(false, update.changed);
    });

    it('stores a reordered list', () => {
        let update = upsert_section(u, 'test', 'main', 'main', { l: [ 'y', 'x' ] }, {});
        assert.match(true, update.changed);
        assert.match([ 'y', 'x' ], u.get('test', 'main', 'l'));
    });

    it('removes a dropped option', () => {
        let update = upsert_section(u, 'test', 'main', 'main', {}, { b: true });
        assert.match(true, update.changed);
        assert.match(null, u.get('test', 'main', 'b'));
    });

    it('reports no change when dropping an absent option', () => {
        let update = upsert_section(u, 'test', 'main', 'main', {}, { c: true });
        assert.match(false, update.changed);
    });
});
