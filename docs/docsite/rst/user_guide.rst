..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.user_guide:


Community OpenWrt User Guide
============================

Welcome to the Community OpenWrt User Guide! If you are reading this, it's likely that you own
or manage OpenWrt routers and you would like to use Ansible to manage them.
As you may well know, some devices have limitations of resources, preventing Python from being installed.

This collection is based on the Ansible role ``gekmihesg.openwrt`` and as such it does not require Python
installed on the OpenWrt devices - all the code is written in plain shell scripts.
If you have been using ``gekmihesg.openwrt`` before and want to move to ``community.openwrt``,
please check the :ref:`ansible_collections.community.openwrt.docsite.migration_guide`.


Quickstart
^^^^^^^^^^

To get started with ``community.openwrt`` you can simply run a playbook like:

..  code-block:: yaml+jinja

    ---
    - hosts: routers
      gather_facts: false
      roles:
        - community.openwrt.init
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


Requirements
^^^^^^^^^^^^

Check the collection's `README <https://github.com/ansible-collections/community.openwrt?tab=readme-ov-file>`_
for the supported versions of Ansible and OpenWrt.

The modules in this collection are all written in shell script (more specifically ``ash``,
used in OpenWrt devices). The control node requires Python and follows  ``ansible-core``
`support matrix <https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-support-matrix>`_.

This collection is tested using OpenWrt container images for the ``x86_64`` architecture.
As of Dec 2025, it supports OpenWrt versions: 21.02, 22.03, 23.05, and 24.10. It is likely going to
run in other versions as well, but we strongly recommend using
`supported versions <https://openwrt.org/docs/guide-developer/security#support_status>`_ of OpenWrt.


Additional packages
"""""""""""""""""""

To provide some specific features, additional packages are required in the OpenWrt devices:

    coreutils-sha1sum
      Required for any module that uses/provides SHA1 hashes.

    coreutils-base64
      Used to improve the performance of modules that manipulate content using the Base64 encoding.

The installation of those packages is performed by the ``community.openwrt.init`` role.


Configuration
^^^^^^^^^^^^^

OpenWrt control variables
"""""""""""""""""""""""""

These variables control Ansible behavior:

    openwrt_scp_if_ssh:
        Whether to use ``scp`` instead of ``sftp`` for OpenWRT systems (sets ``ansible_scp_if_ssh``).
        Value can be ``true``, ``false`` or ``smart``. (default: ``smart``)

    openwrt_remote_tmp:
        Ansibles ``remote_tmp`` (sets ``ansible_remote_tmp``) setting for OpenWRT systems.
        Setting to ``/tmp`` helps prevent flash wear on target device. (default: ``/tmp``)

This variable is used when including the ``community.openwrt.init`` role:

    openwrt_install_recommended_packages:
        Checks for some commands and installs the corresponding packages if they are
        missing. See the item above. (default: ``true``)

These variables are used by the handlers defined in the collection:

    openwrt_wait_for_connection, openwrt_wait_for_connection_timeout:
        Whether to wait for the host (default: ``true``) and how long (default: ``300``) after a
        network or wifi restart (see handlers below).

These variables are created as convenience to perform some specific tasks:

    openwrt_ssh, openwrt_scp, openwrt_ssh_host, openwrt_ssh_user, openwrt_user_host:
        Helper shortcuts to do things like
        ``command: {{ openwrt_scp }} {{ openwrt_user_host|quote }}:/etc/rc.local /tmp``

These variables are set when (or before) executing the ``community.openwrt.init`` role.


Using community.openwrt
^^^^^^^^^^^^^^^^^^^^^^^


Initialization
""""""""""""""

The collection provides the role ``community.openwrt.init`` that should be included before using the modules.
Although the use of this role is not strictly necessary, it is **strongly recommended** that you do so.
The ``init`` role:

* Installs additional packages
* Sets variables controlling the behavior of the modules
* Register notification handlers

You can use it like any other role and you should use it before using any module from this collection.

..  code-block:: yaml+jinja

    - name: Init community.openwrt
      vars:
        openwrt_install_recommended_packages: true
      ansible.builtin.import_role:
        name: community.openwrt.init


Modules
"""""""

Many modules in this collection mimic (to some extent) their counterpart modules in ``ansible.builtin``, for example: ``community.openwrt.copy``,
``community.openwrt.command``, ``community.openwrt.slurp``, etc, whilst other modules are specific to OpenWrt: ``community.openwrt.opkg``,
``community.openwrt.nohup``, etc.

You can find the detailed documentation for each module on the
`community.openwrt collection page in Ansible Galaxy <https://galaxy.ansible.com/ui/repo/published/community/openwrt/>`_.


Handlers
""""""""

The collection providers some standard handlers you can use in your playbooks:

    Setup wifi
        Runs ``/sbin/wifi`` to setup WiFi

    Reload wifi
        Runs ``/sbin/wifi reload`` to reload WiFi configuration

    Restart network
        Restarts the network service

    Wait for connection
        Waits for the device to come back online after network changes

Example usage:

..  code-block:: yaml+jinja

    - name: Configure wireless
      community.openwrt.uci:
        command: set
        key: wireless.radio0.channel
        value: "6"
      notify: Reload wifi

These handlers are actually defined in another role called ``community.openwrt.common``,
but they are made available when ``community.openwrt.init`` is executed.


Facts
"""""

In playbooks ``gather_facts=true`` will **always** try to run Python in the target node.
Because of that, it is recommended that you disable
`default fact gathering <https://docs.ansible.com/projects/ansible/latest/reference_appendices/config.html#default-gathering>`_
in your ``ansible.cfg`` file, or make sure to always set ``gather_facts=false``.

That being said, you can retrieve facts from your OpenWrt device using the module ``community.openwrt.setup``.
It is as easy as:

..  code-block:: yaml+jinja

    - name: Gather OpenWRT facts
      community.openwrt.setup:


.. versionadded:: 0.3.0
