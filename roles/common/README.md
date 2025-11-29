# community.openwrt.common

Common handlers and utilities for the OpenWRT collection.

## Purpose

This role provides common handlers that can be used across the collection by making it a dependency in other roles.

## Available Handlers

- `Setup wifi` - Initialize WiFi using `/sbin/wifi`
- `Reload wifi` - Reload WiFi configuration using `/sbin/wifi reload`
- `Restart network` - Restart network services using `/etc/init.d/network restart`
- `Wait for connection` - Automatically wait for connection after network changes (listens to the above handlers)

## Usage

Add this role as a dependency in your role's `meta/main.yml`:

```yaml
dependencies:
  - role: community.openwrt.common
```

Then you can notify the handlers from your tasks:

```yaml
- name: Update WiFi configuration
  community.openwrt.uci:
    command: set
    key: wireless.@wifi-iface[0].ssid
    value: "MySSID"
  notify: Reload wifi
```
