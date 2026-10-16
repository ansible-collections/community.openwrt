..
  Copyright (c) 2026, Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.testing_guide:

Testing Guide
=============

This guide explains how to run and write tests for the ``community.openwrt`` collection.
Because the modules in this collection run as ucode scripts on real OpenWrt devices (or
container images of them), testing works a little differently from a typical Python-based
collection. Read on for the full picture.

.. contents::
   :local:
   :depth: 2

Quickstart
^^^^^^^^^^

Already familiar with Molecule and just need the commands?  Here you go.

**Run a single module's integration test:**

.. code-block:: console

   $ nox -e test -- <target>

**Run the default collection scenario:**

.. code-block:: console

   $ nox -e molecule

**Run all module integration tests:**

.. code-block:: console

   $ nox -e integration

**Run a single role scenario:**

.. code-block:: console

   $ nox -e roles -- --role <role> --scenario <scenario>

**Run all role scenarios:**

.. code-block:: console

   $ nox -e roles

**ucode unit tests:**

.. code-block:: console

   $ nox -e ucode_units

**Sanity / Python unit tests:**

.. code-block:: console

   $ ansible-test sanity --docker default --python 3.14
   $ ansible-test units --docker default --python 3.14

Everything else is explained in the sections below.


What is Molecule?
^^^^^^^^^^^^^^^^^

`Molecule <https://ansible.readthedocs.io/projects/molecule/>`_ is a testing framework
for Ansible roles and collections. It automates the full test lifecycle: spin up one or
more instances (containers or VMs), run your playbooks against them, then tear the
instances down.

A few concepts worth knowing before you dive in:

    - **Scenario**: A named test configuration, stored in a ``molecule/<scenario>/`` directory.
      Each scenario has its own ``molecule.yml`` (driver and platform settings) and a
      ``converge.yml`` playbook that Molecule runs against the instances.
    - **Driver**: The backend that creates instances. This collection uses the ``docker`` driver.
    - **Platform**: A container (or VM) definition — image, name, startup command. Each OpenWrt
      version becomes one platform.
    - **Converge**: The step where Molecule runs your playbook against all running instances.
    - ``molecule test``: Runs the full default sequence: create → converge → destroy. Safe for CI.
    - ``molecule converge``: Runs only the converge step against already-running instances. Handy when
      iterating on a change: create once, converge many times, destroy when done.

For a deeper introduction, see the
`official Molecule documentation <https://ansible.readthedocs.io/projects/molecule/>`_.


Overview
^^^^^^^^

The test suite is built around Molecule, which orchestrates Docker containers running
actual OpenWrt root filesystem images. This means your tests exercise real OpenWrt
userspace — BusyBox shell, ``uci``, ``opkg``, etc. — rather than mocks.

The collection tests fall into four broad categories:

   Integration tests (modules)
       Tests under ``tests/integration/targets/<module>/`` that verify each module's
       behaviour on a live OpenWrt container.

   Role tests
       Molecule scenarios under ``roles/<role>/molecule/<scenario>/`` that test the
       bundled Ansible roles.

   Collection tests
       Tests under ``extensions/molecule`` that do not fall under the previous categories.

   ucode unit tests
       Tests under ``tests/ucode/`` that check module utils and functions inside modules
       in isolation, written with utest. These are not Molecule-based, and may use mocks
       (see `ucode Unit Tests`_).

All categories use real OpenWrt container images. The list of tested OpenWrt versions
is maintained in a single file: ``tests/molecule/openwrt.yml``.

Molecule has native support for Ansible collections and automatically discovers scenarios
placed under ``extensions/molecule/``, so all collection-level tests can be invoked from
the repository root without changing directories.


Running Individual Integration Tests
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Single module
""""""""""""""

Run a single module's integration test using the ``ansible_test_integration`` scenario,
passing the target name as a positional argument:

.. code-block:: console

   $ nox -e test -- uci

This runs the target against all OpenWrt platform versions defined in
``tests/molecule/openwrt.yml``.


Running All Plugin Integration Tests at Once
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The ``molecule_integration`` scenario runs every plugin integration target in a single
pass — the same thing CI does. It does **not** include role tests
(see `Running Role Tests`_ for those).

.. code-block:: console

   $ nox -e integration

The full list of targets is defined in ``extensions/molecule/molecule_integration/converge.yml``.


