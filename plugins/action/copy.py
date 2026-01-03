# Copyright (c) 2025 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations

from tempfile import mkstemp

from ansible.errors import AnsibleError
from ansible.module_utils.common.text.converters import to_bytes
from ansible.utils.hashing import checksum

from ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action import OpenwrtActionBase


class ActionModule(OpenwrtActionBase):
    """Action plugin for community.openwrt.copy module

    Handles file transfer from controller to remote OpenWRT device,
    then invokes the shell-based copy module to handle permissions,
    backup, and other file operations.
    """

    def run(self, tmp=None, task_vars=None):
        """Execute the copy action plugin"""

        if task_vars is None:
            task_vars = {}

        result = {}

        source = self._task.args.get("src", None)
        dest = self._task.args.get("dest", None)
        content = self._task.args.get("content", None)

        if not dest:
            result["failed"] = True
            result["msg"] = "dest is required"
            return result

        if source and content is not None:
            result["failed"] = True
            result["msg"] = "source and content are mutually exclusive"
            return result

        if content is not None:
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

        # Create remote temp directory
        try:
            tmp_dir = self._make_tmp_path()
            tmp_src = self._connection._shell.join_path(tmp_dir, "source")
            self._transfer_file(source, tmp_src)
            self._fixup_perms2([tmp_src])
        except Exception as e:
            result["failed"] = True
            result["msg"] = f"Failed to transfer file: {e}"
            return result

        self._task.args = self._task.args.copy()
        self._task.args["src"] = tmp_src
        self._task.args.pop("content", None)
        return super(ActionModule, self).run(tmp, task_vars)

    def _create_content_tempfile(self, content):
        """Create a temporary file with the given content"""

        fd, content_tempfile = mkstemp()
        with open(fd, "wb") as f:
            f.write(to_bytes(content))

        return content_tempfile
