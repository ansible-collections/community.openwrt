# Copyright (c) Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations


class ModuleDocFragment:
    DOCUMENTATION = r"""
options:
  mode:
    description:
      - Permissions for the file or directory.
      - Can be specified as an octal number (for example, V('0644'), V('1777')) or symbolic mode (like V('u+rwx')).
      - When using octal notation, quote the value to ensure it is treated as a string.
      - If not specified, permissions may be determined by the system default C(umask) or remain unchanged.
      - Not applied to symlinks when O(follow=false).
    type: str
  owner:
    description:
      - User name that should own the file or directory.
      - Passed directly to the C(chown) command.
      - If not specified, ownership is not changed.
      - Not applied to symlinks when O(follow=false).
    type: str
  group:
    description:
      - Group name that should own the file or directory.
      - Passed directly to the C(chgrp) command.
      - If not specified, group ownership is not changed.
      - Not applied to symlinks when O(follow=false).
    type: str
  follow:
    description:
      - Whether to follow symlinks when setting file attributes.
      - When V(false), symlinks are not followed and attributes are set on the link itself (where supported).
      - When V(true), attributes are set on the symlink target.
      - Affects how O(mode), O(owner), and O(group) are applied.
    type: bool
    default: false
"""
