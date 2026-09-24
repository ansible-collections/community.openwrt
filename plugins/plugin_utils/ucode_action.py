# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
from pathlib import Path

from ansible.plugins.action import ActionBase


class UCodeModuleNotFound(Exception):
    def __init__(self, name, path):
        super().__init__(f"Module script for {name} not found: {path}")


class UCodeModuleTransferFailed(Exception):
    def __init__(self, msg):
        super().__init__(f"Failed to transfer module script: {msg}")


class UCodeActionBase(ActionBase):
    """Base action plugin for ucode-based OpenWrt modules.

    Modules written in ucode (``plugins/modules/<name>.uc``) are transferred, together with
    ``_basic`` and any module_utils they declare, into a shared remote temporary directory, then
    executed through the ``community.openwrt.ucode_wrapper`` module via ``_execute_module()``. That
    wrapper execs ``ucode -S -L <module_utils dir> module.uc <args>``, so module_utils are
    imported by name (e.g. ``import { AnsibleModule } from '_basic';``) rather than by relative
    file path.
    """

    module_utils = []

    def run(self, tmp=None, task_vars=None):
        if task_vars is None:
            task_vars = {}

        result = super().run(tmp, task_vars)
        del tmp  # not used directly

        module_name = self._task.action.split(".")[-1]
        try:
            result.update(self._run_ucode_module(module_name, self._task.args.copy(), task_vars))
        except Exception as e:
            result["failed"] = True
            result["msg"] = str(e)

        return result

    def _run_ucode_module(self, module_name, module_args, task_vars):
        """Transfer a ucode module + module_utils, then run it via the ucode wrapper."""
        module_path = self._find_module_file(module_name)

        self._make_tmp_path()
        tmp_dir = self._connection._shell.tmpdir

        self._transfer_module_file(module_path, tmp_dir)
        self._transfer_module_utils(tmp_dir)

        module_args["_openwrt_module_name"] = self._task.action
        return self._execute_module(
            module_name="community.openwrt.ucode_wrapper",
            module_args=module_args,
            task_vars=task_vars,
        )

    def _find_module_file(self, module_name):
        """Find the module's .uc file in the collection."""
        plugin_utils_dir = os.path.dirname(os.path.abspath(__file__))
        plugins_dir = os.path.dirname(plugin_utils_dir)
        modules_dir = os.path.join(plugins_dir, "modules")
        module_path = os.path.join(modules_dir, f"{module_name}.uc")

        if not os.path.exists(module_path):
            raise UCodeModuleNotFound(module_name, module_path)

        return module_path

    def _find_module_util_script(self, util_name):
        """Find a ucode module util in plugins/module_utils/<util_name>.uc."""
        util_path = Path(__file__).parent.parent / "module_utils" / f"{util_name}.uc"
        if not util_path.exists():
            raise UCodeModuleNotFound(util_name, str(util_path))
        return util_path

    def _transfer_module_file(self, module_path, tmp_dir):
        """Transfer the module .uc file into the shared tmp dir under a fixed name."""
        remote_module = self._connection._shell.join_path(tmp_dir, "module.uc")
        self._transfer_file(str(module_path), remote_module)
        self._fixup_perms2([remote_module])

    def _transfer_module_utils(self, tmp_dir):
        """Transfer _basic and any declared ucode module utils into <tmp_dir>/module_utils/."""
        remote_utils_dir = self._connection._shell.join_path(tmp_dir, "module_utils")
        self._low_level_execute_command(f"mkdir -p '{remote_utils_dir}'")
        for util_name in ["_basic"] + list(self.module_utils):
            util_path = self._find_module_util_script(util_name)
            remote_util = self._connection._shell.join_path(remote_utils_dir, f"{util_name}.uc")
            self._transfer_file(str(util_path), remote_util)
            self._fixup_perms2([remote_util])
