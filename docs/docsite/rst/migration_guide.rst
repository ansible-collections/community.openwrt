..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.migration_guide:

Community OpenWrt Migration Guide
=================================

This guide provides the information needed for users migrating from ``gekmihesg.openwrt`` role
to the ``community.openwrt`` collection.

If you are new to ``community.openwrt`` and not migrating from ``gekmihesg.openwrt``,
you should start with the :ref:`ansible_collections.community.openwrt.docsite.user_guide` instead.


Overview
^^^^^^^^

The ``community.openwrt`` collection builds upon the foundation of the ``gekmihesg.openwrt``
Ansible role, which was maintained by Markus Weippert until 2022. While the core functionality
remains similar, there are important changes in structure and usage patterns that you will need
to address when migrating your playbooks.

The good news is that both projects share the same approach: they enable you to manage OpenWrt
devices without requiring Python on the target systems. All modules are implemented as shell
scripts, making them compatible with resource-constrained devices. While the underlying code
is largely the same, the collection now provides proper documentation for each module, accessible
via ``ansible-doc`` or the `collection documentation site <https://galaxy.ansible.com/ui/repo/published/community/openwrt/>`_.


Key Differences
^^^^^^^^^^^^^^^

Structure
"""""""""

``gekmihesg.openwrt`` was an Ansible role that you included in your playbooks.
It provided modules and handlers as part of the role.

``community.openwrt`` is a full Ansible collection with a defined namespace.
It provides:

* Multiple modules (``community.openwrt.opkg``, ``community.openwrt.uci``, etc.)
* Multiple roles (``community.openwrt.init``, ``community.openwrt.common``)
* Handlers and plugins organized in a standard collection structure

No Support for Standard Ansible Modules
"""""""""""""""""""""""""""""""""""""""

Migrated playbooks **MUST** use modules in the ``community.openwrt`` namespace to function correctly on devices without Python.

In the legacy ``gekmihesg.openwrt`` role, a `monkey patch <https://en.wikipedia.org/wiki/Monkey_patch>`_
intercepted tasks calling standard modules (for example ``lineinfile``) and redirected them to shell-script
equivalents. This allowed execution on hosts without Python.

This collection does **not** include monkey patching. If you are migrating playbooks that utilize
standard Ansible modules (such as ``ansible.builtin.*``), you must update them to use the
equivalent ``community.openwrt.*`` implementation.

Attempting to use standard modules like ``fetch`` or ``template`` 
(see `Issue #63 <https://github.com/ansible-collections/community.openwrt/issues/63>`_)
will typically fail with an error indicating missing Python:

   ``Task failed: Action failed: The module interpreter '/usr/bin/python3' was not found``

Workarounds
-----------

There are some easy work-arounds until native equivalents are added to ``community.openwrt``. 
For example, you can use the ``lookup`` plugin along with ``community.openwrt.copy``  
as a replacement for ``ansible.builtin.template``:

.. code-block:: yaml+jinja

    - name: Generate template and copy to device
      community.openwrt.copy:
        content: "{{ lookup('template', 'config_template.j2') }}"
        dest: /etc/app/config.json

Installation
""""""""""""

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - gekmihesg.openwrt
     - community.openwrt
   * - .. code-block:: bash

          ansible-galaxy install gekmihesg.openwrt
     - .. code-block:: bash

          ansible-galaxy collection install community.openwrt


Initialization
""""""""""""""

Both ``gekmihesg.openwrt`` and ``community.openwrt`` require you to include an initialization
role before using their modules and handlers.

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - gekmihesg.openwrt
     - community.openwrt
   * - .. code-block:: yaml+jinja

          - hosts: openwrt
            roles:
              - gekmihesg.openwrt
     - .. code-block:: yaml+jinja

          - hosts: routers
            roles:
              - community.openwrt.init

The initialization role sets up the necessary environment, installs recommended packages,
configures variables, and registers handlers.

..  note::

    The ``gekmihesg.openwrt`` role required all target hosts to be members of an
    ``openwrt`` group. The ``community.openwrt`` collection has no such requirement - you can
    use any group name or host pattern you prefer.


