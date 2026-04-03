# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from ansible_collections.community.openwrt.plugins.action.setup import ActionModule, _redact_wireless


def _make_action():
    obj = object.__new__(ActionModule)
    obj._task = MagicMock()
    obj._task.action = "community.openwrt.setup"
    obj._task.async_val = 0
    obj._task.args = {}
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
            {"config": {"mode": "ap", "ssid": "Corp", "priv_key_pwd": "certpass"}},
        ]
    },
}

SENSITIVE_KEYS = [
    "key",
    "key1",
    "key2",
    "key3",
    "key4",
    "sae_password",
    "password",
    "auth_secret",
    "acct_secret",
    "priv_key_pwd",
]


@pytest.mark.parametrize("sensitive_key", SENSITIVE_KEYS)
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
    assert all("key" not in cfg and "password" not in cfg and "psk" not in cfg for cfg in configs)


def test_run_without_wireless_facts(mocker):
    action = _make_action()
    mocker.patch(
        "ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action.OpenwrtActionBase.run",
        return_value={"changed": False, "ansible_facts": {"ansible_hostname": "router"}},
    )
    result = action.run(task_vars={})
    assert "openwrt_wireless" not in result["ansible_facts"]
