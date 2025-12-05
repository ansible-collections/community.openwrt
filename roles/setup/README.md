# Ansible Role: community.openwrt.setup

## Description

This role performs essential initialization tasks for using the `community.openwrt` collection:

1. **Configures Ansible connection settings**:

   - Sets `ansible_remote_tmp` to `/tmp` to avoid flash wear on OpenWRT devices
   - Configures `ansible_ssh_transfer_method` to use SCP instead of SFTP (OpenWRT does not have SFTP by default)
   - Sets appropriate SSH connection options

2. **Installs recommended packages** (optional):

   - `coreutils-base64` - For Base64 encoding/decoding
   - `coreutils-md5sum` - For MD5 checksums
   - `coreutils-sha1sum` - For SHA1 checksums

   These packages are required for some collection modules to function properly (e.g., the `fetch` module needs SHA1 for checksum validation).

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Whether to install recommended packages for better module compatibility
openwrt_install_recommended_packages: true

# Whether to wait for connection after network/wifi restart
openwrt_wait_for_connection: true
openwrt_wait_for_connection_timeout: 600

# Use SCP instead of SFTP (OpenWRT doesn't have SFTP by default)
openwrt_scp_if_ssh: true

# Use /tmp for remote temporary files to avoid flash wear
openwrt_remote_tmp: /tmp
```

## Example Playbook

```yaml
---
- hosts: openwrt_devices
  gather_facts: false
  roles:
    - community.openwrt.setup
  tasks:
    - name: Gather OpenWRT facts
      community.openwrt.setup:

    - name: Install a package
      community.openwrt.opkg:
        name: luci
        state: present

    - name: Configure UCI settings
      community.openwrt.uci:
        command: set
        key: system.@system[0].hostname
        value: myrouter
```

## Handlers

This role provides handlers for common OpenWRT operations:

- `Setup wifi` - Runs `/sbin/wifi` to setup WiFi
- `Reload wifi` - Runs `/sbin/wifi reload` to reload WiFi configuration
- `Restart network` - Restarts the network service
- `Wait for connection` - Waits for the device to come back online after network changes

Example usage:

```yaml
- name: Configure wireless
  community.openwrt.uci:
    command: set
    key: wireless.radio0.channel
    value: "6"
  notify: Reload wifi
```

## License

GPL-3.0-or-later

## Author Information

This role is part of the `community.openwrt` collection.

Original role by Markus Weippert (@gekmihesg)
Adapted for collection by Alexei Znamensky (@russoz)
