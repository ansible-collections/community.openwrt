..
  Copyright (c) 2026, Alexei Znamensky (@russoz)
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.architecture:


Community OpenWrt Architecture
==============================

Most Ansible collections take one thing for granted: a Python interpreter on the managed node. Their modules are
Python programs, ``ansible-core`` packs them and their ``module_utils`` into a single payload, and that payload
runs on the target. ``community.openwrt`` cannot take that for granted, and most of what makes it look unusual
follows from that.

This document explains why the collection is built the way it is, and what that means for you, whether you
write playbooks with it or modules for it. It does not go into the details of either: the
:ref:`ansible_collections.community.openwrt.docsite.user_guide` and the
:ref:`ansible_collections.community.openwrt.docsite.ucode_mod_dev_guide` do.

The design rests on two constraints and one enabler.

.. _ansible_collections.community.openwrt.docsite.architecture.constraints:

Constraints and enabler
^^^^^^^^^^^^^^^^^^^^^^^

No Python on the target
"""""""""""""""""""""""

OpenWrt images do not ship Python. It can be installed on some devices, but it is a poor fit for this kind of
target:

* Ansible needs more than the interpreter: its module code imports a good part of the Python standard library.
  The smallest Python able to run it takes most of the free flash an entry-level device has left after the
  firmware, and does not fit at all on devices with 8 MB of flash - see OpenWrt's notes on
  `device sizing <https://openwrt.org/supported_devices/864_warning>`_.
* Every task starts a Python interpreter and loads Ansible's module code into it, which takes an order of
  magnitude more memory than a ucode module doing the same, on devices where 64 or 128 MB of RAM is common.
* A firmware upgrade keeps the configuration but not the packages installed on top of the image, so Python
  would have to be reinstalled after each one - with ``ansible.builtin.raw``, since no module runs without it.

The collection therefore does not ask for Python on the target at all. Every piece of ``ansible-core`` that assumes it -
running modules, gathering facts, the standard modules themselves - has to be avoided or replaced.

The control node is an ordinary Ansible control node, and does require Python.

The target is a small device
""""""""""""""""""""""""""""

Even setting Python aside, an OpenWrt device is not a server. Flash is small and wears out with writes, RAM is
scarcer still, and the userspace is minimal: shell commands are provided by BusyBox, and the SSH server is
Dropbear. Only what is in the base image can be taken for granted; anything beyond that is an extra package the
user must install.

ucode is in every base image
""""""""""""""""""""""""""""

The base image does carry `ucode <https://ucode-lang.org/>`_, OpenWrt's own scripting language, together with a
few of its modules - ``fs``, ``uci``, ``ubus`` and ``math`` among them - on every OpenWrt release this collection
supports. ucode reads and writes JSON natively, has arrays and dictionaries that nest, raises and catches
exceptions, and imports code from other files.

That is what makes the design work: modules are written in a real programming language that is already on the
device, instead of in ``/bin/sh``, and shared code can be written once and imported by every module that needs
it. The limit is the same as for everything else on the device: only the ucode modules that come with the
interpreter can be relied upon.


.. _ansible_collections.community.openwrt.docsite.architecture.task_flow:

How a task runs
^^^^^^^^^^^^^^^

``ansible-core`` can run a module written in any language, but it bundles ``module_utils`` only for Python
modules. A ucode module that imports shared code needs another way to get that code onto the target, and that
way is an action plugin: every module of this collection comes with one, which runs on the control node and
prepares the target before the module runs.

For a task using ``community.openwrt.stat``, which imports the ``_file`` module utils, that looks like this:

.. code-block:: text

    control node                                       OpenWrt device
    ------------                                       --------------
    action plugin stat.py (UCodeActionBase)
      |-- transfer stat.uc ---------------------->  <tmp>/module.uc
      |-- transfer _basic.uc, _file.uc ---------->  <tmp>/module_utils/
      |-- run community.openwrt.ucode_wrapper --->  <tmp>/ucode_wrapper.sh <args file>
      |                                               exec ucode -S -L module_utils module.uc <args file>
      |                                                 validate parameters, do the work
      |<---------------------- JSON result on stdout ---'
    task result

``ucode_wrapper`` is a module in its own right - a small shell script that ``ansible-core`` transfers and runs
as it does any non-Python module. Its only job is to start the interpreter with the module utils on its search
path, so that a module imports them by name. Whatever the module prints as JSON is the task result, exactly as
for a Python module.


.. _ansible_collections.community.openwrt.docsite.architecture.consequences:

Consequences
^^^^^^^^^^^^

.. _ansible_collections.community.openwrt.docsite.architecture.standard_modules:

Standard modules do not work on OpenWrt
"""""""""""""""""""""""""""""""""""""""

Any module that runs on the target and is written in Python fails there, and that includes most of
``ansible.builtin``. The error is the familiar one about a missing ``/usr/bin/python3`` interpreter.

