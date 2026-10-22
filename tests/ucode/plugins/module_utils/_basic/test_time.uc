// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert } from 'utest';
import { Time } from '_basic';

function rejects(name, epoch, nsec, msg) {
    it(`rejects ${name}`, () => assert.throws(() => Time(epoch, nsec), msg));
}

function hms(epoch, hours, minutes, seconds) {
    it(`splits ${epoch}s into ${hours}h ${minutes}m ${seconds}s`, () => {
        let t = Time(epoch, 0);
        assert.match([ hours, minutes, seconds ], [ t.hours(), t.minutes(), t.seconds() ]);
    });
}

describe('Time()', () => {
    describe('accessors', () => {
        it('returns the epoch and nsec it was built with', () => {
            let t = Time(100, 200000000);
            assert.match(100, t.epoch());
            assert.match(200000000, t.nsec());
        });

        it('returns nsec as microseconds, truncated', () => {
            assert.match(200000, Time(100, 200000999).usec());
        });

        it('returns zero microseconds below one microsecond', () => {
            assert.match(0, Time(100, 999).usec());
        });

        it('returns the time as a double', () => {
            assert.match(100.2, Time(100, 200000000).time());
        });

        it('accepts the zero time', () => {
            assert.match(0.0, Time(0, 0).time());
        });

        it('accepts the largest nsec', () => {
            assert.match(1.999999999, Time(1, 999999999).time());
        });
    });

    describe('hours(), minutes(), seconds()', () => {
        hms(0, 0, 0, 0);
        hms(59, 0, 0, 59);
        hms(60, 0, 1, 0);
        hms(3599, 0, 59, 59);
        hms(3600, 1, 0, 0);
        hms(5430, 1, 30, 30);
        hms(86400, 24, 0, 0);

        it('ignores nsec', () => {
            let t = Time(59, 999999999);
            assert.match([ 0, 0, 59 ], [ t.hours(), t.minutes(), t.seconds() ]);
        });
    });

    describe('minus()', () => {
        it('subtracts without a borrow', () => {
            let d = Time(50, 700000000).minus(Time(10, 100000000));
            assert.match([ 40, 600000000 ], [ d.epoch(), d.nsec() ]);
        });

        it('borrows a second when nsec goes negative', () => {
            let d = Time(100, 200000000).minus(Time(50, 700000000));
            assert.match([ 49, 500000000 ], [ d.epoch(), d.nsec() ]);
        });

        it('borrows down to a single nanosecond', () => {
            let d = Time(5, 0).minus(Time(4, 999999999));
            assert.match([ 0, 1 ], [ d.epoch(), d.nsec() ]);
        });

        it('yields zero for equal times', () => {
            let d = Time(42, 123).minus(Time(42, 123));
            assert.match([ 0, 0 ], [ d.epoch(), d.nsec() ]);
        });

        it('returns a Time that can be subtracted from again', () => {
            let d = Time(10, 0).minus(Time(3, 0)).minus(Time(2, 500000000));
            assert.match([ 4, 500000000 ], [ d.epoch(), d.nsec() ]);
        });

        it('leaves its operands unchanged', () => {
            let a = Time(100, 200000000), b = Time(50, 700000000);
            a.minus(b);
            assert.match([ 100, 200000000, 50, 700000000 ], [ a.epoch(), a.nsec(), b.epoch(), b.nsec() ]);
        });

        it('rejects subtracting a later time', () => {
            assert.throws(() => Time(50, 700000000).minus(Time(100, 200000000)), 'expects epoch >= 0');
        });
    });

    describe('validation', () => {
        rejects('a double epoch', 1.5, 0, 'expects integer epoch and nsec');
        rejects('a double epoch with an integral value', 1.0, 0, 'expects integer epoch and nsec');
        rejects('a double nsec', 1, 0.5, 'expects integer epoch and nsec');
        rejects('a string epoch', '1', 0, 'expects integer epoch and nsec');
        rejects('a null epoch', null, 0, 'expects integer epoch and nsec');
        rejects('a missing nsec', 1, null, 'expects integer epoch and nsec');
        rejects('a negative epoch', -1, 0, 'expects epoch >= 0');
        rejects('a negative nsec', 1, -1, 'expects 0 <= nsec < 1000000000');
        rejects('nsec of one full second', 1, 1000000000, 'expects 0 <= nsec < 1000000000');
        rejects('a bad type before a bad range', -1, 0.5, 'expects integer epoch and nsec');
    });
});
