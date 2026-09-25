# Copyright (c) 2026, Vladimir Ermakov (@vooon)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action import UCodeActionBase


class ActionModule(UCodeActionBase):
    module_utils = ["_uci", "_wg"]
