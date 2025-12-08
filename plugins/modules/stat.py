#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: stat
short_description: Retrieve file or file system status on OpenWrt targets
description:
  - The M(community.openwrt.stat) module retrieves facts about files similar to the Linux stat command.
  - It returns detailed information about file properties including permissions, ownership, size, and timestamps.
author: Markus Weippert (@gekmihesg)
options:
  path:
    description:
      - The full path of the file/directory to get the facts of.
    type: str
    required: true
  checksum_algorithm:
    description:
      - Algorithm to use for checksumming the file.
    type: str
    choices:
      - md5
      - sha1
      - sha224
      - sha256
      - sha384
      - sha512
    default: sha1
    aliases:
      - checksum_algo
      - checksum
  get_checksum:
    description:
      - Whether to get the checksum of the file.
      - Uses the algorithm specified in O(checksum_algorithm).
    type: bool
    default: true
  get_md5:
    description:
      - Whether to get the MD5 checksum of the file.
    type: bool
    default: true
  get_mime:
    description:
      - Whether to get the MIME type of the file.
      - Note that this is not fully implemented and returns V(unknown).
    type: bool
    default: true
  follow:
    description:
      - Whether to follow symlinks.
    type: bool
notes:
  - This module is designed for OpenWrt devices without Python installed.
"""

EXAMPLES = r"""
- name: Get stats of a file
  community.openwrt.stat:
    path: /etc/config/network
  register: network_stat

- name: Check if file exists
  community.openwrt.stat:
    path: /tmp/myfile
  register: file_check

- name: Get file checksum
  community.openwrt.stat:
    path: /etc/config/system
    checksum_algorithm: sha256
  register: file_hash

- name: Fail if path does not exist
  community.openwrt.stat:
    path: /etc/important_file
  register: stat_result
  failed_when: not stat_result.stat.exists
"""

RETURN = r"""
stat:
  description: Dictionary containing all file stat information.
  returned: always
  type: dict
  contains:
    path:
      description: The full path to the file.
      returned: always
      type: str
      sample: /etc/config/network
    exists:
      description: Whether the file exists.
      returned: always
      type: bool
      sample: true
    size:
      description: Size of the file in bytes.
      returned: when file exists
      type: int
      sample: 1024
    mode:
      description: Unix permissions of the file in octal.
      returned: when file exists
      type: str
      sample: "0644"
    uid:
      description: Numeric user ID of the owner.
      returned: when file exists
      type: int
      sample: 0
    gid:
      description: Numeric group ID of the owner.
      returned: when file exists
      type: int
      sample: 0
    pw_name:
      description: User name of the owner.
      returned: when file exists
      type: str
      sample: root
    gr_name:
      description: Group name of the owner.
      returned: when file exists
      type: str
      sample: root
    mtime:
      description: Last modification time in seconds since epoch.
      returned: when file exists
      type: int
      sample: 1701788400
    ctime:
      description: Last change time in seconds since epoch.
      returned: when file exists
      type: int
      sample: 1701788400
    inode:
      description: Inode number of the file.
      returned: when file exists
      type: int
      sample: 12345
    nlink:
      description: Number of hard links to the file.
      returned: when file exists
      type: int
      sample: 1
    dev:
      description: Device identifier.
      returned: when file exists
      type: int
    isdir:
      description: Whether the path is a directory.
      returned: when file exists
      type: bool
      sample: false
    isreg:
      description: Whether the path is a regular file.
      returned: when file exists
      type: bool
      sample: true
    islnk:
      description: Whether the path is a symbolic link.
      returned: when file exists
      type: bool
      sample: false
    issock:
      description: Whether the path is a socket.
      returned: when file exists
      type: bool
      sample: false
    isblk:
      description: Whether the path is a block device.
      returned: when file exists
      type: bool
      sample: false
    ischr:
      description: Whether the path is a character device.
      returned: when file exists
      type: bool
      sample: false
    isfifo:
      description: Whether the path is a FIFO.
      returned: when file exists
      type: bool
      sample: false
    isuid:
      description: Whether the file is owned by the current user.
      returned: when file exists
      type: bool
      sample: true
    isgid:
      description: Whether the file is owned by the current group.
      returned: when file exists
      type: bool
      sample: true
    readable:
      description: Whether the file is readable by the current user.
      returned: when file exists
      type: bool
      sample: true
    writeable:
      description: Whether the file is writeable by the current user.
      returned: when file exists
      type: bool
      sample: true
    executable:
      description: Whether the file is executable by the current user.
      returned: when file exists
      type: bool
      sample: false
    rusr:
      description: Whether the owner has read permission.
      returned: when file exists
      type: bool
      sample: true
    wusr:
      description: Whether the owner has write permission.
      returned: when file exists
      type: bool
      sample: true
    xusr:
      description: Whether the owner has execute permission.
      returned: when file exists
      type: bool
      sample: false
    rgrp:
      description: Whether the group has read permission.
      returned: when file exists
      type: bool
      sample: true
    wgrp:
      description: Whether the group has write permission.
      returned: when file exists
      type: bool
      sample: false
    xgrp:
      description: Whether the group has execute permission.
      returned: when file exists
      type: bool
      sample: false
    roth:
      description: Whether others have read permission.
      returned: when file exists
      type: bool
      sample: true
    woth:
      description: Whether others have write permission.
      returned: when file exists
      type: bool
      sample: false
    xoth:
      description: Whether others have execute permission.
      returned: when file exists
      type: bool
      sample: false
    md5:
      description: MD5 hash of the file.
      returned: when O(get_md5=true) and file is readable
      type: str
      sample: 9a8ad92c50cae39aa2c5604fd0ab6d8c
    checksum:
      description: Hash of the file using the specified algorithm.
      returned: when O(get_checksum=true) and file is readable
      type: str
      sample: 4e1243bd22c66e76c2ba9eddc1f91394e57f9f83
    charset:
      description: Character set of the file.
      returned: when file exists
      type: str
      sample: unknown
    mime_type:
      description: MIME type of the file.
      returned: when file exists
      type: str
      sample: unknown
    lnk_source:
      description: Original path when O(follow=true) and path is a symlink.
      returned: when following a symlink
      type: str
      sample: /tmp/link
"""
