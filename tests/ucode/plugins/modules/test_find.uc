// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach } from 'utest';
import { module_internals } from 'utils.ansible_module';

const MODULE = '../../plugins/modules/find.uc';

const AGE_UNITS = { s: 1, m: 60, h: 3600, d: 86400, w: 604800 };
const SIZE_UNITS = { b: 1, k: 1024, m: 1048576 };

let params;
let fn;

beforeEach(() => {
    params = { hidden: false, exact_mode: true };
    fn = module_internals(MODULE, {
        params: params,
        check_mode: false,
        diff_mode: false,
        fail_json: (result) => die(type(result) == 'object' ? result.msg : result),
    });
});

function globbed(glob, name) {
    return match(name, regexp(fn.glob_to_regex(glob))) != null;
}

describe('find: glob_to_regex()', () => {
    it('matches any run of characters with *', () => {
        assert.match(true, globbed('*.txt', 'a.txt'));
        assert.match(true, globbed('*.txt', '.txt'));
        assert.match(false, globbed('*.txt', 'a.txt.bak'));
    });

    it('matches one character with ?', () => {
        assert.match(true, globbed('a?c', 'abc'));
        assert.match(false, globbed('a?c', 'ac'));
    });

    it('takes regex metacharacters literally', () => {
        assert.match(true, globbed('a.b+(c)', 'a.b+(c)'));
        assert.match(false, globbed('a.b', 'axb'));
    });

    it('supports bracket expressions and their negation', () => {
        assert.match(true, globbed('[ab]x', 'bx'));
        assert.match(false, globbed('[ab]x', 'cx'));
        assert.match(true, globbed('[!ab]x', 'cx'));
        assert.match(false, globbed('[!ab]x', 'ax'));
    });

    it('takes an unclosed [ literally', () => {
        assert.match(true, globbed('a[b', 'a[b'));
    });
});

describe('find: compile_patterns()', () => {
    it('anchors regular expressions at both ends', () => {
        let res = fn.compile_patterns([ 'b.*' ], true);
        assert.match(true, fn.matches_any('bcd', res));
        assert.match(false, fn.matches_any('abcd', res));
    });

    it('fails on an invalid regular expression', () => {
        let msg = null;
        try {
            fn.compile_patterns([ '(' ], true);
        } catch (e) {
            msg = e.message;
        }
        assert.match(true, index(msg, "invalid pattern '('") >= 0);
    });
});

describe('find: parse_amount()', () => {
    it('applies the default unit to unqualified values', () => {
        assert.match(3600, fn.parse_amount('3600', AGE_UNITS, 's'));
        assert.match(100, fn.parse_amount('100', SIZE_UNITS, 'b'));
    });

    it('applies units, ignoring case', () => {
        assert.match(2 * 86400, fn.parse_amount('2d', AGE_UNITS, 's'));
        assert.match(1048576, fn.parse_amount('1M', SIZE_UNITS, 'b'));
    });

    it('keeps the sign', () => {
        assert.match(-604800, fn.parse_amount('-1w', AGE_UNITS, 's'));
    });

    it('rejects what it cannot read', () => {
        assert.match(null, fn.parse_amount('lots', SIZE_UNITS, 'b'));
        assert.match(null, fn.parse_amount('1x', SIZE_UNITS, 'b'));
        assert.match(null, fn.parse_amount('1.5k', SIZE_UNITS, 'b'));
    });
});

describe('find: parse_mode()', () => {
    it('reads octal modes', () => {
        assert.match(420, fn.parse_mode('0644'));
        assert.match(493, fn.parse_mode('755'));
        assert.match(2541, fn.parse_mode('4755'));
    });

    it('rejects symbolic and non-octal modes', () => {
        assert.match(null, fn.parse_mode('u=rw'));
        assert.match(null, fn.parse_mode('0688'));
    });
});

describe('find: within()', () => {
    it('selects at least a positive limit', () => {
        assert.match(true, fn.within(10, 10));
        assert.match(false, fn.within(9, 10));
    });

    it('selects at most a negative limit', () => {
        assert.match(true, fn.within(10, -10));
        assert.match(false, fn.within(11, -10));
    });
});

describe('find: selected()', () => {
    function crit(extra) {
        return { patterns: [], excludes: [], type: null, stamp: 'mtime', now: 1000,
                 age: null, size: null, mode: null, ...(extra ?? {}) };
    }
    const FILE = { type: 'file', size: 50, mode: 420, mtime: 900 };

    it('skips hidden names unless asked for them', () => {
        assert.match(false, fn.selected('.x', FILE, crit()));
        params.hidden = true;
        assert.match(true, fn.selected('.x', FILE, crit()));
    });

    it('selects on type', () => {
        assert.match(true, fn.selected('x', FILE, crit({ type: 'file' })));
        assert.match(false, fn.selected('x', FILE, crit({ type: 'directory' })));
    });

    it('applies excludes after patterns', () => {
        let c = crit({ patterns: fn.compile_patterns([ '*' ], false),
                       excludes: fn.compile_patterns([ 'x*' ], false) });
        assert.match(false, fn.selected('xy', FILE, c));
        assert.match(true, fn.selected('yx', FILE, c));
    });

    it('selects on age', () => {
        assert.match(true, fn.selected('x', FILE, crit({ age: 100 })));
        assert.match(false, fn.selected('x', FILE, crit({ age: 101 })));
        assert.match(true, fn.selected('x', FILE, crit({ age: -100 })));
    });

    it('selects on size only for regular files', () => {
        assert.match(false, fn.selected('x', FILE, crit({ size: 51 })));
        assert.match(true, fn.selected('x', { ...FILE, type: 'directory' }, crit({ size: 51 })));
    });

    it('selects on exact or minimum mode', () => {
        assert.match(false, fn.selected('x', FILE, crit({ mode: 256 })));
        params.exact_mode = false;
        assert.match(true, fn.selected('x', FILE, crit({ mode: 256 })));
        assert.match(false, fn.selected('x', FILE, crit({ mode: 493 })));
    });
});
