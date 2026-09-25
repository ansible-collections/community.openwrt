#!/usr/bin/python
# Copyright (c) 2017 Markus Weippert
# GNU General Public License v3.0 (see https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

DOCUMENTATION = r"""
module: uci
short_description: Controls OpenWrt UCI
description:
  - The M(community.openwrt.uci) module controls OpenWrt UCI through the native C(ucode) UCI bindings.
  - It supports all the command line functionality plus some extra commands.
author:
  - Markus Weippert (@gekmihesg)
  - Vladimir Ermakov (@vooon)
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
      - delete
      - ensure
      - export
      - find
      - find_all
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
  operations:
    description:
      - A list of UCI operations to execute in order using one UCI cursor.
      - Each entry accepts the same options as a standalone invocation except O(operations).
      - Per-operation results are returned in RV(operations).
      - An empty list performs no operations and reports no change.
      - Set top-level O(autocommit=true) to commit all staged changes once after the list succeeds, or include an
        operation with C(command=commit).
    type: list
    elements: dict
    version_added: "1.9.0"
  redact_keys:
    description:
      - UCI option names whose values must be hidden in diff output.
      - Changed values are represented by V(REDACTED-present) and V(REDACTED-wanted); unchanged values are
        represented by V(REDACTED).
      - A value set on an individual O(operations) entry overrides this top-level list for that operation.
    type: list
    elements: str
    version_added: "1.9.0"
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
    default: true
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
notes:
  - Since version 1.8.0, O(command=set), O(command=ensure) and O(command=section) compare the stored value
    before writing, and report RV(ignore:changed=true) only when it differs. Earlier versions reported
    RV(ignore:changed=true) on every run.
  - Starting with version 1.9.0, this module is implemented in C(ucode).
  - O(redact_keys) hides values from diffs, but does not prevent O(command=get), O(command=show), or
    O(command=export) from returning them. Use the C(no_log) task keyword when reading sensitive values.
requirements:
  - C(ucode) and C(ucode-mod-uci) on the target.
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
    replace: true

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

# Apply several changes through one UCI cursor and commit once at the end.
- community.openwrt.uci:
    autocommit: true
    operations:
      - command: set
        key: system.@system[0].hostname
        value: my-router
      - command: set
        key: network.lan.ipaddr
        value: 192.168.1.1

# Hide a password in the before/after diff.
- community.openwrt.uci:
    command: set
    key: wireless.default_radio0.key
    value: top-secret
    redact_keys:
      - key
"""

RETURN = r"""
result:
  description: Output of the C(uci) command.
  returned: always
  type: str
  sample: cfg12523
result_list:
  description:
    - The list form of C(result).
    - For O(command=find_all), this is the list of matching positional section IDs, for example V(@wifi-iface[0]).
      Named sections are returned as positional IDs.
  returned: when O(command=get) or O(command=find_all)
  type: list
  sample: ["0.pool.ntp.org", "1.pool.ntp.org"]
changes:
  description: Pending UCI changes.
  returned: when O(command=changes)
  type: dict
diff:
  description: UCI state before and after each changed operation, with options from O(redact_keys) hidden.
  returned: in diff mode when a supported operation changes state
  type: list
  elements: dict
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
operations:
  description: Result of each entry passed through O(operations), in execution order.
  returned: when O(operations) is given
  type: list
  elements: dict
"""
