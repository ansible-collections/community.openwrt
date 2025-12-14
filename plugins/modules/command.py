#!/usr/bin/python
# Copyright (c) 2021 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: command
short_description: Execute commands on OpenWrt targets
description:
  - The M(community.openwrt.command) module runs a command on the remote OpenWrt device.
  - The command is executed directly or through a shell depending on the O(uses_shell) parameter.
  - This module does not support check mode.
author: Markus Weippert (@gekmihesg)
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: none
  diff_mode:
    support: none
options:
  cmd:
    description:
      - The command to execute.
    type: str
    required: true
    aliases:
      - raw_params
      - _raw_params
  uses_shell:
    description:
      - Whether to execute the command through a shell.
      - If V(false), the command is executed directly.
      - If V(true), the command is executed through the shell specified in O(executable).
    type: bool
    default: false
    aliases:
      - _uses_shell
  chdir:
    description:
      - Change into this directory before running the command.
    type: str
  executable:
    description:
      - The shell to use when O(uses_shell) is V(true).
    type: str
    default: /bin/sh
  creates:
    description:
      - A filename or glob pattern.
      - If it already exists, the command does not run.
    type: str
  removes:
    description:
      - A filename or glob pattern.
      - If it does not exist, the command does not run.
    type: str
"""

EXAMPLES = r"""
- name: Run a simple command
  community.openwrt.command:
    cmd: uptime

- name: Run a command with arguments
  community.openwrt.command:
    cmd: ls -la /etc

- name: Change directory before running command
  community.openwrt.command:
    cmd: pwd
    chdir: /tmp

- name: Only run if file does not exist
  community.openwrt.command:
    cmd: touch /tmp/myfile
    creates: /tmp/myfile
"""

RETURN = r"""
cmd:
  description: The command executed.
  returned: always
  type: str
  sample: /usr/bin/uptime
stdout:
  description: The command standard output.
  returned: always
  type: str
  sample: Foo foo foo
stderr:
  description: The command standard error.
  returned: always
  type: str
  sample: ""
rc:
  description: The command return code.
  returned: always
  type: int
  sample: 0
start:
  description: The command start time.
  returned: always
  type: str
  sample: "2025-12-05 10:15:23.000000"
end:
  description: The command end time.
  returned: always
  type: str
  sample: "2025-12-05 10:15:25.000000"
delta:
  description: The command execution time.
  returned: always
  type: str
  sample: "0:00:02.000000"
"""
