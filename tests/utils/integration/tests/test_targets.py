# Copyright (c) 2025, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

import os


def test_target(run_openwrt_test):
    target = os.environ.get("TEST_TARGET_NAME")
    if not target:
        raise AssertionError("TEST_TARGET_NAME must be set by the test entrypoint")
    run_openwrt_test(target)
