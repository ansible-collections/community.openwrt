..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.howto_guide:


Community OpenWrt How-To Guide
==============================

Welcome to the Community OpenWrt How-To Guide! This is a collection of recipes that will help you
using the ``community.openwrt`` role in real world scenarios.

OpenWrt has a very small footprint there is no python available it is a design rule of ``community.openwrt``
to no force you to install it. Based on this limitation a lot of ansible pattern and default roles
are not available or will fail. However there are ``community.openwrt`` specific roles.

Also by the nature of OpenWrt and its CLI-based ``uci`` tool, you need to be very familiar how
this ecosystem works. Even the creation of a Wifi passwort or a simple forwarding rule can
be challenging.


Initial Setup
^^^^^^^^^^^^^

- Real Hardware
- VM as a router for Proxmox or similar hypervisors


SSH Installation
^^^^^^^^^^^^^^^^

- Bootstrap
- Initial SSH Key Installation


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
