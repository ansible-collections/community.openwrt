..
  Copyright (c) 2026, Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.testing_guide:

Testing Guide
=============

This guide explains how to run and write tests for the ``community.openwrt`` collection.
Because the modules in this collection run as shell scripts on real OpenWrt devices (or
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

**Sanity / unit tests:**

.. code-block:: console

   $ ansible-test sanity --docker default --python 3.13
   $ ansible-test units --docker default --python 3.13

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

The collection tests fall into two broad categories:

   Integration tests (modules)
       Tests under ``tests/integration/targets/<module>/`` that verify each module's
       behaviour on a live OpenWrt container.

   Role tests
       Molecule scenarios under ``roles/<role>/molecule/<scenario>/`` that test the
       bundled Ansible roles.

Both categories use real OpenWrt container images. The list of tested OpenWrt versions
is maintained in a single file: ``tests/molecule/openwrt-versions.yml``.

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
``tests/molecule/openwrt-versions.yml``.


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
           molecule.yml   ← minimal; platforms come from tests/molecule/openwrt-versions.yml
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
``tests/molecule/openwrt-versions.yml`` by the shared ``create.yml`` playbook.


Sanity and Unit Tests
^^^^^^^^^^^^^^^^^^^^^

These use the standard Ansible tooling and are not Molecule-based.

Sanity:

.. code-block:: console

   $ ansible-test sanity --docker default --python 3.13

Unit tests:

.. code-block:: console

   $ ansible-test units --docker default --python 3.13

`andebox <https://github.com/russoz/andebox>`_ is a convenience wrapper around
``ansible-test`` that handles the collection path setup for you, so either tool works.

See the :ref:`ansible_collections.community.openwrt.docsite.mod_dev_guide` for more
on what the sanity checks cover.

shellcheck and ignore files
""""""""""""""""""""""""""""

Because this collection is largely shell code, the ``shellcheck`` sanity check is
particularly relevant. When ``shellcheck`` flags an issue that cannot or should not be
fixed, the correct way to suppress it is to add an entry to the appropriate
``tests/sanity/ignore-X.Y.txt`` file — **never** use inline ``# shellcheck disable=``
directives inside the module files themselves.

Some project-wide suppressions live in ``.shellcheckrc`` at the repository root.

To regenerate the ignore-file entries systematically, use the helper script
``tests/utils/regen-shellcheck-ignores``. It strips all existing ``shellcheck`` lines
from every ``ignore-X.Y.txt`` file, runs the check for each supported ansible-core
version, and appends the new failures (with descriptions from the ``shellcheck`` wiki)
back to the appropriate ignore files.

.. code-block:: console

   $ python3 tests/utils/regen-shellcheck-ignores

Run this after adding or significantly modifying shell files, or whenever the set of
supported ansible-core versions changes.


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
   * - ``ansible-test`` (sanity)
     - ``ansible-test sanity --docker default --python <version>``
   * - ``ansible-test`` (units)
     - ``ansible-test units --docker default --python <version>``


Further Reading
^^^^^^^^^^^^^^^

- `Molecule documentation <https://ansible.readthedocs.io/projects/molecule/>`_
- `andebox documentation <https://github.com/russoz/andebox>`_
- `OpenWrt container images <https://github.com/openwrt/docker>`_
- `nox documentation <https://nox.thea.codes/>`_
- `antsibull-nox documentation <https://docs.ansible.com/projects/antsibull-nox/>`_
- :ref:`ansible_collections.community.openwrt.docsite.mod_dev_guide`
