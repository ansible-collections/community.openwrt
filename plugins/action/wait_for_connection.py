# Copyright (c) 2026 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from unittest import mock

from ansible.plugins.action.wait_for_connection import ActionModule as WaitForConnectionActionModule

from ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action import OpenwrtActionBase


class ActionModule(OpenwrtActionBase, WaitForConnectionActionModule):
    def run(self, tmp=None, task_vars=None):
        _orig_execute_module = self._execute_module

        def _execute_module(module_name=None, module_args=None, task_vars=None, **kwargs):
            if module_name == "ansible.legacy.ping":
                return self._run_shell_module("ping", {}, task_vars)
            return _orig_execute_module(module_name=module_name, module_args=module_args, task_vars=task_vars, **kwargs)

        with mock.patch.object(self, "_execute_module", _execute_module):
            return WaitForConnectionActionModule.run(self, tmp, task_vars)
