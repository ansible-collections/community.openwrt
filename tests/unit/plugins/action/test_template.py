# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from unittest.mock import MagicMock

from ansible.errors import AnsibleAction, AnsibleActionFail, AnsibleFileNotFound
from ansible.plugins.action.template import ActionModule as CoreTemplateActionModule

from ansible_collections.community.openwrt.plugins.action.template import ActionModule


def _make_action():
    obj = object.__new__(ActionModule)
    obj._shared_loader_obj = MagicMock()
    return obj


def test_missing_src_returns_failed_result_instead_of_raising(mocker):
    """ansible-core >= 2.19 lets AnsibleFileNotFound escape run(); it must be turned into a normal result."""
    mocker.patch.object(
        CoreTemplateActionModule,
        "run",
        side_effect=AnsibleFileNotFound(file_name="missing.j2", paths=["/templates/missing.j2"]),
    )
    action = _make_action()

    result = action.run(task_vars={})

    assert result["failed"] is True
    assert "missing.j2" in result["msg"]


def test_ansible_action_fail_result_is_preserved(mocker):
    """An AnsibleActionFail raised by core must come back as its own contributed result dict."""
    mocker.patch.object(CoreTemplateActionModule, "run", side_effect=AnsibleActionFail("src and dest are required"))
    action = _make_action()

    result = action.run(task_vars={})

    assert result == {"failed": True, "msg": "src and dest are required"}


def test_bare_ansible_action_without_msg_falls_back_to_exception_text(mocker):
    """A bare AnsibleAction contributes no "msg" of its own; some platforms have been observed
    to raise AnsibleActionFail with a result lacking "msg" too, so the exception's own text
    must still surface in the result either way."""
    mocker.patch.object(CoreTemplateActionModule, "run", side_effect=AnsibleAction("could not find src=missing.j2"))
    action = _make_action()

    result = action.run(task_vars={})

    assert "could not find src=missing.j2" in result["msg"]


def test_generic_exception_is_converted_to_failed_result(mocker):
    """Any other exception escaping core's run() must also be converted, not raised."""
    mocker.patch.object(CoreTemplateActionModule, "run", side_effect=ValueError("boom"))
    action = _make_action()

    result = action.run(task_vars={})

    assert result == {"failed": True, "msg": "boom"}


def test_successful_result_is_returned_unchanged(mocker):
    """When core's run() succeeds normally, its result dict must be passed through untouched."""
    mocker.patch.object(CoreTemplateActionModule, "run", return_value={"changed": True, "dest": "/etc/config"})
    action = _make_action()

    result = action.run(task_vars={})

    assert result == {"changed": True, "dest": "/etc/config"}
