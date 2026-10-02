..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.user_guide:


Community OpenWrt User Guide
============================

Welcome to the Community OpenWrt User Guide! If you are reading this, it's likely that you own
or manage OpenWrt routers and you would like to use Ansible to manage them.
As you may well know, some devices have limitations of resources, preventing Python from being installed.

This collection is based on the Ansible role ``gekmihesg.openwrt`` and as such it does not require Python
installed on the OpenWrt devices. The role's modules were plain shell scripts; starting with
community.openwrt 1.9.0, all modules are written in ucode.
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
        - name: Gather OpenWrt facts
          community.openwrt.setup:

        - name: Install a package
          community.openwrt.apk:
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

The control node requires Python.

This collection is tested using OpenWrt container images for the ``x86_64`` architecture.

Additional packages
"""""""""""""""""""

Stock OpenWrt images provide only MD5 and SHA256 checksums. To provide some specific features, additional
packages are needed in the OpenWrt devices:

    coreutils-sha1sum
      Needed for ``community.openwrt.stat`` to return ``checksum`` with the default algorithm (SHA1);
      without it, the module succeeds but omits ``checksum``. Alternatively, install ``openssl-util``.

The SHA224, SHA384 and SHA512 algorithms are only needed if you select one of them in the ``checksum_algorithm``
option of ``community.openwrt.stat``. In that case, the task fails unless the matching package
(``coreutils-sha224sum``, ``coreutils-sha384sum`` or ``coreutils-sha512sum``) or ``openssl-util`` is installed.

When ``openssl-util`` is not installed, the ``community.openwrt.init`` role installs ``coreutils-sha1sum``.


Configuration
^^^^^^^^^^^^^

OpenWrt control variables
"""""""""""""""""""""""""

These variables control Ansible behavior:

    openwrt_scp_if_ssh:
        Whether to use ``scp`` instead of ``sftp`` for OpenWrt systems (sets ``ansible_scp_if_ssh``).
        Value can be ``true``, ``false`` or ``smart``. (default: ``smart``)

    openwrt_remote_tmp:
        Ansible's ``remote_tmp`` (sets ``ansible_remote_tmp``) setting for OpenWrt systems.
        Setting to ``/tmp`` helps prevent flash wear on target device. (default: ``/tmp``)

This variable is used when including the ``community.openwrt.init`` role:

    openwrt_install_recommended_packages:
        Checks for some commands and installs the corresponding packages if they are
        missing. See the item above. (default: ``true``)

These variables are used by the handlers defined in the collection:

    openwrt_wait_for_connection, openwrt_wait_for_connection_timeout:
        Whether to wait for the host (default: ``true``) and how long (default: ``600``) after a
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
* Registers notification handlers

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

The collection provides some standard handlers you can use in your playbooks:

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

In playbooks ``gather_facts=true`` will **always** try to run Python in the target node, unless you enable the
:ref:`transparent gather_facts support <ansible_collections.community.openwrt.docsite.user_guide.gather_facts_shim>`
described below.
Because of that, it is recommended that you disable
`default fact gathering <https://docs.ansible.com/projects/ansible/latest/reference_appendices/config.html#default-gathering>`_
in your ``ansible.cfg`` file, or make sure to always set ``gather_facts=false``.

That being said, you can retrieve facts from your OpenWrt device using the module ``community.openwrt.setup``.
It is as easy as:

..  code-block:: yaml+jinja

    - name: Gather OpenWrt facts
      community.openwrt.setup:


.. _ansible_collections.community.openwrt.docsite.user_guide.gather_facts_shim:

Transparent ``gather_facts`` support
--------------------------------------

This collection provides an optional shim that intercepts play-level
``gather_facts: true`` and redirects it to ``community.openwrt.setup``,
so playbooks that rely on implicit fact gathering work without modification.

**How it works**

Ansible resolves the ``gather_facts`` action through the ``ansible.legacy``
pseudo-namespace, searching directories listed in ``action_plugins`` before
falling back to ``ansible.builtin``. Action plugins placed in a collection's
``plugins/action/`` directory are only reachable as
``<namespace>.<collection>.<name>`` and cannot override
``ansible.legacy.gather_facts``. The shim lives in a dedicated directory
(``plugins/plugin_utils/_setup/``) that is added to the search path explicitly,
so only the ``gather_facts`` override is exposed without shadowing any other
built-in action plugins.

**Required configuration**

Add the shim directory to the ``action_plugins`` search path in ``ansible.cfg``:

..  code-block:: ini

    [defaults]
    # example path
    action_plugins = ~/.ansible/collections/ansible_collections/community/openwrt/plugins/plugin_utils/_setup

**Per-host opt-in**

The shim only intercepts fact gathering for hosts that have
``openwrt_gather_facts: true`` set (for example in ``group_vars/`` or
``host_vars/``). All other hosts fall through to ``ansible.builtin.gather_facts``
unchanged.

..  code-block:: yaml+jinja

    # group_vars/openwrt.yml
    openwrt_gather_facts: true


.. versionadded:: 0.3.0
