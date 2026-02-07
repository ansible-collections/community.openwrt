#!/usr/bin/python
# Copyright (c) 2026 Ilya Bogdanov
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: tempfile
short_description: Creates temporary files and directories on OpenWrt nodes
description:
  - The M(community.openwrt.tempfile) module creates temporary files and directories on the OpenWrt target.
author: Ilya Bogdanov (@zeerayne)
version_added: 1.1.0
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: full
  diff_mode:
    support: none
options:
  state:
    description:
      - Whether to create a file or a directory.
    type: str
    choices: [ file, directory ]
    default: file
  path:
    description:
      - Location where the temporary file or directory should be created.
    type: path
    default: /tmp
  prefix:
    description:
      - Prefix of the file or directory name.
    type: str
    default: ansible
notes:
  - This module always returns C(changed=true) because it creates a new temporary file or directory each time it runs.
"""

EXAMPLES = r"""
- name: Create temporary file
  community.openwrt.tempfile:
    state: file
  register: temp_file_1

- name: Create temporary directory with `build` prefix
  community.openwrt.tempfile:
    state: directory
    prefix: build
  register: temp_dir_1
"""

RETURN = r"""
path:
  description: The absolute path to the created file or directory.
  returned: success
  type: str
  sample: /tmp/ansible.bMlvdk
"""
