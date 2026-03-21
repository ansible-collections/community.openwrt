#!/usr/bin/python
# Copyright (c) 2026 Sebastian Hamann
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

DOCUMENTATION = r"""
module: group
version_added: "1.2.0"
short_description: Add or remove groups
description:
  - Manage presence of groups on a host.
options:
  name:
    description:
      - Name of the group to manage.
    type: str
    required: true
  gid:
    description:
      - Optional I(GID) to set for the group.
    type: int
  state:
    description:
      - Whether the group should be present or not on the remote host.
    type: str
    choices: [absent, present]
    default: present
  force:
    description:
      - Whether to delete a group even if it is the primary group of a user.
    type: bool
    default: false
  system:
    description:
      - If V(true), indicates that the group created is a system group.
    type: bool
    default: false
  non_unique:
    description:
      - This option allows to change the group ID to a non-unique value. Requires O(gid).
    type: bool
    default: false
  gid_min:
    description:
      - Sets the GID_MIN value for group creation.
    type: int
  gid_max:
    description:
      - Sets the GID_MAX value for group creation.
    type: int
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: full
  diff_mode:
    support: none
author:
  - Sebastian Hamann (@s-hamann)
"""

EXAMPLES = r"""
- name: Ensure group "somegroup" exists
  community.openwrt.group:
    name: somegroup
    state: present

- name: Ensure group "docker" exists with correct gid
  community.openwrt.group:
    name: docker
    state: present
    gid: 1750
"""

RETURN = r"""
gid:
  description: Group ID of the group.
  returned: When O(state=present)
  type: int
  sample: 1001
name:
  description: Group name.
  returned: always
  type: str
  sample: users
state:
  description: Whether the group is present or not.
  returned: always
  type: str
  sample: 'absent'
system:
  description: Whether the group is a system group or not.
  returned: When O(state=present)
  type: bool
  sample: false
"""