Running Role Tests
^^^^^^^^^^^^^^^^^^

Each bundled role has its own Molecule scenarios alongside the role itself:

.. code-block:: text

   roles/
     <role>/
       molecule/
         <scenario>/
           molecule.yml   ← minimal; platforms come from tests/molecule/openwrt.yml
           converge.yml

Run a specific role and scenario:

.. code-block:: console

   $ nox -e roles -- --role <role> --scenario <scenario>

For example, for the ``init`` role:

.. code-block:: console

   $ nox -e roles -- --role init --scenario install_recommended_true

Run all scenarios for a single role:

.. code-block:: console

   $ nox -e roles -- --role init

Run every role and every scenario:

.. code-block:: console

   $ nox -e roles

The ``molecule.yml`` files in role scenarios are intentionally minimal (they contain only a
comment). The actual platform list is read at runtime from
``tests/molecule/openwrt.yml`` by the shared ``create.yml`` playbook.


ucode Unit Tests
^^^^^^^^^^^^^^^^

Integration tests prove a module through its interface. Some code is better checked
directly: the module utils under ``plugins/module_utils/``, and the helper functions
inside a module whose edge cases would take a playbook each to reach. Those are
covered by unit tests written in ucode with `utest <https://m00qek.github.io/utest/>`_.

Running them
""""""""""""

.. code-block:: console

   $ nox -e ucode_units

The session starts a container for each OpenWrt version in ``tests/molecule/openwrt.yml``,
installs utest in it, and runs every test file under ``tests/ucode/``. utest is not part of
OpenWrt: it comes from a third-party package feed, pinned by version and checksum in
``UTEST_PACKAGES`` in ``noxfile.py``. A version without a package there is skipped, which
currently means the unit tests run on 24.10 and 25.12 only.

The session takes these options of its own:

``--openwrt VERSION``
    Run against that version only. Repeatable.

``--summary FILE``
    Append a Markdown report to ``FILE``. This is what CI uses to write the job summary.

Everything else is passed to utest. The useful ones are:

``-r detailed``
    Print every test, not just the failures. The default reporter is ``compact``.

``-f REGEX``
    Run only the tests whose full name matches ``REGEX``.

``-s SEED``
    utest runs the test files in random order. Pass the seed of a failed run to repeat it.

For example:

.. code-block:: console

   $ nox -e ucode_units -- --openwrt 25.12 -r detailed -f 'to_id'

Layout
""""""

``tests/ucode/`` mirrors ``tests/unit/``: the tests for ``plugins/<type>/<name>.uc`` go in
``tests/ucode/plugins/<type>/test_<name>.uc``. Tests for a large file may be split into a
directory named after it, as with ``plugins/module_utils/_basic/``.

.. code-block:: text

   tests/ucode/
     utest.config.uc         ← search path, reporter and mocks
     utils/                  ← helpers shared by the tests
     plugins/
       module_utils/
         _basic/
           test_<topic>.uc
         test_uci.uc
       modules/
         test_group.uc

``utest.config.uc`` puts ``plugins/module_utils/`` on the module search path, so a test
imports a module util by its name, as a module does:

.. code-block:: text

   import { describe, it, assert } from 'utest';
   import { normalize_value } from '_uci';

   describe('normalize_value()', () => {
       it('turns true into "1"', () => assert.match('1', normalize_value(true)));
   });

``assert.match()`` takes the expected value first and the actual value second. utest's own
`documentation <https://m00qek.github.io/utest/>`_ covers the rest of its API: ``describe``,
``it``, ``beforeEach``, the assertions and the mocks.

Mocks
"""""

Only the modules listed under ``mocks`` in ``utest.config.uc`` can be mocked; currently those
are ``fs`` and ``_basic``. utest cannot look inside ``_basic``, so it uses the proxy in
``tests/ucode/utils/basic_proxy.uc`` instead. That proxy lists every function ``_basic.uc``
exports, and the list has to be updated when one is added.

Testing AnsibleModule
"""""""""""""""""""""

A module reads its arguments from a file and ends the process through ``exit()``, which would
take the test with it. ``ansible_module()`` in ``tests/ucode/utils/ansible_module.uc`` builds an
``AnsibleModule`` from a dictionary of arguments and catches the exit. It returns
``{ exited: false, value }`` when the module was built, or ``{ exited: true, rc, result }``
when building it ended the module, as invalid arguments do. Call ``reset()`` from the same file in ``afterEach``.

