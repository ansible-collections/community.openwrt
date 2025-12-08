#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: ping
short_description: Verify ability to communicate with OpenWrt targets
description:
  - The M(community.openwrt.ping) module tests the ability to log in to remote OpenWrt machines and execute commands.
  - This is a simple way to verify that your host is reachable and that you have valid credentials.
author: Markus Weippert (@gekmihesg)
options:
  data:
    description:
      - Data to return in the ping response.
      - The special value V(crash) causes the module to crash with an error.
    type: raw
notes:
  - This module is designed for OpenWrt devices without Python installed.
  - This module does not support check mode.
"""

EXAMPLES = r"""
- name: Test connection to OpenWrt device
  community.openwrt.ping:

- name: Test with custom data
  community.openwrt.ping:
    data: hello
"""

RETURN = r"""
ping:
  description: Response from the ping module.
  returned: always
  type: str
  sample: pong
data:
  description: The data that was sent to the module.
  returned: when O(data) is provided
  type: raw
  sample: hello
"""
