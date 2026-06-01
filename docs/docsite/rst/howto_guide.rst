..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.howto_guide:


Community OpenWrt How-To Guide
==============================

Welcome to the Community OpenWrt How-To Guide! This is a collection of recipes that will help you
using the ``community.openwrt`` role in real world scenarios.

Most OpenWrt devices have a very small footprint and there is no space available to install Python. Based on this constraint, virtually all of the standard Ansible modules are not available.

It is a design rule of ``community.openwrt`` not to require Python, rather providing modules based on shell scripts (``/bin/sh``) instead.

Also by the nature of OpenWrt and its CLI-based ``uci`` tool, you need to be very familiar how
this ecosystem works. Even the creation of a Wifi passwort or a simple forwarding rule can
be challenging.

Below is a list of topics we intend to write How-To documents about. The ones that are not linked to another page are to be considered To-Be-Done (TBD), and they should be added incrementally. Contributions are welcome!

Initial Setup
^^^^^^^^^^^^^

Real Hardware
"""""""""""""

 - Consult the official hardware guide at <https://openwrt.org/toh/start>.
 - Ensure the device is flashed with a compatible OpenWrt firmware image.
 - Default configurations define separate WAN and LAN interfaces; wireless is disabled by default.
 - LAN interfaces typically have an active DHCP server enabled.
 - The LuCI web interface is accessible at ``<http://192.168.1.1>``.

**Note**: Single-interface hardware (for example, Raspberry Pi) typically defaults the Ethernet port to the LAN zone.
Establishing WAN connectivity requires configuring the onboard WiFi or a USB network adapter.
Be aware that USB adapters often require drivers missing from the base image; bootstrapping initial connectivity
for such hardware is an advanced topic and beyond the scope of this guide.

Verify connectivity via ping, LuCI, or SSH at ``192.168.1.1`` (default: ``root`` / no password).
Consult the OpenWrt documentation for further device-specific instructions.

VM as a router on hypervisors (Proxmox showcase)
""""""""""""""""""""""""""""""""""""""""""""""""""

You need the ``community.proxmox <https://docs.ansible.com/projects/ansible/latest/collections/community/proxmox/index.html>`` role.

**Download Image**

Unfortunately ``community.proxmox.proxmox_template`` can only download iso, lxc templates or ova. So we use ssh to proxmox.

..  code-block:: yaml+jinja

    ---
    - hosts: proxmox
      gather_facts: false
      become: true
      vars:
        #openwrt_version: "24.10.5"
        openwrt_version: "25.12.0-rc4"
        # this is the default "local" storage iso path
        iso_storage_path: "/var/lib/vz/template/iso"
        openwrt_image_url: "https://downloads.openwrt.org/releases/{{ openwrt_version }}/targets/x86/64/openwrt-{{ openwrt_version }}-x86-64-generic-ext4-combined.img.gz"
        openwrt_filename: "openwrt-{{ openwrt_version }}-x86-64-generic-ext4-combined.img.gz"
      tasks:
        - name: Install OpenWRT image
          shell: |
            cd {{ iso_storage_path }}
            wget -q "{{ openwrt_image_url }}"
            gunzip -f "{{ openwrt_filename }}"
          args:
            creates: "{{ iso_storage_path }}/{{ openwrt_filename | replace('.gz', '') }}"

**Create the VM**

..  code-block:: yaml+jinja

    ---
    - hosts: localhost
      gather_facts: false
      vars:
        proxmox_api_user: root@pam
        proxmox_api_token_id: my-token-id
        proxmox_api_token_secret: xxxxxx-xxxxx-xxxxxx-xxxx
        proxmox_host: "pve.example.com:8006"
        proxmox_vm_storage: local

        proxmox_vm_id: 8563
        proxmox_vm_name: dummy-openwrt
        proxmox_vm_node: pve

        iso_storage_path: "/var/lib/vz/template/iso"

        openwrt_version: "25.12.0-rc4"
        openwrt_image: "openwrt-{{ openwrt_version }}-x86-64-generic-ext4-combined.img"
      tasks:
        - name: Remove VM if it exists
          community.proxmox.proxmox_kvm:
            api_user: "{{ proxmox_api_user }}"
            api_token_id: "{{ proxmox_api_token_id }}"
            api_token_secret: "{{ proxmox_api_token_secret }}"
            api_host: "{{ proxmox_host }}"
            vmid: "{{ proxmox_vm_id }}"
            state: absent
            force: true
            timeout: 300

        - name: Create OpenWrt VM
          community.proxmox.proxmox_kvm:
            api_user: "{{ proxmox_api_user }}"
            api_token_id: "{{ proxmox_api_token_id }}"
            api_token_secret: "{{ proxmox_api_token_secret }}"
            api_host: "{{ proxmox_host }}"
            vmid: "{{ proxmox_vm_id }}"
            name: "{{ proxmox_vm_name }}"
            node: "{{ proxmox_vm_node }}"
            storage: "{{ proxmox_vm_storage }}"
            state: present
            scsihw: virtio-scsi-single
            net:
              # careful here
              # LAN
              net0: 'virtio,bridge=vmbrXXX'
              # WAN
              net1: 'virtio,bridge=vmbrYYY'
            cores: 2
            memory: 512

        # this uses SSH - if you know how to use ``community.proxmox.proxmox_disk`` create a ticket via github

        - name: Check VM configuration for scsi0
          ansible.builtin.command: "qm config {{ proxmox_vm_id }}"
          register: vm_config
          delegate_to: "{{ proxmox_vm_node }}"
          become: true
          changed_when: false

        - name: Import OpenWrt image and set boot order
          ansible.builtin.shell: |
            qm set {{ proxmox_vm_id }} --scsi0 {{ proxmox_vm_storage }}:0,import-from="{{ iso_storage_path }}/{{ openwrt_image }}",discard=on,cache=writeback,format=qcow2
            qm set {{ proxmox_vm_id }} --boot order=scsi0
          delegate_to: "{{ proxmox_vm_node }}"
          become: true
          when:
            - "'scsi0:' not in vm_config.stdout"
          register: import_result

