# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import json
import os
from pathlib import Path

from ansible.plugins.action import ActionBase


class UcodeModuleNotFound(Exception):
    def __init__(self, name, path):
        super().__init__(f"Module script for {name} not found: {path}")


class UcodeModuleTransferFailed(Exception):
    def __init__(self, msg):
        super().__init__(f"Failed to transfer ucode module: {msg}")


class UcodeOpenwrtActionBase(ActionBase):
    """Base action plugin for ucode-based OpenWrt modules.

    Modules written in ucode (``plugins/modules/<name>.uc``) run directly on the
    target with ``/usr/bin/ucode`` and share a helper library
    (``plugins/module_utils/ansible_common.uc``) via a relative ``import``.

    This action plugin:
      1. Transfers the module ``.uc`` file and its ``ansible_common.uc`` helper
         into the same remote temporary directory (so the relative import
         resolves).
      2. Writes the module arguments as a JSON file next to them.
      3. Executes ``ucode <module> <args>`` and parses the JSON emitted on
         stdout into the Ansible result.

    No shell wrapper is involved; JSON is handled natively by ucode.
    """

    module_utils = ["ansible_common"]

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
        """Transfer a ucode module + helpers and execute it via ucode."""
        module_path = self._find_module_file(module_name)
        tmp_dir = self._make_tmp_path()

        remote_module = self._transfer_module_file(module_name, module_path, tmp_dir)
        self._transfer_module_utils(tmp_dir)

        self._update_module_args(module_name, module_args, task_vars)
        args_path = self._transfer_args(tmp_dir, module_args)

        cmd = f"ucode {remote_module} {args_path}"
        exec_result = self._low_level_execute_command(cmd)

        rc = exec_result["rc"]
        stdout = exec_result["stdout"]
        stderr = exec_result["stderr"]

        if stderr:
            self._display.vvv(f"ucode module stderr: {stderr}")

        if not stdout.strip():
            result = {
                "failed": True,
                "msg": f"ucode module produced no output{(': ' + stderr) if stderr else ''}",
            }
        else:
            try:
                result = json.loads(stdout)
            except json.JSONDecodeError as e:
                result = {
                    "failed": True,
                    "msg": f"ucode module produced invalid JSON: {e}\n{stdout}",
                }

        if rc != 0 and not result.get("failed"):
            result["failed"] = True
            result.setdefault("msg", f"ucode module exited with rc {rc}{(': ' + stderr) if stderr else ''}")

        return result

    def _find_module_file(self, module_name):
        """Find the module's .uc file in the collection."""
        plugin_utils_dir = os.path.dirname(os.path.abspath(__file__))
        plugins_dir = os.path.dirname(plugin_utils_dir)
        modules_dir = os.path.join(plugins_dir, "modules")
        module_path = os.path.join(modules_dir, f"{module_name}.uc")

        if not os.path.exists(module_path):
            raise UcodeModuleNotFound(module_name, module_path)

        return module_path

    def _find_module_util_script(self, util_name):
        """Find a ucode module util in plugins/module_utils/<util_name>.uc."""
        util_path = Path(__file__).parent.parent / "module_utils" / f"{util_name}.uc"
        if not util_path.exists():
            raise UcodeModuleNotFound(util_name, str(util_path))
        return util_path

    def _transfer_module_file(self, module_name, module_path, tmp_dir):
        try:
            remote_module = self._connection._shell.join_path(tmp_dir, f"{module_name}.uc")
            self._transfer_file(str(module_path), remote_module)
            self._fixup_perms2([remote_module])
            return remote_module
        except Exception as e:
            raise UcodeModuleTransferFailed(str(e)) from e

    def _transfer_module_utils(self, tmp_dir):
        """Transfer declared ucode module utils next to the module file."""
        for util_name in self.module_utils:
            util_path = self._find_module_util_script(util_name)
            remote_util = self._connection._shell.join_path(tmp_dir, f"{util_name}.uc")
            self._transfer_file(str(util_path), remote_util)
            self._fixup_perms2([remote_util])

    def _transfer_args(self, tmp_dir, module_args):
        """Serialize module args to JSON and transfer them to the remote."""
        try:
            args_path = self._connection._shell.join_path(tmp_dir, "args")
            data = json.dumps(module_args)
            self._transfer_data(args_path, data)
            return args_path
        except Exception as e:
            raise UcodeModuleTransferFailed(str(e)) from e
