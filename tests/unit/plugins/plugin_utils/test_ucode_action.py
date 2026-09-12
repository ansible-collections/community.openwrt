# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action import (
    UcodeModuleNotFound,
    UcodeModuleTransferFailed,
    UcodeOpenwrtActionBase,
)

# Path to patch os.path.exists in the module under test
_UCODE_ACTION_MODULE = "ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action"


@pytest.fixture
def action():
    """Return a bare UcodeOpenwrtActionBase instance with mocked dependencies."""
    obj = object.__new__(UcodeOpenwrtActionBase)
    obj._task = MagicMock()
    obj._connection = MagicMock()
    obj._templar = MagicMock()
    obj._display = MagicMock()
    return obj


def test_module_not_found_is_exception_subclass():
    assert issubclass(UcodeModuleNotFound, Exception)


def test_module_not_found_message_format():
    exc = UcodeModuleNotFound("uc_uci", "/path/to/uc_uci.uc")
    assert str(exc) == "Module script for uc_uci not found: /path/to/uc_uci.uc"


def test_module_not_found_can_be_raised_and_caught():
    with pytest.raises(UcodeModuleNotFound):
        raise UcodeModuleNotFound("uc_uci", "/plugins/modules/uc_uci.uc")


def test_transfer_failed_is_exception_subclass():
    assert issubclass(UcodeModuleTransferFailed, Exception)


def test_transfer_failed_message_format():
    exc = UcodeModuleTransferFailed("connection refused")
    assert str(exc) == "Failed to transfer ucode module: connection refused"


def test_find_module_file_raises_when_uc_missing(action):
    with patch(f"{_UCODE_ACTION_MODULE}.os.path.exists", return_value=False):
        with pytest.raises(UcodeModuleNotFound) as exc_info:
            action._find_module_file("uc_uci")
    assert "uc_uci" in str(exc_info.value)
    assert "uc_uci.uc" in str(exc_info.value)


def test_find_module_file_returns_path_when_uc_exists(action):
    with patch(f"{_UCODE_ACTION_MODULE}.os.path.exists", return_value=True):
        result = action._find_module_file("uc_uci")
    assert result.endswith("uc_uci.uc")


def test_find_module_util_script_raises_when_uc_missing(action):
    with patch.object(Path, "exists", return_value=False):
        with pytest.raises(UcodeModuleNotFound) as exc_info:
            action._find_module_util_script("ansible_common")
    assert "ansible_common" in str(exc_info.value)
    assert "ansible_common.uc" in str(exc_info.value)


def test_find_module_util_script_returns_path_under_module_utils(action):
    with patch.object(Path, "exists", return_value=True):
        result = action._find_module_util_script("ansible_common")
    assert str(result).endswith("ansible_common.uc")
    assert "module_utils" in str(result)


def test_transfer_module_utils_transfers_declared_utils(action):
    action.module_utils = ["ansible_common"]
    action._connection._shell.join_path = MagicMock(side_effect=lambda *p: "/".join(p))
    action._transfer_file = MagicMock()
    action._fixup_perms2 = MagicMock()

    with patch.object(Path, "exists", return_value=True):
        action._transfer_module_utils("/tmp/ans")

    action._transfer_file.assert_called_once()
    remote_util = action._transfer_file.call_args[0][1]
    assert remote_util.endswith("ansible_common.uc")
    action._fixup_perms2.assert_called_once()


def test_transfer_args_serializes_to_json(action):
    action._connection._shell.join_path = MagicMock(side_effect=lambda *p: "/".join(p))
    action._transfer_data = MagicMock()

    args_path = action._transfer_args("/tmp/ans", {"command": "get"})

    assert args_path == "/tmp/ans/args"
    data = action._transfer_data.call_args[0][1]
    assert '"command": "get"' in data


def test_run_ucode_module_parses_stdout_json(action):
    action._task.action = "community.openwrt.uc_uci"
    action._task.args = {"command": "get"}
    action._task.check_mode = False
    action._task.diff = False
    action._task.no_log = False
    action._task.environment = []

    action._make_tmp_path = MagicMock(return_value="/tmp/ans")
    action._find_module_file = MagicMock(return_value="/plugins/modules/uc_uci.uc")
    action._transfer_module_file = MagicMock(return_value="/tmp/ans/uc_uci.uc")
    action._transfer_module_utils = MagicMock()
    action._transfer_args = MagicMock(return_value="/tmp/ans/args")
    action._update_module_args = MagicMock()
    action._low_level_execute_command = MagicMock(
        return_value={"rc": 0, "stdout": '{"changed": true, "failed": false, "result": "cfg123"}', "stderr": ""}
    )

    result = action._run_ucode_module("uc_uci", {"command": "get"}, {})

    assert result["changed"] is True
    assert result["result"] == "cfg123"
    assert result["failed"] is False


def test_run_ucode_module_reports_nonzero_rc(action):
    action._task.action = "community.openwrt.uc_uci"
    action._task.args = {"command": "get"}
    action._task.check_mode = False
    action._task.diff = False
    action._task.no_log = False
    action._task.environment = []

    action._make_tmp_path = MagicMock(return_value="/tmp/ans")
    action._find_module_file = MagicMock(return_value="/plugins/modules/uc_uci.uc")
    action._transfer_module_file = MagicMock(return_value="/tmp/ans/uc_uci.uc")
    action._transfer_module_utils = MagicMock()
    action._transfer_args = MagicMock(return_value="/tmp/ans/args")
    action._update_module_args = MagicMock()
    action._low_level_execute_command = MagicMock(
        return_value={"rc": 1, "stdout": '{"changed": false, "failed": false}', "stderr": "boom"}
    )

    result = action._run_ucode_module("uc_uci", {"command": "get"}, {})

    assert result["failed"] is True
    assert "boom" in result["msg"]


def test_run_ucode_module_handles_invalid_json(action):
    action._task.action = "community.openwrt.uc_uci"
    action._task.args = {"command": "get"}
    action._task.check_mode = False
    action._task.diff = False
    action._task.no_log = False
    action._task.environment = []

    action._make_tmp_path = MagicMock(return_value="/tmp/ans")
    action._find_module_file = MagicMock(return_value="/plugins/modules/uc_uci.uc")
    action._transfer_module_file = MagicMock(return_value="/tmp/ans/uc_uci.uc")
    action._transfer_module_utils = MagicMock()
    action._transfer_args = MagicMock(return_value="/tmp/ans/args")
    action._update_module_args = MagicMock()
    action._low_level_execute_command = MagicMock(return_value={"rc": 0, "stdout": "not json at all", "stderr": ""})

    result = action._run_ucode_module("uc_uci", {"command": "get"}, {})

    assert result["failed"] is True
    assert "invalid JSON" in result["msg"]
