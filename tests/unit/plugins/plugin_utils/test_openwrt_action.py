# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import pytest
from unittest.mock import MagicMock, patch

from ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action import (
    ModuleNotFound,
    ModuleTransferFailed,
    OpenwrtActionBase,
)

# Path to patch os.path.exists in the module under test
_OPENWRT_ACTION_MODULE = (
    "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action"
)


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


def test_transfer_module_script_raises_when_make_tmp_path_fails(action):
    action._make_tmp_path = MagicMock(side_effect=Exception("no remote tmp"))

    with pytest.raises(ModuleTransferFailed) as exc_info:
        action._transfer_module_script("mymodule", "/some/path/mymodule.sh")
    assert "no remote tmp" in str(exc_info.value)


def test_transfer_module_script_raises_when_transfer_file_fails(action):
    action._make_tmp_path = MagicMock(return_value="/tmp/ansible-remote")
    action._connection._shell.join_path = MagicMock(return_value="/tmp/ansible-remote/mymodule.sh")
    action._transfer_file = MagicMock(side_effect=Exception("transfer error"))

    with pytest.raises(ModuleTransferFailed) as exc_info:
        action._transfer_module_script("mymodule", "/some/path/mymodule.sh")
    assert "transfer error" in str(exc_info.value)


def test_transfer_module_script_raises_when_fixup_perms_fails(action):
    action._make_tmp_path = MagicMock(return_value="/tmp/ansible-remote")
    action._connection._shell.join_path = MagicMock(return_value="/tmp/ansible-remote/mymodule.sh")
    action._transfer_file = MagicMock()
    action._fixup_perms2 = MagicMock(side_effect=Exception("permission denied"))

    with pytest.raises(ModuleTransferFailed) as exc_info:
        action._transfer_module_script("mymodule", "/some/path/mymodule.sh")
    assert "permission denied" in str(exc_info.value)


def test_transfer_module_script_wraps_original_exception(action):
    original = Exception("root cause")
    action._make_tmp_path = MagicMock(side_effect=original)

    with pytest.raises(ModuleTransferFailed) as exc_info:
        action._transfer_module_script("mymodule", "/some/path/mymodule.sh")
    assert exc_info.value.__cause__ is original