That is why the collection provides its own modules for common tasks - ``community.openwrt.copy``,
``community.openwrt.file``, ``community.openwrt.stat``, ``community.openwrt.command`` and others - and why
playbooks must call them by their fully qualified collection name: a bare ``copy`` resolves to
``ansible.builtin.copy``, which needs Python. The collection does not intercept or redirect standard modules.

What does keep working is everything that does not run a Python module on the target:

* action plugins that work entirely on the control node, such as ``ansible.builtin.debug``,
  ``ansible.builtin.set_fact`` or ``ansible.builtin.assert``;
* ``ansible.builtin.raw``, which runs a command over the connection without any module.

Some standard action plugins do part of their work on the control node and then call a Python module on the
target - ``ansible.builtin.template`` renders the template locally and then calls ``copy``. Those fail as well.

Modules that run on the control node
""""""""""""""""""""""""""""""""""""

A few of the collection's modules have no ucode file at all. ``community.openwrt.template`` and
``community.openwrt.wait_for_connection`` are action plugins built on their ``ansible.builtin`` counterparts,
with the step that would run a Python module on the target replaced by the collection's own: ``template``
copies the rendered file with ``community.openwrt.copy``, and ``wait_for_connection`` checks the connection with
``community.openwrt.ping``.

A small AnsibleModule of its own
""""""""""""""""""""""""""""""""

The conveniences that ``AnsibleModule`` gives a Python module - an ``argument_spec`` that validates and
converts parameters, check mode, consistent results, running commands - come from ``ansible.module_utils``,
which is Python. The collection provides its own, smaller counterpart in ucode, ``_basic.uc``, transferred with
every module. It deliberately resembles the Python API, so modules here read like Ansible modules elsewhere,
but it is not the same code and does not do everything the Python one does.

.. _ansible_collections.community.openwrt.docsite.architecture.facts:

Fact gathering
""""""""""""""

Play-level fact gathering runs ``ansible.builtin.setup``, a Python module, so ``gather_facts: true`` fails on
OpenWrt hosts. Facts are gathered with ``community.openwrt.setup`` instead, either as an explicit task or through
an optional shim that takes over fact gathering for the hosts you opt in and runs ``community.openwrt.setup`` in
place of the standard module. ``ansible-core`` offers no way for a collection to override ``gather_facts``, so
the shim lives in its own directory, which you add to the ``action_plugins`` search path yourself. The
:ref:`user guide <ansible_collections.community.openwrt.docsite.user_guide.gather_facts_shim>` describes how to
set it up.

Connection settings
"""""""""""""""""""

The device shapes two connection settings, both of which the ``community.openwrt.init`` role takes care of:

* the remote temporary directory is set to ``/tmp``, which lives in RAM on OpenWrt, instead of a directory under
  the user's home, which lives on flash - every task writes files there, and flash wears out;
* Dropbear does not provide an SFTP server, so file transfers rely on ``ansible-core`` falling back to ``scp``,
  which it does by default; the role lets you choose the transfer method explicitly instead.

Packages beyond the base image
""""""""""""""""""""""""""""""

Because nothing beyond the base image can be assumed, a module needing an external command or package declares
it in its documentation, and fails cleanly when it is not there. Installing such packages is left to the user;
the ``community.openwrt.init`` role can install the ones the collection's own modules benefit from.

Documentation and sanity tests
""""""""""""""""""""""""""""""

A module's documentation lives in a ``.yml`` file next to its ucode file, which ``ansible-core`` and
``ansible-doc`` read as they read the documentation of any module. The sanity tests that cross-check a Python
module's documentation against its ``argument_spec`` cannot read ucode, though, so for these modules the two
are kept consistent by hand.

Testing
"""""""

``ansible-test`` unit tests are written in Python and can only exercise the Python side of the collection: the
action plugins and the plugin utils. The ucode modules are tested by running them, with integration tests driven
by Molecule against OpenWrt container images, one for each OpenWrt release the collection is tested against. The
:ref:`ansible_collections.community.openwrt.docsite.testing_guide` covers how.


.. _ansible_collections.community.openwrt.docsite.architecture.history:

History
^^^^^^^

The collection descends from the ``gekmihesg.openwrt`` role, maintained by Markus Weippert until 2022. The role
already managed OpenWrt without Python on the target, but its modules were shell scripts, built on a common
``wrapper.sh`` library, and it monkeypatched ``ansible-core`` so that tasks calling standard modules, such as
``lineinfile``, ran its shell implementations instead.

The monkeypatching served the role in two ways: tasks could call its modules by their bare names - a role has no
namespace to put in front of them - and each module script was injected into ``wrapper.sh`` as it ran. Once the
code became a collection, neither was needed: modules are called by their fully qualified collection names, and
action plugins took over preparing the module on the target. ``community.openwrt`` dropped the monkeypatching,
and with it any redirection of standard modules, and later gave its shell modules shared module utils.

Shell scripts proved hard to grow, though: JSON handled through ``jshn``, no data structures beyond strings,
and limited error handling. Release 1.9.0 reimplemented every module in ucode and removed the shell-based
framework, keeping the overall shape - action plugins on the control node, modules and their utils transferred
to the target - and replacing what runs there.
