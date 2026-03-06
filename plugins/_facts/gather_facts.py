# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import copy
import importlib.util
import os
from unittest import mock

from ansible import constants as C
import ansible.plugins.action as _ansible_action_pkg

# Import the builtin gather_facts ActionModule by file path to avoid a circular
# import: Ansible loads this file under the module name
# 'ansible.plugins.action.gather_facts', so a regular import of that name would
# resolve back to this very file.
_builtin_path = os.path.join(os.path.dirname(_ansible_action_pkg.__file__), 'gather_facts.py')
_spec = importlib.util.spec_from_file_location('_ansible_builtin_gather_facts', _builtin_path)
_builtin_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_builtin_module)
GatherFactsActionModule = _builtin_module.ActionModule

OPENWRT_SETUP = 'community.openwrt.setup'


class ActionModule(GatherFactsActionModule):

    def run(self, tmp=None, task_vars=None):
        if task_vars is None:
            task_vars = {}

        if not task_vars.get('openwrt_gather_facts'):
            return super().run(tmp, task_vars)

        _orig_execute_module = self._execute_module

        def _patched_execute_module(module_name=None, module_args=None, task_vars=None, **kwargs):
            if module_name in C._ACTION_SETUP:
                task = copy.copy(self._task)
                task.action = OPENWRT_SETUP
                setup_action = self._shared_loader_obj.action_loader.get(
                    OPENWRT_SETUP,
                    task=task,
                    connection=self._connection,
                    play_context=self._play_context,
                    loader=self._loader,
                    templar=self._templar,
                    shared_loader_obj=self._shared_loader_obj,
                )
                return setup_action.run(task_vars=task_vars)
            return _orig_execute_module(module_name=module_name, module_args=module_args, task_vars=task_vars, **kwargs)

        with mock.patch.object(self, '_execute_module', _patched_execute_module):
            return super().run(tmp, task_vars)