**Further VM Bootstrapping Automation**

- Challenge: ``192.168.1.1`` might be not routed. The ``WAN`` device has a firewall for http(s) and ssh.
- Limitation: ``community.openwrt`` requires SSH and cannot bootstrap the device.
- Solution: On Proxmox, use ``serial0`` instead of the VGA display and automate with ``ansible.builtin.expect``.

..  code-block:: yaml+jinja

    - name: Make Terminal serial console
      ansible.builtin.shell: |
        qm shutdown {{ proxmox_vm_openwrt_vmid }} || true
        qm set {{ proxmox_vm_openwrt_vmid }} --serial0 socket --vga serial0
        # close any terminal on the Proxmox UI
        qm start {{ proxmox_vm_openwrt_vmid }}

    - name: Set SSH
      ansible.builtin.expect:
      delegate_to: "{{ proxmox_vm_node }}"
      become: true
        command: "qm terminal {{ proxmox_vm_id }}"
        responses:
            "xxx":
                - "yyy"

You also need to install ``qemu-ga`` (QEMU Guest Agent) in OpenWrt to simplify Proxmox interaction with the VM.
This can also be done in Ansible.

..  code-block:: bash

    # legacy OpenWrt 24.x
    # opkg update
    # opkg install qemu-ga

    # OpenWrt >= 25.x
    apt update
    apt add -q qemu-ga

    service qemu-ga enable
    # you have to reboot


SSH Installation
^^^^^^^^^^^^^^^^

Bootstrap
"""""""""

**Manual SSH installation**

- Click here (or your use your own IP) ``<http://192.168.1.1>``.
- If https redirects are enabled, you might get a certificate warning. Please ignore this.
- Login was ``root`` / no password (check the documentation of your image for other default passwords).
- OpenWrt might ask you to change the password.
- Click on System/Administration/Router Password
- Change your Router Password.
- Click on System/Administration/SSH Access (if you don't see this - follow the instructions)
- Enable ``Enable Instance``
- Disable the ``Password authentication``
- Disable ``Allow root logins with passwords``
- Click on System/Administration/SSH-Keys
- Add your SSH Key here

If you have no SSH Access in the Admin menu, you might need to install dropbear

- Your OpenWrt router needs internet access.
- Click on System/Software/Update Lists. Confirm with Dismiss.
- In the Filter box type in ``dropbear``
- Press the ``Install...`` button.
- Click System/Reboot/Perform Reboot
- After reboot, perform the steps System/Administration/SSH Access mentioned before


Troubleshooting

- The ``dropbear`` service might not be enabled.
- Click System/Startup
- Check if ``dropbear`` is in the list. If it's ``Disabled`` click on the button to enable it.
- Click on the ``Start`` / ``Restart`` button.
- If SSH is still not available on ``192.168.1.1`` check the firewall rules.

Reboot the system and ensure that you can login via ssh keys.

**Ansible based SSH Key Installation**

- TBD

**Advanced SSH Key Installation**

- You might have a board that only has a serial port terminal access.

..  code-block:: bash

    # set root password
    passwd

    # install dropbear

    # legacy OpenWrt 24.x
    # opkg update
    # opkg install dropbear

    # OpenWrt >= 25.x
    apk update
    apk add -q dropbear

    service dropbear enable
    service dropbear start

    echo 'your ssh key content' > /etc/dropbear/authorized_keys

    uci set dropbear.@dropbear[0].PasswordAuth='off'
    uci set dropbear.@dropbear[0].RootPasswordAuth='off'
    uci commit dropbear


SSL Certificates
^^^^^^^^^^^^^^^^

- redirect http to https
- acme support
- Install existing ssl certificates


Wifi Setup
^^^^^^^^^^

- 2Ghz / 5Ghz
- Passwords
- Additional Guest Network + isolation


VPN
^^^

- Wireguard Server
- Wireguard Client
- NordVPN or similar
- Netbird
- Tailscale
- Tinc


Advanced networking
^^^^^^^^^^^^^^^^^^^

- VLAN
- VLAN per Hardware Port
- Routing
- Firewall, Port forwarding


Hardware
^^^^^^^^

- Configure the hardware button do do cool things
- Configure the LEDs


Firmware Update
^^^^^^^^^^^^^^^

- CLI / UI Tool installation


Backup/Restore
^^^^^^^^^^^^^^

- Backup
- Restore
- Crontab
