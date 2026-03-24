===============================
Community OpenWrt Release Notes
===============================

.. contents:: Topics

v1.2.0
======

Release Summary
---------------

Regular & bugfix release.

Minor Changes
-------------

- copy action plugin - remove redundant code (https://github.com/ansible-collections/community.openwrt/pull/192).
- openwrt_action plugin utils - remove redundant code (https://github.com/ansible-collections/community.openwrt/pull/192).

Bugfixes
--------

- copy - fix destination file name if ``dest`` is a directory (https://github.com/ansible-collections/community.openwrt/pull/165).
- openwrt_action plugin utils - exception classes were not calling the parent's constructor correctly (https://github.com/ansible-collections/community.openwrt/pull/161).

New Modules
-----------

- community.openwrt.group - Add or remove groups.

v1.1.0
======

Release Summary
---------------

See https://github.com/ansible-collections/community.openwrt/blob/main/CHANGELOG.md for all changes.

Minor Changes
-------------

- init role - enable check mode in the task checking package manager compatibility (https://github.com/ansible-collections/community.openwrt/pull/136).
- nohup - use ``init()`` function to declare parameters (https://github.com/ansible-collections/community.openwrt/pull/131).
- setup - collect ``ansible_date_time`` facts as well (https://github.com/ansible-collections/community.openwrt/issues/52, https://github.com/ansible-collections/community.openwrt/pull/138).
- setup - report ``ansible_pkg_mgr`` fact with the detected package manager used (https://github.com/ansible-collections/community.openwrt/pull/136).

Bugfixes
--------

- ping - module code must indicate it does not support check mode (https://github.com/ansible-collections/community.openwrt/pull/132).
- setup - generate an empty factoid when the underlying command ``ubus call`` returns empty (https://github.com/ansible-collections/community.openwrt/issues/149, https://github.com/ansible-collections/community.openwrt/pull/151).

New Modules
-----------

- community.openwrt.package_facts - Gather package facts in OpenWrt systems.
- community.openwrt.tempfile - Creates temporary files and directories on OpenWrt nodes.

v1.0.0
======

Release Summary
---------------

First GA release of the community.openwrt collection.

v0.4.0
======

Release Summary
---------------

Establish mechanism for integration testing.
Add support to the ``apk`` package manager.
Modules now have lifecycle functions ``init()`` and ``validate()``.

Minor Changes
-------------

- command - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- copy - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- file - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- lineinfile - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- opkg - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- service - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- slurp - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- stat - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- sysctl - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- uci - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).
- wrapper - use functions ``init()`` and ``validate()`` (https://github.com/ansible-collections/community.openwrt/issues/47, https://github.com/ansible-collections/community.openwrt/pull/67).

New Modules
-----------

- community.openwrt.apk - Manage packages with apk on OpenWrt.

v0.3.0
======

Release Summary
---------------

Add ``.devcontainer`` setup.
Create User and Module Dev Guides.
Generate collection docs in GitHub.
Simplify collection-level molecule tests.
Rename setup role to ``community.openwrt.init``.

v0.2.0
======

Release Summary
---------------

Use action plugins to "wrap" shell-based modules.
Update ``build_ignore`` in ``galaxy.yml``.
Move module docs to ``.py`` files.
Mark ``shell=ash`` for ``shellcheck``.

Minor Changes
-------------

- command - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- command action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- copy - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- copy action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- file - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- file action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- lineinfile - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- lineinfile action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- nohup - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- nohup action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- openwrt_action plugin utils - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- opkg - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- opkg action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- ping - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- ping action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- service - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- service action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- setup - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- setup action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- slurp - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- slurp action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- stat - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- stat action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- sysctl - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- sysctl action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- uci - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- uci action plugin - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).
- wrapper - revamp the shell wrapping mechanism (https://github.com/ansible-collections/community.openwrt/pull/14).

New Modules
-----------

- community.openwrt.wrapper - Internal wrapper module for OpenWrt shell\-based modules.

v0.1.0
======

Release Summary
---------------

This is the first release of the ``community.openwrt`` collection.
The code in this collection was mostly brought over from gekmihesg.openwrt (Ansible role).
