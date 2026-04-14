# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from ansible_collections.community.openwrt.plugins.action.setup import (
    _WIRELESS_SENSITIVE_KEYS,
    ActionModule,
    _redact_wireless,
)


def _make_action():
    obj = object.__new__(ActionModule)
    obj._task = MagicMock()
    obj._task.action = "community.openwrt.setup"
    obj._task.async_val = 0
    obj._task.args = {}
    obj._task.get_ds.return_value = {}
    obj._connection = MagicMock()
    obj._connection._shell.join_path = MagicMock(return_value="/tmp/remote/setup.sh")
    obj._templar = MagicMock()
    obj._loader = MagicMock()
    obj._play_context = MagicMock()
    obj._shared_loader_obj = MagicMock()
    obj._make_tmp_path = MagicMock(return_value="/tmp/remote")
    obj._transfer_file = MagicMock()
    obj._fixup_perms2 = MagicMock()
    return obj


WIRELESS_WITH_SECRETS = {
    "radio0": {
        "interfaces": [
            {"config": {"mode": "ap", "ssid": "MyNet", "key": "s3cr3t", "sae_password": "sae-s3cr3t"}},
            {
                "config": {
                    "mode": "ap",
                    "ssid": "Guest",
                    "password": "guest-pass",
                    "auth_secret": "rad1us",
                    "acct_secret": "rad1us2",
                    "dae_secret": "dae-s3cr3t",
                }
            },
        ]
    },
    "radio1": {
        "interfaces": [
            {
                "config": {
                    "mode": "sta",
                    "ssid": "Upstream",
                    "key1": "wep1",
                    "key2": "wep2",
                    "key3": "wep3",
                    "key4": "wep4",
                }
            },
            {
                "config": {
                    "mode": "ap",
                    "ssid": "Corp",
                    "priv_key_pwd": "certpass",
                    "priv_key2_pwd": "certpass2",
                    "private_key_passwd": "srvkeypass",
                    "multi_ap_backhaul_key": "backhaul-s3cr3t",
                    "r0kh": "aa:bb:cc:dd:ee:ff r0kh-id s3cr3t",
                    "r1kh": "aa:bb:cc:dd:ee:ff aa:bb:cc:dd:ee:ff s3cr3t",
                }
            },
        ]
    },
}


def test_task_get_ds_api_exists():
    """Canary: get_ds() is an internal Ansible API we rely on to detect explicit no_log.
    If this fails, the Ansible core Task class has changed and the no_log check needs revisiting."""
    from ansible.playbook.base import Base

    assert callable(getattr(Base, "get_ds", None))


@pytest.mark.parametrize("sensitive_key", sorted(_WIRELESS_SENSITIVE_KEYS))
def test_redact_wireless_removes_sensitive_keys(sensitive_key):
    result = _redact_wireless(WIRELESS_WITH_SECRETS)
    configs = [iface["config"] for radio in result.values() for iface in radio["interfaces"]]
    assert all(sensitive_key not in cfg for cfg in configs)


def test_redact_wireless_preserves_other_keys():
    result = _redact_wireless(WIRELESS_WITH_SECRETS)
    configs = [iface["config"] for radio in result.values() for iface in radio["interfaces"]]
    assert all("ssid" in cfg for cfg in configs)
    assert all("mode" in cfg for cfg in configs)


def test_redact_wireless_handles_empty():
    assert _redact_wireless({}) == {}


def test_run_redacts_wireless_facts(mocker):
    action = _make_action()
    mocker.patch(
        "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action.OpenwrtActionBase.run",
        return_value={"changed": False, "ansible_facts": {"openwrt_wireless": WIRELESS_WITH_SECRETS}},
    )
    result = action.run(task_vars={})
    configs = [
        iface["config"]
        for radio in result["ansible_facts"]["openwrt_wireless"].values()
        for iface in radio["interfaces"]
    ]
    assert all(k not in cfg for cfg in configs for k in _WIRELESS_SENSITIVE_KEYS)


def test_run_expose_secrets_requires_explicit_no_log(mocker):
    action = _make_action()
    action._task.args = {"expose_secrets": True}
    action._task.get_ds.return_value = {"expose_secrets": True}  # no_log absent
    mocker.patch(
        "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action.OpenwrtActionBase.run",
        return_value={"changed": False, "ansible_facts": {"openwrt_wireless": WIRELESS_WITH_SECRETS}},
    )
    result = action.run(task_vars={})
    assert result["failed"] is True
    assert "no_log" in result["msg"]
    assert "ansible_facts" not in result


def test_run_expose_secrets_preserves_wireless_facts(mocker):
    action = _make_action()
    action._task.args = {"expose_secrets": True}
    action._task.get_ds.return_value = {"expose_secrets": True, "no_log": False}
    mocker.patch(
        "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action.OpenwrtActionBase.run",
        return_value={"changed": False, "ansible_facts": {"openwrt_wireless": WIRELESS_WITH_SECRETS}},
    )
    result = action.run(task_vars={})
    assert result["ansible_facts"]["openwrt_wireless"] == WIRELESS_WITH_SECRETS


def test_run_without_wireless_facts(mocker):
    action = _make_action()
    mocker.patch(
        "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action.OpenwrtActionBase.run",
        return_value={"changed": False, "ansible_facts": {"ansible_hostname": "router"}},
    )
    result = action.run(task_vars={})
    assert "openwrt_wireless" not in result["ansible_facts"]
