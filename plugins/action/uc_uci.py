# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action import UcodeOpenwrtActionBase


class ActionModule(UcodeOpenwrtActionBase):
    module_utils = ["ansible_common"]
