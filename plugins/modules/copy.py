#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# Copyright (c) 2025 Alexei Znamensky
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: copy
short_description: Copy files to remote OpenWRT devices
description:
  - The M(community.openwrt.copy) module copies a file from the Ansible controller to remote OpenWRT devices.
  - The C(content) parameter supports Jinja2 variable interpolation.
author:
  - Markus Weippert (@gekmihesg)
  - Alexei Znamensky (@russoz)
extends_documentation_fragment:
  - community.openwrt.attributes
  - community.openwrt.attributes.files
attributes:
  check_mode:
    support: full
  diff_mode:
    support: full
  safe_file_operations:
    support: full
options:
  src:
    description:
      - Local path to a file to copy to the remote server.
      - Can be absolute or relative.
      - When relative, the file is searched in the C(files/) directory of the role or playbook.
      - Only regular files are supported. Directories cannot be copied recursively.
      - Do not specify together with O(content) (only one is used if both are provided).
    type: path
  content:
    description:
      - When used instead of O(src), sets the contents of a file directly to the specified value.
      - Works only when O(dest) is a file. Creates the file if it does not exist.
      - Do not specify together with O(src) (only one is used if both are provided).
    type: str
  dest:
    description:
      - Remote absolute path where the file is copied to.
      - If O(dest) is a directory, the file is copied into that directory using the source file name.
      - If O(dest) ends with "/", it is treated as a directory and is created if it does not exist.
      - If O(dest) is a relative path, the starting directory is determined by the remote host.
      - The parent directory of O(dest) must exist or the task fails.
    type: path
    required: true
  backup:
    description:
      - Create a backup file including the timestamp information so you can get the original file back if you clobbered
        it incorrectly.
    type: bool
    default: false
  force:
    description:
      - Determines whether the remote file must always be replaced.
      - If V(true), the remote file is replaced when contents are different from the source.
      - If V(false), the file is only transferred if the destination does not exist.
    type: bool
    default: true
    aliases:
      - thirsty
  mode:
    description:
      - Permissions of the destination file or directory.
      - Can be specified as an octal number (for example, V('0644'), V('1777')) or symbolic mode (like V('u+rwx')).
      - When using octal notation, quote the value to ensure it is treated as a string.
      - The module attempts to convert numeric mode values to 4-digit octal format.
      - If not specified, the system default C(umask) determines permissions for new files.
      - For existing files, permissions remain unchanged unless O(mode) is explicitly set.
      - Not applied to symlinks when O(follow=false).
    type: str
  owner:
    description:
      - User name that should own the file.
      - Passed directly to the C(chown) command.
      - If not specified, ownership is not changed.
      - Not applied to symlinks when O(follow=false).
    type: str
  group:
    description:
      - Group name that should own the file.
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
  directory_mode:
    description:
      - Permissions to set on directories that are created during the copy operation.
      - Used when O(dest) ends with "/" and the directory structure needs to be created.
      - Follows the same format rules as O(mode).
      - If not specified, directories are created with system default permissions.
    type: str
  validate:
    description:
      - Command to run to validate the file before copying it into place.
      - The file path is substituted for C(%s) in the command.
      - The command must include C(%s) or the validation fails.
      - The command is executed through C(printf) substitution, so shell features like pipes do not work.
      - If the validation command fails, the copy operation is aborted.
    type: str
notes:
  - This module does not support recursive directory copy. Only regular files can be copied.
  - Supports C(check_mode).
"""

EXAMPLES = r"""
- name: Copy file with owner and permissions
  community.openwrt.copy:
    src: /srv/myfiles/foo.conf
    dest: /etc/foo.conf
    owner: root
    group: root
    mode: '0644'

- name: Copy file from controller, creating backup
  community.openwrt.copy:
    src: /mine/ntp.conf
    dest: /etc/ntp.conf
    owner: root
    group: root
    mode: '0644'
    backup: true

- name: Copy inline content to file
  community.openwrt.copy:
    content: |
      # Managed by Ansible
      option enabled '1'
      option hostname 'openwrt'
    dest: /etc/config/system
    mode: '0644'

- name: Copy file only if it does not exist
  community.openwrt.copy:
    src: /srv/myfiles/foo.conf
    dest: /etc/foo.conf
    force: false

- name: Copy file and validate
  community.openwrt.copy:
    src: /etc/uci-defaults/template
    dest: /etc/uci-defaults/custom
    validate: sh -n %s

- name: Copy file from Ansible files directory
  community.openwrt.copy:
    src: myconfig.txt
    dest: /etc/config/myapp
    mode: '0600'
"""

RETURN = r"""
dest:
  description: Destination file/path.
  returned: success
  type: str
  sample: /etc/foo.conf
src:
  description:
    - Source file used for the copy on the target machine.
    - After the action plugin transfers the file, this is the path on the remote device.
  returned: changed
  type: str
  sample: /tmp/.ansible/tmp/source
md5sum:
  description: MD5 checksum of the source file.
  returned: when supported
  type: str
  sample: 2a5aeecc61dc98c4d780b14b330e3282
checksum:
  description: SHA1 checksum of the source file.
  returned: success
  type: str
  sample: 6e642bb8dd5c2e027bf21dd923337cbb4214f827
backup_file:
  description: Name of backup file created.
  returned: changed and if backup=true
  type: str
  sample: /etc/foo.conf.2025-11-30@10:30:15~
state:
  description: State of the target file after execution.
  returned: success
  type: str
  sample: file
"""
