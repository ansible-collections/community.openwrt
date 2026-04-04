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
collection.  Read on for the full picture.

.. contents::
   :local:
   :depth: 2

Quickstart
^^^^^^^^^^

Already familiar with Molecule and just need the commands?  Here you go.

**One-time setup** (skip if using the dev container):

.. code-block:: console

   $ python3 tests/utils/setup-molecule

**Run a single module's integration test:**

.. code-block:: console

   $ TEST_TARGET_ROLE=<target> molecule test -s integration_test

**Run the default collection scenario:**

.. code-block:: console

   $ molecule test -s default

**Run all module integration tests:**

.. code-block:: console

   $ molecule test --scenario-name molecule_integration

**Run a single role scenario:**

.. code-block:: console

   $ cd roles/<role>
   $ molecule test -s <scenario>

**Sanity / unit tests:**

.. code-block:: console

   $ ansible-test sanity --docker default --python 3.13
   $ ansible-test units --docker default --python 3.13

Everything else is explained in the sections below.


What is Molecule?
^^^^^^^^^^^^^^^^^

`Molecule <https://ansible.readthedocs.io/projects/molecule/>`_ is a testing framework
for Ansible roles and collections.  It automates the full test lifecycle: spin up one or
more instances (containers or VMs), run your playbooks against them, then tear the
instances down.

A few concepts worth knowing before you dive in:

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Concept
     - Meaning
   * - **Scenario**
     - A named test configuration, stored in a ``molecule/<scenario>/`` directory.
       Each scenario has its own ``molecule.yml`` (driver and platform settings) and a
       ``converge.yml`` playbook that Molecule runs against the instances.
   * - **Driver**
     - The backend that creates instances.  This collection uses the ``docker`` driver.
   * - **Platform**
     - A container (or VM) definition — image, name, startup command.  Each OpenWrt
       version becomes one platform.
   * - **Converge**
     - The step where Molecule runs your playbook against all running instances.
   * - **``molecule test``**
     - Runs the full default sequence: create → converge → destroy.  Safe for CI.
   * - **``molecule converge``**
     - Runs only the converge step against already-running instances.  Handy when
       iterating on a change: create once, converge many times, destroy when done.

Molecule also supports a global configuration file at ``~/.config/molecule/config.yml``.
Any settings in that file are merged into *every* scenario Molecule runs on your machine.
This collection uses that mechanism to share the OpenWrt platform list across all its
scenarios — more on that in the next section.

For a deeper introduction, see the
`official Molecule documentation <https://ansible.readthedocs.io/projects/molecule/>`_.


Overview
^^^^^^^^

The test suite is built around Molecule, which orchestrates Docker containers running
actual OpenWrt root filesystem images.  This means your tests exercise real OpenWrt
userspace — BusyBox shell, ``uci``, ``opkg``, etc. — rather than mocks.

The collection tests fall into two broad categories:

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Category
     - What it covers
   * - **Integration tests** (modules)
     - Tests under ``tests/integration/targets/<module>/`` that verify each module's
       behaviour on a live OpenWrt container.
   * - **Role tests**
     - Molecule scenarios under ``roles/<role>/molecule/<scenario>/`` that test the
       bundled Ansible roles.

Both categories use real OpenWrt container images.  The list of tested OpenWrt versions
is maintained in a single file: ``extensions/molecule/openwrt-versions.yml``.

Molecule has native support for Ansible collections and automatically discovers scenarios
placed under ``extensions/molecule/``, so all collection-level tests can be invoked from
the repository root without changing directories.


Setting Up Your Environment
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Before running any Molecule tests you need to generate a shared Molecule configuration
file.  This is done by the helper script ``tests/utils/setup-molecule``.

What the script does
""""""""""""""""""""

The script reads ``extensions/molecule/openwrt-versions.yml``, builds a list of Docker
platform entries (one per OpenWrt version), and writes the result to
``~/.config/molecule/config.yml``.  Molecule automatically merges that file into every
scenario it runs, so all scenarios inherit the correct platforms without duplicating them
in individual ``molecule.yml`` files.

To run it manually:

.. code-block:: console

   $ python3 tests/utils/setup-molecule

You should see output like:

.. code-block:: console

   Ingesting versions from /path/to/extensions/molecule/openwrt-versions.yml
   Versions loaded: ['25.12.2', '24.10.6', '23.05.6']
   Writing file /home/<you>/.config/molecule/config.yml:
   ...

.. note::

   If you are using the **dev container**, this step is done for you automatically as
   part of ``setup.sh``.  You only need to run it manually when working outside the
   dev container, or after updating ``openwrt-versions.yml``.

.. warning::

   The script writes to ``~/.config/molecule/config.yml`` in your **home directory**.
   Because Molecule merges that file into *every* scenario it runs, the OpenWrt platform
   list will appear in any Molecule execution on your machine — not just those from this
   collection.  If you work on other projects that use Molecule, be mindful of this file:
   re-run the script (or edit the file manually) whenever you need to switch between
   different platform configurations.


Running Individual Integration Tests
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Single module
""""""""""""""

Run a single module's integration test using the ``integration_test`` scenario.
The scenario reads the target name from the ``TEST_TARGET_ROLE`` environment variable:

.. code-block:: console

   $ TEST_TARGET_ROLE=uci molecule test -s integration_test

This runs the target against all OpenWrt platform versions defined in
``openwrt-versions.yml``.


Running All Plugin Integration Tests at Once
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The ``molecule_integration`` scenario runs every plugin integration target in a single
pass — the same thing CI does.  It does **not** include role tests
(see `Running Role Tests`_ for those).

.. code-block:: console

   $ molecule test -s molecule_integration

The full list of targets is defined in ``extensions/molecule/molecule_integration/converge.yml``.


Running Role Tests
^^^^^^^^^^^^^^^^^^

Each bundled role has its own Molecule scenarios alongside the role itself:

.. code-block:: text

   roles/
     <role>/
       molecule/
         <scenario>/
           molecule.yml   ← dummy; config comes from ~/.config/molecule/config.yml
           converge.yml

Run a single scenario from inside the role directory:

.. code-block:: console

   $ (cd roles/<role>; molecule test -s <scenario>)

For example, for the ``init`` role:

.. code-block:: console

   $ (cd roles/init; molecule test -s install_recommended_true)

The ``molecule.yml`` files in role scenarios are intentionally minimal (they contain only a
comment).  The actual platform list is injected from the global
``~/.config/molecule/config.yml`` written by ``setup-molecule``.


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

By default, nox creates a fresh virtual environment for each session.  Add ``-R`` to
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
     - ``molecule test -s default``
   * - ``molecule-integration``
     - ``molecule test -s molecule_integration``
   * - ``molecule-roles``
     - ``(cd roles/<role> && molecule test -s <scenario>)``
       for every role scenario
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
