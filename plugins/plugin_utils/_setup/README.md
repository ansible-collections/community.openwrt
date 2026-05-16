<!--
Copyright (c) Ansible Project
GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
SPDX-License-Identifier: GPL-3.0-or-later
-->

# `plugins/plugin_utils/_setup/` — gather_facts shim

Contains `gather_facts.py`, a shim that enables transparent `gather_facts: true`
support for OpenWrt hosts by redirecting fact collection to `community.openwrt.setup`.

## Why this directory exists

Ansible resolves the `gather_facts` action through the `ansible.legacy` pseudo-namespace,
which searches the directories listed in `action_plugins` before falling back to
`ansible.builtin`. Action plugins placed in a collection's `plugins/action/` directory
are only reachable as `<namespace>.<collection>.<name>` — they cannot override
`ansible.legacy.gather_facts`.

This directory is therefore kept separate and added to the `action_plugins` search path
explicitly. Isolating it to `_setup/` (rather than adding all of `plugins/plugin_utils/`)
ensures only the shim is exposed, without accidentally shadowing any other built-in
action plugins.

## Required configuration

Add this directory to the `action_plugins` search path in `ansible.cfg`:

```ini
[defaults]
action_plugins = ~/.ansible/collections/ansible_collections/community/openwrt/plugins/plugin_utils/_setup
```

## Per-host opt-in

The shim only intercepts fact gathering for hosts that have `openwrt_gather_facts: true`
set (for example in `group_vars/` or `host_vars/`). All other hosts fall through to the
standard `ansible.builtin.gather_facts` unchanged.
