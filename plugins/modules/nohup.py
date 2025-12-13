#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: nohup
short_description: Starts a command in background and returns
description:
  - The M(community.openwrt.nohup) module start runs a command in a shell using OpenWRTs C(start-stop-daemon).
  - The module dispatches the command and return.
author: Markus Weippert (@gekmihesg)
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: none
  diff_mode:
    support: none
options:
  command:
    description:
      - Command to execute. Execution takes place in a shell.
    required: true
    aliases:
      - cmd
  delay:
    description:
      - Seconds to wait, before command is run.
    default: 0
notes:
  - This module does not support check_mode.
"""

EXAMPLES = r"""
- name: Wait 3 seconds, then restart network
  community.openwrt.nohup:
    command: /etc/init.d/network restart
    delay: 3
"""

RETURN = r""""""
