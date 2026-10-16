// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

return {
    reporter: 'compact',
    pattern: 'test_*.uc',
    lib_paths: [ '../../plugins/module_utils' ],
    mocks: {
        fs: null,
        _basic: { proxy: 'utils/basic_proxy.uc' },
    },
};
