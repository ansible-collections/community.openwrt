#!/usr/bin/python
# Copyright (c) 2025 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations

from ansible.errors import AnsibleError
from ansible.module_utils._text import to_bytes
from ansible.plugins.action import ActionBase
from ansible.utils.hashing import checksum


class ActionModule(ActionBase):
    """Action plugin for community.openwrt.copy module

    Handles file transfer from controller to remote OpenWRT device,
    then invokes the shell-based copy module to handle permissions,
    backup, and other file operations.
    """

    TRANSFERS_FILES = True

    def run(self, tmp=None, task_vars=None):
        """Execute the copy action plugin"""

        if task_vars is None:
            task_vars = {}

        result = super(ActionModule, self).run(tmp, task_vars)
        del tmp  # not used

        source = self._task.args.get("src", None)
        dest = self._task.args.get("dest", None)
        content = self._task.args.get("content", None)

        if not dest:
            result["failed"] = True
            result["msg"] = "dest is required"
            return result

        # Handle content parameter (create temp file with content)
        if content is not None:
            # Create a temp file with the content
            try:
                content_tempfile = self._create_content_tempfile(content)
                source = content_tempfile
            except Exception as e:
                result["failed"] = True
                result["msg"] = f"Failed to create content tempfile: {e}"
                return result
        elif source is None:
            result["failed"] = True
            result["msg"] = "src or content is required"
            return result
        else:
            # Find the source file on the controller
            try:
                source = self._find_needle("files", source)
            except AnsibleError as e:
                result["failed"] = True
                result["msg"] = str(e)
                return result

        # Get checksum of source file
        try:
            source_checksum = checksum(source)
        except Exception as e:
            result["failed"] = True
            result["msg"] = f"Failed to checksum source file: {e}"
            return result

        # Transfer the file to a temporary location on the remote
        try:
            tmp_src = self._connection._shell.join_path(
                self._connection._shell.tmpdir, "source"
            )
            self._transfer_file(source, tmp_src)
            self._fixup_perms2((self._connection._shell.tmpdir, tmp_src))
        except Exception as e:
            result["failed"] = True
            result["msg"] = f"Failed to transfer file: {e}"
            return result

        # Update task args to use the transferred file
        new_module_args = self._task.args.copy()
        new_module_args["src"] = tmp_src

        # Remove content from args if it was used (we've already created the file)
        new_module_args.pop("content", None)

        # Execute the shell-based copy module on the remote
        result.update(
            self._execute_module(
                module_name="community.openwrt.copy",
                module_args=new_module_args,
                task_vars=task_vars,
            )
        )

        return result

    def _create_content_tempfile(self, content):
        """Create a temporary file with the given content"""
        import tempfile

        # Create temp file in system temp directory
        fd, content_tempfile = tempfile.mkstemp()

        # Write content to it
        with open(fd, "wb") as f:
            f.write(to_bytes(content))

        return content_tempfile
