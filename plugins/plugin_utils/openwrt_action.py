# Copyright (c) 2025, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
from pathlib import Path

from ansible.plugins.action import ActionBase


class ModuleNotFound(Exception):
    def __init__(self, name, path):
        super().__init__(f"Module script for {name} not found: {path}")


class ModuleTransferFailed(Exception):
    def __init__(self, msg):
        super().__init__(f"Failed to transfer module script: {msg}")


class OpenwrtActionBase(ActionBase):
    """Base action plugin for OpenWrt modules

    This action plugin wraps shell-based OpenWrt modules by:
    1. Reading the module's .sh file content
    2. Transferring it to the remote target
    3. Executing the wrapper.sh module with the script path as argument

    The wrapper.sh module handles sourcing and executing the actual module code.
    """

    module_utils = []

    def run(self, tmp=None, task_vars=None):
        """Execute the OpenWrt module via wrapper"""

        if task_vars is None:
            task_vars = {}

        result = super().run(tmp, task_vars)
        del tmp  # not used directly

        module_name = self._task.action.split(".")[-1]
        try:
            result.update(self._run_shell_module(module_name, self._task.args.copy(), task_vars))
        except Exception as e:
            result["failed"] = True
            result["msg"] = str(e)

        return result

    def _run_shell_module(self, module_name, module_args, task_vars):
        """Find, transfer and execute a shell module via wrapper"""
        module_script_path = self._find_module_script(module_name)
        tmp_dir = self._make_tmp_path()
        remote_script = self._transfer_module_script(module_name, module_script_path, tmp_dir)
        module_args["_openwrt_script"] = remote_script
        module_args["_openwrt_libs"] = self._transfer_module_utils(tmp_dir)
        return self._execute_module(
            module_name="community.openwrt.wrapper",
            module_args=module_args,
            task_vars=task_vars,
        )

    def _find_module_script(self, module_name):
        """Find the module's .sh file in the collection"""
        plugin_utils_dir = os.path.dirname(os.path.abspath(__file__))
        plugins_dir = os.path.dirname(plugin_utils_dir)
        modules_dir = os.path.join(plugins_dir, "modules")
        module_path = os.path.join(modules_dir, f"{module_name}.sh")

        if not os.path.exists(module_path):
            raise ModuleNotFound(module_name, module_path)

        return module_path

    def _find_module_util_script(self, util_name):
        """Find a shell module util in plugins/module_utils/<util_name>.sh"""
        util_path = Path(__file__).parent.parent / "module_utils" / f"{util_name}.sh"
        if not util_path.exists():
            raise ModuleNotFound(util_name, str(util_path))
        return util_path

    def _transfer_and_fixup(self, local_path, remote_path):
        self._transfer_file(str(local_path), remote_path)
        self._fixup_perms2([remote_path])

    def _transfer_module_script(self, module_name, module_script_path, tmp_dir):
        try:
            remote_script = self._connection._shell.join_path(tmp_dir, f"{module_name}.sh")
            self._transfer_and_fixup(module_script_path, remote_script)
            return remote_script
        except Exception as e:
            raise ModuleTransferFailed(str(e)) from e

    def _transfer_module_utils(self, tmp_dir):
        """Transfer _core and any declared shell module utils to <tmp_dir>/module_utils/"""
        remote_utils_dir = self._connection._shell.join_path(tmp_dir, "module_utils")
        self._low_level_execute_command(f"mkdir -p '{remote_utils_dir}'")
        remote_utils = []
        for util_name in ["_core"] + list(self.module_utils):
            util_path = self._find_module_util_script(util_name)
            remote_util = self._connection._shell.join_path(remote_utils_dir, f"{util_name}.sh")
            self._transfer_and_fixup(util_path, remote_util)
            remote_utils.append(remote_util)
        return remote_utils
