#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: sysctl
short_description: Manage sysctl entries on OpenWrt targets
description:
  - The M(community.openwrt.sysctl) module manages sysctl configuration on OpenWrt systems.
  - It can modify both the running kernel parameters and the persistent configuration file.
author: Markus Weippert (@gekmihesg)
options:
  name:
    description:
      - The sysctl key to manage.
    type: str
    required: true
    aliases:
      - key
  value:
    description:
      - The value to set for the sysctl key.
      - Required when O(state=present).
    type: str
    aliases:
      - val
  state:
    description:
      - Whether the sysctl entry should be present or absent in the configuration file.
    type: str
    choices:
      - absent
      - present
    default: present
  sysctl_file:
    description:
      - The sysctl configuration file to modify.
    type: str
    default: /etc/sysctl.conf
  sysctl_set:
    description:
      - Whether to set the value in the running kernel.
      - If V(false), only the configuration file is modified.
    type: bool
    default: false
  reload:
    description:
      - Whether to reload the sysctl configuration after making changes.
      - Only applies when O(state=present).
    type: bool
    default: true
  ignore_errors:
    description:
      - Ignore errors when the sysctl key is unknown.
    type: bool
    aliases:
      - ignoreerrors
notes:
  - This module is designed for OpenWrt devices without Python installed.
"""

EXAMPLES = r"""
- name: Enable IP forwarding
  community.openwrt.sysctl:
    name: net.ipv4.ip_forward
    value: '1'
    state: present

- name: Set kernel parameter and apply immediately
  community.openwrt.sysctl:
    name: net.ipv4.tcp_syncookies
    value: '1'
    sysctl_set: true

- name: Remove a sysctl entry
  community.openwrt.sysctl:
    name: net.ipv6.conf.all.forwarding
    state: absent

- name: Set value without reloading
  community.openwrt.sysctl:
    name: vm.swappiness
    value: '10'
    reload: false
"""

RETURN = r"""
name:
  description: The sysctl key that was managed.
  returned: always
  type: str
  sample: net.ipv4.ip_forward
value:
  description: The value of the sysctl key.
  returned: when O(state=present)
  type: str
  sample: "1"
"""
