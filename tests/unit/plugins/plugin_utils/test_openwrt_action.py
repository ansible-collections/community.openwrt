# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action import (
    ModuleNotFound,
    ModuleTransferFailed,
    OpenwrtActionBase,
)

# Path to patch os.path.exists in the module under test
_OPENWRT_ACTION_MODULE = "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action"


@pytest.fixture
def action():
    """Return a bare OpenwrtActionBase instance with mocked dependencies."""
    obj = object.__new__(OpenwrtActionBase)
    obj._task = MagicMock()
    obj._connection = MagicMock()
    obj._templar = MagicMock()
    return obj


def test_module_not_found_is_exception_subclass():
    assert issubclass(ModuleNotFound, Exception)


def test_module_not_found_message_format():
    exc = ModuleNotFound("mymodule", "/path/to/mymodule.sh")
    assert str(exc) == "Module script for mymodule not found: /path/to/mymodule.sh"


def test_module_not_found_can_be_raised_and_caught():
    with pytest.raises(ModuleNotFound):
        raise ModuleNotFound("ping", "/plugins/modules/ping.sh")


def test_module_transfer_failed_is_exception_subclass():
    assert issubclass(ModuleTransferFailed, Exception)


def test_module_transfer_failed_message_format():
    exc = ModuleTransferFailed("connection refused")
    assert str(exc) == "Failed to transfer module script: connection refused"


def test_module_transfer_failed_can_be_raised_and_caught():
    with pytest.raises(ModuleTransferFailed):
        raise ModuleTransferFailed("SSH timeout")


def test_find_module_script_raises_when_sh_missing(action):
    with patch(f"{_OPENWRT_ACTION_MODULE}.os.path.exists", return_value=False):
        with pytest.raises(ModuleNotFound) as exc_info:
            action._find_module_script("mymodule")
    assert "mymodule" in str(exc_info.value)
    assert "mymodule.sh" in str(exc_info.value)


def test_find_module_script_message_starts_with_prefix(action):
    with patch(f"{_OPENWRT_ACTION_MODULE}.os.path.exists", return_value=False):
        with pytest.raises(ModuleNotFound) as exc_info:
            action._find_module_script("mymodule")
    assert str(exc_info.value).startswith("Module script for mymodule not found: ")


def test_find_module_script_returns_path_when_sh_exists(action):
    with patch(f"{_OPENWRT_ACTION_MODULE}.os.path.exists", return_value=True):
        result = action._find_module_script("mymodule")
    assert result.endswith("mymodule.sh")


def test_transfer_module_script_raises_when_transfer_and_fixup_fails(action):
    action._connection._shell.join_path = MagicMock(return_value="/tmp/ansible-remote/mymodule.sh")
    action._transfer_and_fixup = MagicMock(side_effect=Exception("transfer error"))

    with pytest.raises(ModuleTransferFailed) as exc_info:
        action._transfer_module_script("mymodule", "/some/path/mymodule.sh", "/tmp/ansible-remote")
    assert "transfer error" in str(exc_info.value)


def test_transfer_module_script_wraps_original_exception(action):
    original = Exception("root cause")
    action._connection._shell.join_path = MagicMock(side_effect=original)

    with pytest.raises(ModuleTransferFailed) as exc_info:
        action._transfer_module_script("mymodule", "/some/path/mymodule.sh", "/tmp/ansible-remote")
    assert exc_info.value.__cause__ is original


def test_module_utils_default_is_empty_list():
    assert OpenwrtActionBase.module_utils == []


def test_find_module_util_script_raises_when_sh_missing(action):
    with patch.object(Path, "exists", return_value=False):
        with pytest.raises(ModuleNotFound) as exc_info:
            action._find_module_util_script("myutil")
    assert "myutil" in str(exc_info.value)
    assert "myutil.sh" in str(exc_info.value)


def test_find_module_util_script_returns_path_under_module_utils(action):
    with patch.object(Path, "exists", return_value=True):
        result = action._find_module_util_script("myutil")
    assert str(result).endswith("myutil.sh")
    assert "module_utils" in str(result)


def test_transfer_module_utils_always_transfers_core(action):
    action.module_utils = []
    action._connection._shell.join_path = MagicMock(side_effect=lambda *p: "/".join(p))
    action._low_level_execute_command = MagicMock()
    action._transfer_and_fixup = MagicMock()

    with patch.object(Path, "exists", return_value=True):
        result = action._transfer_module_utils("/tmp/ans")

    assert len(result) == 1
    assert result[0].endswith("_core.sh")


def test_transfer_module_utils_creates_remote_dir(action):
    action.module_utils = ["lib_a"]
    action._connection._shell.join_path = MagicMock(side_effect=lambda *p: "/".join(p))
    action._low_level_execute_command = MagicMock()
    action._transfer_and_fixup = MagicMock()

    with patch.object(Path, "exists", return_value=True):
        action._transfer_module_utils("/tmp/ans")

    action._low_level_execute_command.assert_called_once_with("mkdir -p '/tmp/ans/module_utils'")


def test_transfer_module_utils_transfers_in_declaration_order(action):
    action.module_utils = ["lib_a", "lib_b"]
    action._connection._shell.join_path = MagicMock(side_effect=lambda *p: "/".join(p))
    action._low_level_execute_command = MagicMock()
    action._transfer_and_fixup = MagicMock()

    with patch.object(Path, "exists", return_value=True):
        result = action._transfer_module_utils("/tmp/ans")

    remote_paths = [call.args[1] for call in action._transfer_and_fixup.call_args_list]
    assert remote_paths[0].endswith("_core.sh")
    assert remote_paths[1].endswith("lib_a.sh")
    assert remote_paths[2].endswith("lib_b.sh")
    assert result == remote_paths