Testing the functions inside a module
"""""""""""""""""""""""""""""""""""""

A module exports nothing, so its functions cannot be imported. ``module_internals()``, also in
``tests/ucode/utils/ansible_module.uc``, returns them as a dictionary keyed by name:

.. code-block:: text

   import { module_internals } from 'utils.ansible_module';

   const to_id = module_internals('../../plugins/modules/group.uc').to_id;

It runs the module only as far as a line ending in a ``// END-OF-UNIT-TESTABLES`` comment,
with ``AnsibleModule()`` mocked. So the module needs that line, placed after its top-level
functions and before the code that does the work. That is usually before the *main* block.
Only functions declared at the top level, with ``function name(`` at the start of the line, are returned.


Sanity and Python Unit Tests
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

These use the standard Ansible tooling and are not Molecule-based. The unit tests here
cover the Python side of the collection: action plugins and plugin utils.

Sanity:

.. code-block:: console

   $ ansible-test sanity --docker default --python 3.14

Unit tests:

.. code-block:: console

   $ ansible-test units --docker default --python 3.14

`andebox <https://github.com/russoz/andebox>`_ is a convenience wrapper around
``ansible-test`` that handles the collection path setup for you, so either tool works.

See the :ref:`ansible_collections.community.openwrt.docsite.ucode_mod_dev_guide` for more
on what the sanity checks cover.


Code Quality and Linting (nox)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The collection uses `nox <https://nox.thea.codes/>`_ together with
`antsibull-nox <https://docs.ansible.com/projects/antsibull-nox/>`_ to run linting,
formatting, and other code-quality checks.

Running a plain ``nox`` executes all default sessions:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Session
     - What it does
   * - ``lint``
     - Meta-session that triggers ``formatters``, ``codeqa``, ``yamllint``, and
       ``antsibull-nox-config``
   * - ``formatters``
     - Runs ``ruff format`` and ``ruff check --fix``
   * - ``codeqa``
     - Runs ``ruff check`` without auto-fixing
   * - ``yamllint``
     - Checks YAML files with ``yamllint``
   * - ``antsibull-nox-config``
     - Lints the ``antsibull-nox.toml`` configuration itself
   * - ``license-check``
     - Verifies REUSE / license compliance across all files
   * - ``extra-checks``
     - Checks for unwanted files in ``plugins/`` and trailing whitespace
   * - ``build-import-check``
     - Builds the collection and runs ``galaxy-importer`` against it

To run all of them:

.. code-block:: console

   $ nox

To target a specific session, use ``-e``:

.. code-block:: console

   $ nox -e lint
   $ nox -e license-check

By default, nox creates a fresh virtual environment for each session. Add ``-R`` to
reuse an existing one and save time on subsequent runs:

.. code-block:: console

   $ nox -Re lint


What CI Runs
^^^^^^^^^^^^

For reference, here is what each CI job exercises:

.. list-table::
   :header-rows: 1
   :widths: 35 65

   * - CI job
     - Equivalent local command
   * - ``nox``
     - ``nox`` (all default sessions)
   * - ``molecule``
     - ``nox -e molecule``
   * - ``molecule-integration``
     - ``nox -e integration``
   * - ``molecule-roles``
     - ``nox -e roles``
   * - ``ucode-units``
     - ``nox -e ucode_units``
   * - ``ansible-test`` (sanity)
     - ``ansible-test sanity --docker default --python <version>``
   * - ``ansible-test`` (units)
     - ``ansible-test units --docker default --python <version>``


Further Reading
^^^^^^^^^^^^^^^

- `Molecule documentation <https://ansible.readthedocs.io/projects/molecule/>`_
- `utest documentation <https://m00qek.github.io/utest/>`_
- `andebox documentation <https://github.com/russoz/andebox>`_
- `OpenWrt container images <https://github.com/openwrt/docker>`_
- `nox documentation <https://nox.thea.codes/>`_
- `antsibull-nox documentation <https://docs.ansible.com/projects/antsibull-nox/>`_
- :ref:`ansible_collections.community.openwrt.docsite.ucode_mod_dev_guide`


.. versionadded:: 1.3.0
