# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, call

import pytest
from ansible.errors import AnsibleConnectionFailure

from ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action import (
    UCodeActionBase,
    UCodeModuleNotFound,
    UCodeModuleTransferFailed,
)

TMP_DIR = "/tmp/remote"


@pytest.fixture
def action():
    obj = object.__new__(UCodeActionBase)
    obj._task = MagicMock()
    obj._task.action = "community.openwrt.mymod"
    obj._task.async_val = 0
    obj._task.check_mode = False
    obj._task.args = {"name": "foo", "opts": {"a": 1}}
    obj._connection = MagicMock()
    obj._connection._shell.tmpdir = TMP_DIR
    obj._connection._shell.join_path = MagicMock(side_effect=lambda *p: "/".join(p))
    obj._templar = MagicMock()
    obj._make_tmp_path = MagicMock(return_value=TMP_DIR)
    obj._low_level_execute_command = MagicMock()
    obj._transfer_file = MagicMock()
    obj._fixup_perms2 = MagicMock()
    obj._execute_module = MagicMock(return_value={"changed": True, "failed": False})
    return obj


@pytest.fixture
def path_exists(mocker):
    return mocker.patch.object(Path, "exists", return_value=True)


@pytest.fixture
def path_missing(mocker):
    return mocker.patch.object(Path, "exists", return_value=False)


def _remote_paths(action):
    return [c.args[1] for c in action._transfer_file.call_args_list]


def test_exception_messages():
    assert str(UCodeModuleNotFound("mymod", "/p/mymod.uc")) == "Module script for mymod not found: /p/mymod.uc"
    assert str(UCodeModuleTransferFailed("boom")) == "Failed to transfer module script: boom"


def test_find_module_file(action, path_exists):
    result = action._find_module_file("mymod")
    assert result.parent.name == "modules"
    assert result.name == "mymod.uc"


def test_find_module_file_missing(action, path_missing):
    with pytest.raises(UCodeModuleNotFound, match=r"^Module script for mymod not found: .*/modules/mymod\.uc$"):
        action._find_module_file("mymod")


def test_find_module_util_script(action, path_exists):
    result = action._find_module_util_script("myutil")
    assert result.parent.name == "module_utils"
    assert result.name == "myutil.uc"


def test_find_module_util_script_missing(action, path_missing):
    with pytest.raises(UCodeModuleNotFound, match=r"^Module script for myutil not found: .*/module_utils/myutil\.uc$"):
        action._find_module_util_script("myutil")


def test_run_module_missing(action, path_missing):
    result = action.run(task_vars={})
    assert result["failed"] is True
    assert result["msg"].startswith("Module script for mymod not found: ")
    action._transfer_file.assert_not_called()
    action._execute_module.assert_not_called()


def test_run_module_util_missing(action, mocker):
    action.module_utils = ["myutil"]
    mocker.patch.object(Path, "exists", autospec=True, side_effect=lambda p: p.name != "myutil.uc")
    result = action.run(task_vars={})
    assert result["failed"] is True
    assert result["msg"].startswith("Module script for myutil not found: ")
    action._execute_module.assert_not_called()


def test_run_transfers_module_and_basic(action, path_exists):
    action.run(task_vars={})
    assert _remote_paths(action) == [
        f"{TMP_DIR}/module.uc",
        f"{TMP_DIR}/module_utils/_basic.uc",
    ]
    local_paths = [c.args[0] for c in action._transfer_file.call_args_list]
    assert local_paths[0].endswith("/modules/mymod.uc")
    assert local_paths[1].endswith("/module_utils/_basic.uc")
    action._low_level_execute_command.assert_called_once_with(f"mkdir -p '{TMP_DIR}/module_utils'")


def test_run_transfers_declared_module_utils_in_order(action, path_exists):
    action.module_utils = ["util_b", "util_a"]
    action.run(task_vars={})
    assert _remote_paths(action) == [
        f"{TMP_DIR}/module.uc",
        f"{TMP_DIR}/module_utils/_basic.uc",
        f"{TMP_DIR}/module_utils/util_b.uc",
        f"{TMP_DIR}/module_utils/util_a.uc",
    ]


def test_run_fixes_perms_for_each_file(action, path_exists):
    action.module_utils = ["myutil"]
    action.run(task_vars={})
    assert action._fixup_perms2.call_args_list == [call([p]) for p in _remote_paths(action)]


def test_run_reuses_existing_tmpdir(action, path_exists):
    action.run(task_vars={})
    action._make_tmp_path.assert_not_called()


def test_run_creates_tmpdir_when_unset(action, path_exists):
    action._connection._shell.tmpdir = None
    action._make_tmp_path.return_value = "/tmp/fresh"
    action.run(task_vars={})
    action._make_tmp_path.assert_called_once_with()
    assert _remote_paths(action)[0] == "/tmp/fresh/module.uc"


@pytest.mark.parametrize("failing", ["_transfer_file", "_fixup_perms2"])
def test_transfer_and_fixup_wraps_exception(action, failing):
    original = OSError("connection lost")
    getattr(action, failing).side_effect = original
    with pytest.raises(
        UCodeModuleTransferFailed, match="^Failed to transfer module script: connection lost$"
    ) as exc_info:
        action._transfer_and_fixup(Path("/local/mymod.uc"), f"{TMP_DIR}/module.uc")
    assert exc_info.value.__cause__ is original


@pytest.mark.parametrize("failing", ["_transfer_file", "_fixup_perms2"])
def test_run_transfer_failure(action, path_exists, failing):
    getattr(action, failing).side_effect = OSError("connection lost")
    result = action.run(task_vars={})
    assert result["failed"] is True
    assert result["msg"] == "Failed to transfer module script: connection lost"
    action._execute_module.assert_not_called()


def test_run_raises_connection_failure_on_tmp_path(action, path_exists):
    action._connection._shell.tmpdir = None
    action._make_tmp_path.side_effect = AnsibleConnectionFailure("ssh: connect to host: Connection timed out")
    with pytest.raises(AnsibleConnectionFailure):
        action.run(task_vars={})


def test_run_raises_connection_failure_on_transfer(action, path_exists):
    action._transfer_file.side_effect = AnsibleConnectionFailure("Data could not be sent to remote host")
    with pytest.raises(AnsibleConnectionFailure):
        action.run(task_vars={})


def test_run_executes_ucode_wrapper(action, path_exists):
    task_vars = {"some_var": 1}
    action.run(task_vars=task_vars)
    action._execute_module.assert_called_once_with(
        module_name="community.openwrt.ucode_wrapper",
        module_args={"name": "foo", "opts": {"a": 1}, "_openwrt_module_name": "community.openwrt.mymod"},
        task_vars=task_vars,
    )


def test_run_does_not_modify_task_args(action, path_exists):
    action.run(task_vars={})
    assert action._task.args == {"name": "foo", "opts": {"a": 1}}


def test_run_returns_module_result(action, path_exists):
    action._execute_module.return_value = {"changed": True, "failed": False, "value": 42}
    result = action.run(task_vars={})
    assert result["changed"] is True
    assert result["value"] == 42
    assert not result["failed"]
