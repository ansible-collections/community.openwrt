# `plugins/_facts/` — gather_facts shim

This directory is **not** a standard Ansible collection plugin directory.
It exists solely to enable transparent `gather_facts: true` support for
OpenWrt hosts.

## Why this directory exists

Ansible resolves the `gather_facts` action via the `ansible.legacy` pseudo-namespace,
which searches configurable `action_plugins` directories before falling back to
`ansible.builtin`. By placing only `gather_facts.py` here and pointing
`action_plugins` at this directory, the shim is loaded for every play without
accidentally shadowing other built-in action plugins (such as `copy`, `template`,
etc.) with their `community.openwrt` counterparts.

## Required configuration

In your `ansible.cfg`, add this directory to the `action_plugins` search path:

```ini
[defaults]
action_plugins = /path/to/ansible_collections/community/openwrt/plugins/_facts
```

Or using the installed collection path:

```ini
[defaults]
action_plugins = ~/.ansible/collections/ansible_collections/community/openwrt/plugins/_facts
```

## Per-host opt-in

The shim only intercepts fact gathering for hosts that have the variable
`openwrt_gather_facts: true` set (for example in `group_vars/` or `host_vars/`).
All other hosts pass through to the standard `ansible.builtin.gather_facts`
unchanged.
