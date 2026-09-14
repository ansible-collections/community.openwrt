..
  Copyright (c) 2026, Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.ucode:

Ucode reference
===============

This page is the single source of truth for developing ucode modules in this collection. It
points to the official ucode documentation and records the hard-learned rules that apply on the
OpenWrt releases the collection supports.

Official documentation
----------------------

- `ucode Reference Documentation <https://ucode.mein.io/>`_ — language, syntax, memory
  management, arrays, dictionaries, and the standard library modules (``core``, ``fs``,
  ``log``, ``math``, ``ubus``, ``uci``, ``uloop``, ...).
- `ucode source (GitHub) <https://github.com/jow-/ucode>`_ — the interpreter and the
  ``libucode`` C API.

Version caveat
^^^^^^^^^^^^^^

The reference site documents the **latest** ucode (OpenWrt ``master``). The OpenWrt releases the
collection targets ship an **older** ucode that is missing some of the newer constructs. Known
differences on OpenWrt **25.12.x**:

- **No forward declarations / function hoisting.** Functions must be defined before they are
  used; there is no ``export function name;`` forward declaration. The reference documentation
  (master) shows examples that rely on hoisting that will **not** run on 25.12.
- When in doubt, test on the oldest supported target (currently ``25.12``) rather than assuming
  the reference examples work.

Collection conventions
----------------------

A ucode module is a ``.uc`` file in ``plugins/modules/`` plus a ``.yml`` sidecar with
``DOCUMENTATION``/``EXAMPLES``/``RETURN``; there is no ``.py``. Modules run as
``non_native_want_json`` scripts: Ansible passes the args as a JSON file whose path is
``ARGV[0]``, and the module prints a JSON result on ``stdout``.

The reusable action base at ``plugins/plugin_utils/ucode_action.py``
(``UcodeOpenwrtActionBase``) transfers the module and its helper library into the same remote
directory so the module's relative import resolves, then executes ``ucode <module> <args>`` and
parses the JSON result. No shell wrapper is involved.

Hard-learned ucode rules
------------------------

- ``'use strict';`` at the top; ``#!/usr/bin/ucode`` shebang and a ``WANT_JSON`` marker.
- JSON: decode with ``json(str)``, encode with ``sprintf("%J", obj)``. There is no
  ``serialize()``.
- ``export function name(...) {...};`` must end with a semicolon. Functions are not hoisted:
  declare before use; no forward declarations; no ``throw`` (use ``die()``).
- Arrays use global helpers: ``length(arr)``, ``push(arr, ...)``, ``sort(arr)``. There are no
  ``arr.push()``/``arr.sort()`` methods.
- Strings are not ``[]``-indexable — use ``substr(s, i, 1)`` / ``ord(s, i)``.
- ``for (let val in arr) {}`` yields the **elements** of an array; over objects it yields the
  **keys** (``for (let k in obj) {}`` — fetch the value with ``obj[k]``). Loop variables must be
  declared with ``let``. The two-variable destructuring form (``for (k, v in dict) {}``) is
  **not** supported on OpenWrt 25.12.
- No ``String(x)`` global — use ``sprintf("%s", x)``.
- Prefer ``${template}`` literals over ``+`` concatenation when building strings for
  readability (e.g. error messages); keep ``+`` for short shell command fragments.
- Dicts merge natively with the spread operator: ``{ ...base, ...override }`` (later wins).
- Test key presence with ``exists(obj, key)`` rather than ``obj[key] == null`` when you need to
  distinguish a present-but-null value from an absent key.
- ``uci``: ``import { cursor } from 'uci'; const u = cursor();`` —
  ``get/get_all/set/foreach/add/save/commit``. ``set(config, section, type)`` creates a named
  section; ``add`` requires the config to be explicitly ``load()``ed first; ``save()`` persists
  changes as a delta so a subsequent module invocation (new process) sees them.
- Check mode: the args include ``_ansible_check_mode``; compute the diff/changed but skip
  ``save``/``commit``.
- Idempotency: strip UCI meta keys (``.name``, ``.type``, ``.anonymous``, ``.index``) from
  ``get_all`` output before comparing; compare via sorted-key equality (``sprintf("%J", ...)``),
  not raw object equality.

Shared helper library
---------------------

All ucode modules share ``plugins/module_utils/_ansible_common.uc``, imported under the ``ac``
namespace. It exports helpers for the Ansible module contract, argument coercion, change
detection and diff redaction:

