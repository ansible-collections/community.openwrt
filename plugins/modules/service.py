#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: service
short_description: Manage services on OpenWrt targets
description:
  - The M(community.openwrt.service) module controls services on OpenWrt using init scripts.
  - It can start, stop, restart, reload services and manage their enabled state.
author: Markus Weippert (@gekmihesg)
options:
  name:
    description:
      - Name of the service.
      - Corresponds to the init script name in C(/etc/init.d/).
    type: str
    required: true
  state:
    description:
      - Desired state of the service.
    type: str
    choices:
      - reloaded
      - restarted
      - started
      - stopped
  enabled:
    description:
      - Whether the service should start on boot.
    type: bool
  pattern:
    description:
      - Pattern to search for in the process table to determine if the service is running.
      - If specified, this pattern is used with C(pgrep) instead of the init script's running command.
    type: str
"""

EXAMPLES = r"""
- name: Start the network service
  community.openwrt.service:
    name: network
    state: started

- name: Stop the firewall service
  community.openwrt.service:
    name: firewall
    state: stopped

- name: Restart the dnsmasq service
  community.openwrt.service:
    name: dnsmasq
    state: restarted

- name: Enable a service to start on boot
  community.openwrt.service:
    name: uhttpd
    enabled: true

- name: Disable a service from starting on boot
  community.openwrt.service:
    name: telnet
    enabled: false
"""

RETURN = r"""
name:
  description: The name of the service.
  returned: always
  type: str
  sample: network
state:
  description: The current state of the service.
  returned: when O(state) is specified
  type: str
  sample: started
enabled:
  description: Whether the service is enabled to start on boot.
  returned: when O(enabled) is specified
  type: str
  sample: "yes"
"""
