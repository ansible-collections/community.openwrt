#!/usr/bin/python
# Copyright (c) 2026 Alexei Znamensky
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

DOCUMENTATION = r"""
module: wait_for_connection
short_description: Waits until an OpenWrt device is reachable/usable
description:
  - Waits for a total of O(timeout) seconds.
  - Retries the transport connection after a timeout of O(connect_timeout).
  - Tests the transport connection every O(sleep) seconds.
  - Uses M(community.openwrt.ping) to verify end-to-end connectivity without requiring Python on the target.
author:
  - Alexei Znamensky (@russoz)
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: none
  diff_mode:
    support: none
options:
  connect_timeout:
    description:
      - Maximum number of seconds to wait for a connection to happen before closing and retrying.
    type: int
    default: 5
  delay:
    description:
      - Number of seconds to wait before starting to poll.
    type: int
    default: 0
  sleep:
    description:
      - Number of seconds to sleep between checks.
    type: int
    default: 1
  timeout:
    description:
      - Maximum number of seconds to wait for.
    type: int
    default: 600
seealso:
  - module: ansible.builtin.wait_for_connection
  - module: ansible.builtin.wait_for
  - module: community.openwrt.ping
"""

EXAMPLES = r"""
- name: Wait for OpenWrt device to become reachable
  community.openwrt.wait_for_connection:

- name: Wait up to 5 minutes, starting checks after 10 seconds
  community.openwrt.wait_for_connection:
    delay: 10
    timeout: 300
"""

RETURN = r"""
elapsed:
  description: The number of seconds that elapsed waiting for the connection to appear.
  returned: always
  type: float
  sample: 23.1
"""