Namespace
"""""""""

All modules and roles now use the ``community.openwrt`` namespace prefix.

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - gekmihesg.openwrt
     - community.openwrt
   * - .. code-block:: yaml+jinja

          - name: Install package
            opkg:
              name: luci
              state: present
     - .. code-block:: yaml+jinja

          - name: Install package
            community.openwrt.opkg:
              name: luci
              state: present


Migration Steps
^^^^^^^^^^^^^^^

Step 1: Install the Collection
"""""""""""""""""""""""""""""""

First, install the ``community.openwrt`` collection:

..  code-block:: bash

    ansible-galaxy collection install community.openwrt

You can optionally add it to your ``requirements.yml``:

..  code-block:: yaml

    ---
    collections:
      - name: community.openwrt


Step 2: Update Role References
"""""""""""""""""""""""""""""""

Replace references to the ``gekmihesg.openwrt`` role with ``community.openwrt.init``.

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - gekmihesg.openwrt
     - community.openwrt
   * - .. code-block:: yaml+jinja

          ---
          - hosts: openwrt
            gather_facts: false
            roles:
              - gekmihesg.openwrt
     - .. code-block:: yaml+jinja

          ---
          - hosts: routers
            gather_facts: false
            roles:
              - community.openwrt.init


Step 3: Add Module Namespaces
""""""""""""""""""""""""""""""

Update all module calls to include the ``community.openwrt`` namespace prefix.

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - gekmihesg.openwrt
     - community.openwrt
   * - .. code-block:: yaml+jinja

          tasks:
            - name: Gather facts
              setup:

            - name: Install package
              opkg:
                name: luci
                state: present

            - name: Configure UCI
              uci:
                command: set
                key: system.@system[0].hostname
                value: myrouter

            - name: Copy file
              copy:
                src: /path/to/file
                dest: /etc/config/custom
     - .. code-block:: yaml+jinja

          tasks:
            - name: Gather facts
              community.openwrt.setup:

            - name: Install package
              community.openwrt.opkg:
                name: luci
                state: present

            - name: Configure UCI
              community.openwrt.uci:
                command: set
                key: system.@system[0].hostname
                value: myrouter

            - name: Copy file
              community.openwrt.copy:
                src: /path/to/file
                dest: /etc/config/custom


Step 4: Handler References
"""""""""""""""""""""""""""

Handlers references remain the same, just make sure you have included the ``community.openwrt.init`` role
for them to be available.

..  code-block:: yaml+jinja

    - name: Configure wireless
      community.openwrt.uci:
        command: set
        key: wireless.radio0.channel
        value: "6"
      notify: Reload wifi

..  note::

    The names of some handlers that were entirely lower case have been capitalized.

Variables
^^^^^^^^^

Most variables remain compatible between ``gekmihesg.openwrt`` and ``community.openwrt``.
The collection uses the same variable names:

* ``openwrt_scp_if_ssh``
* ``openwrt_remote_tmp``
* ``openwrt_install_recommended_packages``
* ``openwrt_wait_for_connection``
* ``openwrt_wait_for_connection_timeout``

These variables continue to work as before, so your existing variable definitions
in inventory, group_vars, or host_vars should not require changes. They can also be
set when including the initialization role, as shown in the complete example below.


Complete Example
^^^^^^^^^^^^^^^^

Here is a complete before-and-after example to illustrate the migration:

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - gekmihesg.openwrt
     - community.openwrt
   * - .. code-block:: yaml+jinja

          ---
          - hosts: openwrt
            gather_facts: false
            roles:
              - role: gekmihesg.openwrt
                vars:
                  openwrt_install_recommended_packages: true
            tasks:
              - name: Gather facts
                setup:

              - name: Install packages
                opkg:
                  name: "{{ item }}"
                  state: present
                loop:
                  - luci
                  - luci-ssl

              - name: Set hostname
                uci:
                  command: set
                  key: system.@system[0].hostname
                  value: myrouter
                notify: Reload network
     - .. code-block:: yaml+jinja

          ---
          - hosts: routers
            gather_facts: false
            roles:
              - role: community.openwrt.init
                vars:
                  openwrt_install_recommended_packages: true
            tasks:
              - name: Gather facts
                community.openwrt.setup:

              - name: Install packages
                community.openwrt.opkg:
                  name: "{{ item }}"
                  state: present
                loop:
                  - luci
                  - luci-ssl

              - name: Set hostname
                community.openwrt.uci:
                  command: set
                  key: system.@system[0].hostname
                  value: myrouter
                notify: Reload network


Testing Your Migration
^^^^^^^^^^^^^^^^^^^^^^

After updating your playbooks:

1. **Start small**: Test with a single device or a small group first
2. **Run in check mode**: Use ``--check`` to see what would change without making changes
3. **Verify handlers**: Ensure handlers are properly notified and executed
4. **Check facts**: Verify that ``community.openwrt.setup`` returns the expected facts
5. **Monitor logs**: Review task output for any unexpected warnings or errors


Troubleshooting
^^^^^^^^^^^^^^^

Collection Not Found
""""""""""""""""""""

If you see errors like ``could not resolve module/action 'community.openwrt.opkg'``:

* Verify the collection is installed: ``ansible-galaxy collection list``
* Check you are using the correct namespace prefix
* Ensure your Ansible version meets the minimum requirements (see the collection README)


Module Behavior Differences
""""""""""""""""""""""""""""

While the collection maintains compatibility with the original role's functionality,
some edge cases may behave slightly differently. If you encounter unexpected behavior:

* Check the module documentation: ``ansible-doc community.openwrt.<module_name>``
* Review the `collection's issue tracker on GitHub <https://github.com/ansible-collections/community.openwrt/issues>`_


Getting Help
^^^^^^^^^^^^

If you encounter issues during migration:

* Check the :ref:`ansible_collections.community.openwrt.docsite.user_guide`
* Review the `collection documentation <https://galaxy.ansible.com/ui/repo/published/community/openwrt/>`_
* Join the `Ansible forum <https://forum.ansible.com/>`_ and use the ``community-openwrt`` tag
* Visit the `GitHub repository <https://github.com/ansible-collections/community.openwrt>`_
* Consider opening an issue if you believe you have found a compatibility problem


.. versionadded:: 0.3.0
