#!/usr/bin/python
# Copyright (c) 2026, Ilya Bogdanov (@zeerayne)
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
---
module: template
short_description: Template a file out to remote OpenWrt target
options:
  follow:
    description:
    - Determine whether symbolic links should be followed.
    - When set to V(true) symbolic links will be followed, if they exist.
    - When set to V(false) symbolic links will not be followed.
    type: bool
    default: no
seealso:
- module: community.openwrt.copy
author:
- Ilya Bogdanov (@zeerayne)
extends_documentation_fragment:
- community.openwrt.attributes
- community.openwrt.attributes.files
- backup
- community.openwrt.file_common_arguments
- template_common
- validate
attributes:
    check_mode:
      support: full
    diff_mode:
      support: full
"""

EXAMPLES = r"""
- name: Template a file to /etc/file.conf
  ansible.builtin.template:
    src: /mytemplates/foo.j2
    dest: /etc/file.conf

- name: Copy a new sudoers file into place, after passing validation with visudo
  ansible.builtin.template:
    src: /mine/sudoers
    dest: /etc/sudoers
    validate: /usr/sbin/visudo -cf %s
"""

RETURN = r"""
dest:
    description: Destination file/path, equal to the value passed to I(dest).
    returned: success
    type: str
    sample: /path/to/file.txt
md5sum:
    description: MD5 checksum of the rendered file
    returned: changed
    type: str
    sample: d41d8cd98f00b204e9800998ecf8427e
src:
    description: Source file used for the copy on the target machine.
    returned: changed
    type: str
    sample: /home/httpd/.ansible/tmp/ansible-tmp-1423796390.97-147729857856000/source
"""
