# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock

import pytest
from ansible.errors import AnsibleConnectionFailure
from ansible.plugins.action import ActionBase

from ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action import UCodeActionBase


@pytest.fixture
def action(mocker):
    mocker.patch.object(ActionBase, "run", return_value={})
    obj = object.__new__(UCodeActionBase)
    obj._task = MagicMock()
    obj._task.action = "community.openwrt.ping"
    obj._task.args = {}
    obj._connection = MagicMock()
    obj._connection._shell.tmpdir = "/tmp/remote"
    obj._connection._shell.join_path = MagicMock(side_effect=lambda *parts: "/".join(parts))
    obj._find_module_file = MagicMock(return_value=Path("/collection/plugins/modules/ping.uc"))
    obj._find_module_util_script = MagicMock(return_value=Path("/collection/plugins/module_utils/_basic.uc"))
    obj._make_tmp_path = MagicMock(return_value="/tmp/remote")
    obj._low_level_execute_command = MagicMock(return_value={"rc": 0, "stdout": "", "stderr": ""})
    obj._transfer_file = MagicMock()
    obj._fixup_perms2 = MagicMock()
    obj._execute_module = MagicMock(return_value={"changed": False, "ping": "pong"})
    return obj


def test_run_returns_module_result(action):
    result = action.run(task_vars={})
    assert result == {"changed": False, "ping": "pong"}


def test_run_raises_connection_failure_on_tmp_path(action):
    action._connection._shell.tmpdir = None
    action._make_tmp_path.side_effect = AnsibleConnectionFailure("ssh: connect to host: Connection timed out")
    with pytest.raises(AnsibleConnectionFailure):
        action.run(task_vars={})


def test_run_raises_connection_failure_on_transfer(action):
    action._transfer_file.side_effect = AnsibleConnectionFailure("Data could not be sent to remote host")
    with pytest.raises(AnsibleConnectionFailure):
        action.run(task_vars={})


def test_run_fails_on_transfer_error(action):
    action._transfer_file.side_effect = OSError("disk full")
    result = action.run(task_vars={})
    assert result["failed"] is True
    assert result["msg"] == "Failed to transfer module script: disk full"
    action._execute_module.assert_not_called()