.. code-block:: text

  ac.load_args()
      Read and parse the module args from ``ARGV[0]`` (the JSON args file).

  ac.new_result()
      Build the standard ``{changed, failed, msg}`` result object.

  ac.exit_json(result) / ac.fail_json(result, msg)
      Print the result as JSON and exit; mark the result failed.

  ac.coerce_to_bool(v)
      Coerce a JSON value to a boolean (accepts bool, int and ``"true"/"yes"/"1"/"on"``).

  ac.coerce(v, type)
      Coerce a value to ``'str'``, ``'path'``, ``'bool'``, ``'int'``, ``'float'``,
      ``'list'``, ``'dict'`` or ``'raw'``; returns ``null`` when the value cannot
      be coerced.

  ac.validate_argument_spec(args, spec)
      Declaratively validate/coerce input args against a spec dict, mirroring
      Ansible's `argument_spec <https://docs.ansible.com/ansible/latest/dev_guide/developing_program_flow_modules.html#argument-spec>`_.
      Each entry supports ``type``, ``elements`` (for lists), ``default``,
      ``required``, ``choices``, ``aliases``, ``options`` (nested sub-spec for
      dicts and lists of dicts) and ``apply_defaults``. Returns ``{ok, values,
      error}``; call ``fail_json`` with the error when ``ok`` is false.
      Ansible's dependency checks (``mutually_exclusive``/``required_*``) and
      the ``json``/``jsonarg``/``bytes``/``bits`` types are not implemented.

  ac.get_value(obj, key, default)
      Safely read a value with a fallback.

  ac.is_equal(a, b)
      Deep-compare two values (used for idempotency / change detection).

  ac.strip_meta(section)
      Drop UCI meta keys (``.name``, ``.type``, ``.anonymous``, ``.index``) from a cursor
      ``get_all`` section so it compares cleanly against a desired option map.

  ac.redact(before, after, redact_keys)
      Mask the values of the listed keys in a diff pair with ``REDACTED`` markers.

  ac.render_template(str, scope)
      Render a Jinja-style ucode template string (``{{ ... }}`` / ``{% ... %}``) against a
      scope dict; returns the rendered string (empty on error).

  ac.upsert_section(u, config, sid, sec_type, want, opts)
      Idempotently write a named UCI section (compares, writes only on change, honours check
      mode); returns ``{before, after, changed}``.

  ac.push_diff(out, enabled, header, before, after)
      Append a ``{before, after}`` entry to ``out.diff`` for Ansible ``--diff`` display
      (no-op when ``enabled`` is false).

  ac.is_check_mode(args)
      Read the check-mode flag (``args._ansible_check_mode``) and return it as a boolean.

  ac.is_diff_enabled(args)
      Read the diff-mode flag (``args._ansible_diff``) and return it as a boolean.

  ac.trace()
      Return a stack trace for error reporting (when the optional ``debug`` ucode
      module is present); empty string otherwise.

A ucode module imports it with:

.. code-block:: js

   import * as ac from './_ansible_common.uc';

Linting
-------

Ucode modules are linted with ``tests/uc-lint.mjs``, which runs the `ucode-lsp
<https://github.com/NoahBPeterson/ucode-lsp>`_ checker (type inference, flow analysis,
null-safety, unused imports) gated to the OpenWrt ``25.12`` target, plus the ``;`` terminator
rule that real ucode requires and the LSP does not flag. It stages ``_ansible_common.uc`` next
to each module (mirroring how the action plugin transfers it) so relative imports resolve.
Run it with:

.. code-block:: console

   $ node tests/uc-lint.mjs

or via the ``ucode_lint`` nox session or the ``ucode-lint`` pre-commit hook.

The helper library and argument-handling logic are unit-tested with real ucode in an OpenWrt
container: ``tests/unit/ucode/`` (``test_*.uc`` scripts staged with ``_ansible_common.uc``) run
via the ``ucode_unit`` nox session or ``tests/unit/ucode/run.sh``.

Check mode and diff support
---------------------------

Ucode modules honour check mode (skip persisting changes when ``_ansible_check_mode`` is set)
and diff mode (produce a structured ``diff`` when ``_ansible_diff`` is set and the task has
``diff: true``). The ``ac.new_result``/``ac.exit_json`` helpers carry the
``changed``/``failed``/``msg`` contract automatically.
