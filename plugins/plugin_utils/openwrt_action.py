# Copyright (c) 2025 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations

import os
from ansible.plugins.action import ActionBase


class OpenwrtActionBase(ActionBase):
    """Base action plugin for OpenWRT modules

    This action plugin wraps shell-based OpenWRT modules by:
    1. Reading the module's .sh file content
    2. Transferring it to the remote target
    3. Executing the wrapper.sh module with the script path as argument

    The wrapper.sh module handles sourcing and executing the actual module code.
    """

    def run(self, tmp=None, task_vars=None):
        """Execute the OpenWRT module via wrapper"""

        if task_vars is None:
            task_vars = {}

        result = super(OpenwrtActionBase, self).run(tmp, task_vars)
        del tmp  # not used directly

        module_name = self._task.action.split(".")[-1]
        try:
            module_script_path = self._find_module_script(module_name)
        except Exception as e:
            result["failed"] = True
            result["msg"] = f"Failed to find module script: {e}"
            return result

        try:
            tmp_dir = self._make_tmp_path()
            remote_script = self._connection._shell.join_path(tmp_dir, f"{module_name}.sh")
            self._transfer_file(module_script_path, remote_script)
            self._fixup_perms2([remote_script])
        except Exception as e:
            result["failed"] = True
            result["msg"] = f"Failed to transfer module script: {e}"
            return result

        module_args = self._task.args.copy()
        module_args["_openwrt_script"] = remote_script
        result.update(
            self._execute_module(
                module_name="community.openwrt.wrapper",
                module_args=module_args,
                task_vars=task_vars,
            )
        )

        return result

    def _find_module_script(self, module_name):
        """Find the module's .sh file in the collection"""
        plugin_utils_dir = os.path.dirname(os.path.abspath(__file__))
        plugins_dir = os.path.dirname(plugin_utils_dir)
        modules_dir = os.path.join(plugins_dir, "modules")
        module_path = os.path.join(modules_dir, f"{module_name}.sh")

        if not os.path.exists(module_path):
            raise Exception(f"Module script not found: {module_path}")

        return module_path
