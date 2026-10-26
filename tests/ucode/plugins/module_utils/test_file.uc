// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert, beforeEach } from 'utest';
import { chmod, chown, lsdir, mkdir, readfile, rmdir, stat, unlink, writefile } from 'fs';
import { replace_file } from '_file';

const SCRATCH = '/tmp/test_file';
const TARGET = `${SCRATCH}/target`;

function remove_tree(path) {
    let info = stat(path);
    if (info == null)
        return;

    if (info.type == 'directory') {
        for (let entry in lsdir(path))
            remove_tree(`${path}/${entry}`);
        rmdir(path);
    }
    else
        unlink(path);
}

describe('replace_file()', () => {
    beforeEach(() => {
        remove_tree(SCRATCH);
        mkdir(SCRATCH);
    });

    it('creates a missing file with mode 0644', () => {
        replace_file(TARGET, 'new\n');

        assert.match('new\n', readfile(TARGET));
        assert.match(0644, stat(TARGET).mode);
    });

    it('replaces the content of an existing file', () => {
        writefile(TARGET, 'old\n');

        replace_file(TARGET, 'new\n');

        assert.match('new\n', readfile(TARGET));
    });

    it('keeps the permissions and ownership of an existing file', () => {
        writefile(TARGET, 'old\n');
        chmod(TARGET, 0600);
        chown(TARGET, 1, 1);

        replace_file(TARGET, 'new\n');

        let info = stat(TARGET);
        assert.match([ 0600, 1, 1 ], [ info.mode, info.uid, info.gid ]);
    });

    it('writes an empty file', () => {
        replace_file(TARGET, '');

        assert.match('', readfile(TARGET));
    });

    it('leaves no temporary file behind', () => {
        replace_file(TARGET, 'new\n');

        assert.match([ 'target' ], lsdir(SCRATCH));
    });

    it('raises an error when the directory is missing', () => {
        assert.throws(() => replace_file(`${SCRATCH}/missing/target`, 'new\n'),
                      `cannot write ${SCRATCH}/missing/target`);
    });

    it('removes the temporary file and raises an error when the rename fails', () => {
        mkdir(TARGET);

        assert.throws(() => replace_file(TARGET, 'new\n'), `cannot write ${TARGET}`);
        assert.match([ 'target' ], lsdir(SCRATCH));
        assert.match('directory', stat(TARGET).type);
    });
});
