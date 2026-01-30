..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.apk_opkg_guide:


OpenWrt 25.x Package Manager changes
====================================

With OpenWrt 25.x the Package Manager changed from ``opkg`` to ``apk`` (apk is used in Alpine Linux).
The announcement as made here: <https://openwrt.org/releases/25.12/notes-25.12.0-rc1>.

Major changes can be found here: <https://openwrt.org/docs/guide-user/additional-software/opkg-to-apk-cheatsheet>


Playbooks supporting only apk
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

..  code-block:: yaml+jinja

    ---
    - hosts: routers
      gather_facts: false
      roles:
        - community.openwrt.init
      tasks:
        - name: Gather OpenWrt facts
          community.openwrt.setup:

        # opkg will fail on OpenWrt 25.x or later
        - name: Install a package
          community.openwrt.apk:
            name: luci
            state: present


Playbooks supporting both apk and legacy opkg
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

..  code-block:: yaml+jinja

    ---
    - hosts: routers
      gather_facts: false
      roles:
        - community.openwrt.init
      tasks:
        - name: Install software (apk)
          community.openwrt.apk:
            name: luci
            state: present
          when: openwrt_package_manager == 'apk'

        - name: Install software (legacy opkg)
          community.openwrt.opkg:
            name: luci
            state: present
          when: openwrt_package_manager == 'opkg'

