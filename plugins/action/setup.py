# Copyright (c) 2025 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from ansible_collections.community.openwrt.plugins.plugin_utils.openwrt_action import OpenwrtActionBase

_WIRELESS_SENSITIVE_KEYS = frozenset(
    {
        "key",
        "key1",
        "key2",
        "key3",
        "key4",  # WPA PSK / WEP
        "sae_password",  # WPA3-SAE
        "password",  # EAP user password
        "auth_secret",
        "acct_secret",  # RADIUS shared secrets
        "priv_key_pwd",  # EAP private key password
    }
)


def _redact_wireless(obj):
    if isinstance(obj, dict):
        return {k: _redact_wireless(v) for k, v in obj.items() if k not in _WIRELESS_SENSITIVE_KEYS}
    if isinstance(obj, list):
        return [_redact_wireless(item) for item in obj]
    return obj


class ActionModule(OpenwrtActionBase):
    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)

        ansible_facts = result.get("ansible_facts", {})
        if "openwrt_wireless" in ansible_facts:
            ansible_facts["openwrt_wireless"] = _redact_wireless(ansible_facts["openwrt_wireless"])

        return result
