#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

DOCUMENTATION = r"""
module: setup
short_description: Gather facts about OpenWrt systems
description:
  - The M(community.openwrt.setup) module gathers facts about OpenWrt systems.
  - It collects system information including distribution details, hostname, network interfaces, services, and device
    information through ubus.
  - This module is automatically called by playbooks to gather useful variables about remote hosts.
author: Markus Weippert (@gekmihesg)
extends_documentation_fragment:
  - community.openwrt.attributes
  - community.openwrt.attributes.facts
  - community.openwrt.attributes.facts_module
options:
  expose_secrets:
    description:
      - When V(true), sensitive wireless credentials are included in the C(openwrt_wireless) fact.
      - By default these values are redacted to prevent accidental leakage in logs or task output.
      - When set to V(true), the task must also have an explicit C(no_log) setting (V(true) or V(false));
        omitting C(no_log) is treated as an error to ensure a conscious decision is made about logging.
      - See L(OpenWrt wireless configuration, https://openwrt.org/docs/guide-user/network/wifi/basic) for the full list
        of wireless options; the ones treated as secrets by this module are documented in the notes below.
    type: bool
    default: false
    version_added: "1.3.0"
notes:
  - This module gathers OpenWrt-specific facts including C(ubus) data for network interfaces, devices, services, and
    system information.
  - Facts are returned in the C(ansible_facts) namespace.
  - The fact C(ansible_date_time) was added in community.openwrt 1.1.0.
  - The facts C(ansible_date_time.iso8601_micro) and C(ansible_date_time.iso8601_basic) are meant to include
    microseconds, but the busybox implementation of C(date) does not provide time with that precision, so those facts
    are reported with V(000000) as the value for the microseconds fraction.
  - B(Note:) If you install the package C(coreutils-date), M(community.openwrt.setup) generates the actual microseconds
    for C(ansible_date_time) factoids.
  - In M(ansible.builtin.setup), the fact C(ansible_date_time.epoch_int) is the epoch number, transformed to C(int), and
    then back to C(str), which is ineffective in a shell script. The fact is provided to ensure compatibility with the
    standard module, but its value is always the same as of C(ansible_date_time.epoch).
  - Conversely, C(ansible_date_time.tz_dst) is obtained in the standard module through an internal Python function, so
    in order to provide compatibility, that fact is returned by M(community.openwrt.setup) with the exact same value as
    C(ansible_date_time.tz).
  - Unless O(expose_secrets=true) is set, the following wireless credential fields are redacted from
    C(openwrt_wireless) facts - C(key), C(key1)–C(key4) (WPA PSK / WEP keys); C(sae_password) (WPA3-SAE);
    C(password) (EAP); C(auth_secret), C(acct_secret), C(dae_secret) (RADIUS shared secrets);
    C(priv_key_pwd), C(priv_key2_pwd), C(private_key_passwd) (private key passphrases);
    C(multi_ap_backhaul_key) (Multi-AP backhaul); C(r0kh), C(r1kh) (802.11r roaming key holders).
seealso:
  - name: OpenWrt wireless configuration reference
    description: UCI options for wireless interfaces, including all security and encryption parameters.
    link: https://openwrt.org/docs/guide-user/network/wifi/basic
"""

EXAMPLES = r"""
- name: Gather facts from OpenWrt device
  community.openwrt.setup:

- name: Show distribution version
  ansible.builtin.debug:
    msg: "{{ ansible_distribution_version }}"

- name: Gather facts including wireless credentials (handle with care)
  community.openwrt.setup:
    expose_secrets: true
  no_log: true
"""

RETURN = r"""
ansible_facts:
  description: Facts gathered from the OpenWrt system.
  returned: always
  type: dict
  contains:
    ansible_hostname:
      description: The hostname of the system.
      returned: always
      type: str
      sample: router
    ansible_distribution:
      description: The distribution name.
      returned: always
      type: str
      sample: OpenWrt
    ansible_distribution_version:
      description: The distribution version.
      returned: always
      type: str
      sample: 25.12.1
    ansible_distribution_major_version:
      description: The major version of the distribution.
      returned: always
      type: str
      sample: "25"
    ansible_distribution_release:
      description: The distribution release codename.
      returned: always
      type: str
      sample: ""
    ansible_os_family:
      description: The OS family.
      returned: always
      type: str
      sample: OpenWrt
    ansible_is_chroot:
      description: Whether the system is running in a chroot.
      returned: always
      type: bool
      sample: false
    ansible_date_time:
      description: System date and time.
      returned: always
      type: dict
    openwrt_info:
      description: System information from C(ubus).
      returned: when available
      type: dict
    openwrt_devices:
      description: Network device status from C(ubus).
      returned: when available
      type: dict
    openwrt_services:
      description: Service list from C(ubus).
      returned: when available
      type: dict
    openwrt_board:
      description: Board information from C(ubus).
      returned: when available
      type: dict
    openwrt_wireless:
      description: Wireless status from C(ubus). Sensitive credential fields are redacted unless O(expose_secrets=true).
      returned: when available
      type: dict
    openwrt_interfaces:
      description: Network interface status from C(ubus).
      returned: when available
      type: dict
"""
