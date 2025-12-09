#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: file
short_description: Manage files and file properties on OpenWrt targets
description:
  - The M(community.openwrt.file) module sets attributes of files, symlinks, and directories.
  - It can also create or remove files, directories, and symbolic/hard links.
author: Markus Weippert (@gekmihesg)
options:
  path:
    description:
      - Path to the file being managed.
    type: str
    required: true
    aliases:
      - dest
      - name
  state:
    description:
      - Desired state of the file.
      - If not specified, defaults to V(file) if the path is a file, V(directory) if O(recurse) is set, or the current
        state otherwise.
    type: str
    choices:
      - absent
      - directory
      - file
      - hard
      - link
      - touch
  src:
    description:
      - Path of the file to link to.
      - Required for O(state=link) and O(state=hard).
      - If not specified for links, the realpath of O(path) is used.
    type: str
  force:
    description:
      - Force creation of symlinks when the target does not exist.
      - Force conversion between different link types.
    type: bool
    default: false
  recurse:
    description:
      - Recursively set the specified file attributes on directory contents.
      - Only works with O(state=directory).
    type: bool
    default: false
  follow:
    description:
      - Whether to follow symlinks.
    type: bool
  mode:
    description:
      - The permissions the resulting file or directory should have.
    type: str
  owner:
    description:
      - Name of the user that should own the file/directory.
    type: str
  group:
    description:
      - Name of the group that should own the file/directory.
    type: str
  original_basename:
    description:
      - Original basename to use when O(path) is a directory.
    type: str
    aliases:
      - _original_basename
  diff_peek:
    description:
      - Internal parameter for diff operations.
    type: str
"""

EXAMPLES = r"""
- name: Create a directory
  community.openwrt.file:
    path: /etc/config/custom
    state: directory
    mode: '0755'

- name: Create a symbolic link
  community.openwrt.file:
    src: /etc/config/network
    path: /tmp/network.link
    state: link

- name: Remove a file
  community.openwrt.file:
    path: /tmp/tempfile
    state: absent

- name: Touch a file
  community.openwrt.file:
    path: /tmp/touched
    state: touch
"""

RETURN = r"""
path:
  description: Path to the file or directory.
  returned: always
  type: str
  sample: /etc/config/network
state:
  description: The state of the file or directory.
  returned: always
  type: str
  sample: file
appears_binary:
  description: Whether the file appears to be binary.
  returned: when O(diff_peek) is specified
  type: bool
  sample: false
"""
