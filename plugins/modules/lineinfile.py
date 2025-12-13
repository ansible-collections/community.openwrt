#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: lineinfile
short_description: Manage lines in text files on OpenWrt targets
description:
  - The M(community.openwrt.lineinfile) module ensures a particular line is in a file, or replaces an existing line
    using a regular expression.
  - This is useful when you want to change a single line in a file.
author: Markus Weippert (@gekmihesg)
extends_documentation_fragment:
  - community.openwrt.attributes
  - community.openwrt.attributes.files
attributes:
  check_mode:
    support: full
  diff_mode:
    support: full
options:
  path:
    description:
      - The file to modify.
    type: str
    required: true
    aliases:
      - dest
      - destfile
      - name
  line:
    description:
      - The line to insert/replace into the file.
      - Required when O(state=present).
    type: str
    aliases:
      - value
  state:
    description:
      - Whether the line should be present or absent.
    type: str
    choices:
      - absent
      - present
    default: present
  regex:
    description:
      - The regular expression to look for in every line of the file.
      - For O(state=present), the pattern to replace if found.
      - For O(state=absent), the pattern of the line(s) to remove.
    type: str
    aliases:
      - regexp
  backrefs:
    description:
      - Used with O(regex). If set, the line is inserted/replaced only if the regex matches.
      - The matched groups can be referenced in O(line) using backreferences.
    type: bool
    default: false
  insertafter:
    description:
      - Used with O(state=present).
      - If specified, the line is inserted after the last match of the specified regular expression.
      - Special values V(EOF) for end of file and V(BOF) for beginning of file.
    type: str
  insertbefore:
    description:
      - Used with O(state=present).
      - If specified, the line is inserted before the last match of the specified regular expression.
      - Special value V(BOF) for beginning of file.
    type: str
  create:
    description:
      - Create the file if it does not exist.
      - Without this option, the task fails if the file does not exist.
    type: bool
    default: false
  mode:
    description:
      - The permissions the resulting file should have.
    type: str
  owner:
    description:
      - Name of the user that should own the file.
    type: str
  group:
    description:
      - Name of the group that should own the file.
    type: str
  follow:
    description:
      - Whether to follow symlinks.
    type: bool
"""

EXAMPLES = r"""
- name: Ensure a line is present in a file
  community.openwrt.lineinfile:
    path: /etc/config/network
    line: "option dns '8.8.8.8'"

- name: Replace a line matching a pattern
  community.openwrt.lineinfile:
    path: /etc/config/system
    regex: '^\s*option hostname'
    line: "option hostname 'newname'"

- name: Remove lines matching a pattern
  community.openwrt.lineinfile:
    path: /etc/config/firewall
    regex: '^\s*option dest'
    state: absent

- name: Insert line after match
  community.openwrt.lineinfile:
    path: /etc/hosts
    line: 192.168.1.100 myhost
    insertafter: '^127.0.0.1'
"""

RETURN = r""""""
