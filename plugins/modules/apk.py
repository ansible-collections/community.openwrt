#!/usr/bin/python
# Copyright (c) 2025 Krzysztof Bialek/Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations

DOCUMENTATION = r"""
module: apk
short_description: Manage packages with apk on OpenWrt
description:
  - The M(community.openwrt.apk) module manages packages on OpenWrt using the apk package manager (available in OpenWrt 25.12+).
  - It can install and remove packages.
author: Krzysztof Bialek (@kbialek)
version_added: 0.4.0
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: full
  diff_mode:
    support: none
options:
  name:
    description:
      - Name of the package(s) to install or remove.
      - Multiple packages can be specified as a comma-separated list with no spaces, for example V(curl,wget).
    type: str
    required: true
    aliases:
      - pkg
  state:
    description:
      - Whether the package should be installed or removed.
    type: str
    choices:
      - absent
      - installed
      - present
      - removed
    default: present
  update_cache:
    description:
      - Update the package cache (C(apk update)) before performing the operation. Mutually exclusive with (O(no_cache)).
    type: bool
    default: false
  no_cache:
    description:
      - Do not use a local cache files, fetch from index directly. Mutually exclusive with (O(update_cache)).
    type: bool
    default: false
  force_broken_world:
    description:
      - Continue even if package dependencies are broken.
    type: bool
    default: false
"""

EXAMPLES = r"""
- name: Install a package
  community.openwrt.apk:
    name: vim
    state: present

- name: Remove a package
  community.openwrt.apk:
    name: vim
    state: absent

- name: Update cache and install multiple packages
  community.openwrt.apk:
    name: curl,wget
    state: present
    update_cache: true

- name: Install package without using local cache
  community.openwrt.apk:
    name: tcpdump
    state: present
    no_cache: true
"""

RETURN = r"""
stdout:
  description: apk standard output.
  returned: always
  type: str
  sample: Foo foo foo
stderr:
  description: apk standard error.
  returned: always
  type: str
  sample: ""
rc:
  description: apk return code.
  returned: always
  type: int
  sample: 0
"""
