#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


DOCUMENTATION = r"""
module: uci
short_description: Controls OpenWrt UCI
description:
  - The M(community.openwrt.uci) module is a Ansible wrapper for OpenWrt's C(uci).
  - It supports all the command line functionality plus some extra commands.
author: Markus Weippert (@gekmihesg)
extends_documentation_fragment:
  - community.openwrt.attributes
attributes:
  check_mode:
    support: full
  diff_mode:
    support: full
options:
  autocommit:
    description:
      - Whether to automatically commit changes.
    type: bool
    default: false
  command:
    description:
      - C(uci) command to execute.
      - The default is V(set) if O(value) is passed, otherwise the default is V(get).
      - The V(get), V(export), and V(show) states should be factored out of this module into an C(_info) module.
    choices:
      - absent
      - add
      - add_list
      - batch
      - changes
      - commit
      - del_list
      - export
      - find
      - get
      - import
      - rename
      - reorder
      - revert
      - section
      - set
      - show
    aliases:
      - cmd
  config:
    description:
      - Config part of the O(key).
      - If not specified, extracted from O(key).
  find:
    description:
      - Value(s) to match sections against.
      - Option value to find if O(option) is set. May be list.
      - Dict of options/values if O(option) is not set. Values may be list.
      - Lists are compared in order.
      - Required when O(command=find) or O(command=section).
    aliases:
      - find_by
      - search
  keep_keys:
    description:
      - Space separated list or list of keys not in O(value) or O(find) to keep when O(replace=yes).
    aliases:
      - keep
  key:
    description:
      - The C(uci) key to operate on.
      - Takes precedence over O(config), O(section) and O(option).
      - If not specified, constructed as O(config).O(section).O(option).
  merge:
    description:
      - Whether to merge or replace when O(command=import).
    type: bool
    default: false
  name:
    description:
      - New name when O(command=rename) or O(command=add).
      - Desired name when O(command=section). If a matching section is found it is renamed, if not it is created with
        that name.
  option:
    description:
      - Option part of the O(key).
      - If not specified, extracted from O(key).
  replace:
    description:
      - When O(command=set) or O(command=section), whether to delete all options not mentioned in O(keep_keys), O(value)
        or find when O(set_find=true).
    type: bool
    default: false
  section:
    description:
      - Section part of the O(key).
      - If not specified, extracted from O(key).
  set_find:
    description:
      - When O(command=section) whether to set the options used to search a matching section in the newly created
        section when no match was found.
    type: bool
    default: false
  type:
    description:
      - Section type for O(command=section), O(command=find) and O(command=add).
      - If not specified, defaults to the value of O(section).
  unique:
    description:
      - When O(command=add_list), whether to add the value if it is already contained in the list.
    type: bool
    default: false
  value:
    description:
      - The value for various commands.
"""

EXAMPLES = r"""
# Find a section of type wifi-iface with matching name or matching attributes.
# If not found create it and set the attributes from find.
# Unconditionally set the attributes from value and delete all other options.
- community.openwrt.uci:
    command: section
    config: wireless
    type: wifi-iface
    name: ap0
    find:
      device: radio0
      ssid: My SSID
    value:
      encryption: none
    replace: yes

# Find a matching wifi-iface and delete it.
- community.openwrt.uci:
    command: absent
    config: wireless
    type: wifi-iface
    find:
      ssid: My SSID broken

# Find a matching wifi-iface and delete the options key and encryption.
- community.openwrt.uci:
    command: absent
    config: wireless
    type: wifi-iface
    find:
      ssid: My SSID public
    value:
      - key
      - encryption

# Commit changes and notify.
- community.openwrt.uci:
    cmd: commit
  notify: restart wifi
"""

RETURN = r"""
result:
  description: Output of the C(uci) command.
  returned: always
  type: str
  sample: cfg12523
result_list:
  description: The list form of result.
  returned: when O(command=get)
  type: list
  sample: ["0.pool.ntp.org", "1.pool.ntp.org"]
config:
  description: Config part of O(key).
  returned: when given
  type: str
  sample: wireless
section:
  description: Section part of O(key).
  returned: when given
  type: str
  sample: "@wifi-iface[0]"
option:
  description: Option part of O(key).
  returned: when given
  type: str
  sample: ssid
command:
  description: Command executed.
  returned: always
  type: str
  sample: section
"""
