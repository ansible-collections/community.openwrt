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
        "dae_secret",  # RADIUS DAE shared secret
        "priv_key_pwd",
        "priv_key2_pwd",  # EAP private key passphrases
        "private_key_passwd",  # hostapd server private key passphrase
        "multi_ap_backhaul_key",  # Multi-AP backhaul key
        "r0kh",  # 802.11r roaming key holder 0 (contains shared keys)
        "r1kh",  # 802.11r roaming key holder 1 (contains shared keys)
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
        expose_secrets = self._task.args.get("expose_secrets", False)

        # get_ds() returns the raw parsed task dict, which only contains keys the user
        # explicitly wrote — unlike task_vars, which has no_log already resolved to its
        # default (False) and cannot distinguish "set" from "not set".
        if expose_secrets and "no_log" not in (self._task.get_ds() or {}):
            return {"failed": True, "msg": "expose_secrets=true requires an explicit no_log setting on the task"}

        result = super().run(tmp, task_vars)

        if not expose_secrets:
            ansible_facts = result.get("ansible_facts", {})
            if "openwrt_wireless" in ansible_facts:
                ansible_facts["openwrt_wireless"] = _redact_wireless(ansible_facts["openwrt_wireless"])

        return result
