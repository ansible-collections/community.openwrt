#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: slurp
short_description: Slurps a file from remote OpenWrt nodes
description:
  - The M(community.openwrt.slurp) module reads a file from the OpenWrt target and encodes it in base64.
author: Markus Weippert (@gekmihesg)
extends_documentation_fragment:
  - community.openwrt.attributes
  - community.openwrt.attributes.info_module
options:
  src:
    description:
      - The file on the remote system to fetch.
      - This must be a file, not a directory.
    type: str
    required: true
    aliases:
      - path
"""

EXAMPLES = r"""
- name: Read a configuration file
  community.openwrt.slurp:
    src: /etc/config/network
  register: network_config

- name: Decode the file content
  ansible.builtin.debug:
    msg: "{{ network_config.content | b64decode }}"

- name: Fetch a file for later use
  community.openwrt.slurp:
    src: /etc/dropbear/dropbear_rsa_host_key
  register: ssh_key
"""

RETURN = r"""
source:
  description: Path to the file that was read.
  returned: always
  type: str
  sample: /etc/config/network
content:
  description: Base64 encoded content of the file.
  returned: always
  type: str
  sample: IyBUaGlzIGlzIGEgdGVzdAo=
encoding:
  description: The encoding used for the content.
  returned: always
  type: str
  sample: base64
"""
