#!/usr/bin/python
# Copyright (c) 2026 Sebastian Guarino
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: package_facts
short_description: Gather package facts in OpenWrt systems
description:
  - The M(community.openwrt.package_facts) module gathers facts about installed packages in OpenWrt systems.
  - It collects package name, version and package version of every installed package.
  - This module should be called manually by playbooks when needed. It's not part of the setup task.
author: Sebastián Guarino (@sguarin)
version_added: 1.1.0
extends_documentation_fragment:
  - community.openwrt.attributes
  - community.openwrt.attributes.facts
  - community.openwrt.attributes.facts_module
options: {}
notes:
  - Facts are returned in the C(ansible_facts) namespace (C(packages) key).
"""

EXAMPLES = r"""
- name: Gather facts from OpenWrt device
  community.openwrt.package_facts:

- name: Show installed packages
  ansible.builtin.debug:
    msg: "{{ ansible_facts['packages'] }}"
"""

RETURN = """
ansible_facts:
  description: Facts to add to ansible_facts.
  returned: always
  type: complex
  contains:
    packages:
      description:
        - Maps the package name to a non-empty list of dicts with package information.
        - Every dict in the list corresponds to one installed version of the package.
        - The fields described below are present for the package manager detected (C(apk) or C(opkg))
      returned: when operating system level package manager is auto detected succesfully.
      type: dict
      contains:
        source:
          description: The package management detected.
          type: str
          sample: apk
        name:
          description: The package name.
          type: str
          sample: zlib
        version:
          description: The version of the software.
          type: str
          sample: 1.3.1
        release:
          description: The release version of the package.
          type: str
          sample: r1
      sample:
        {
          "packages": {
            "apk-mbedtls": [
                {
                    "name": "apk-mbedtls",
                    "release": "r2",
                    "source": "apk",
                    "version": "3.0.2"
                }
            ],
            "zlib": [
                {
                    "name": "zlib",
                    "release": "r1",
                    "source": "apk",
                    "version": "1.3.1"
                }
            ]
          }
        }
"""
