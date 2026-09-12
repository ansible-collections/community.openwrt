..
  Copyright (c) Ansible Project
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.mod_dev_guide:


Community OpenWrt Module Developer Guide
========================================

If you are reading this, it is likely you are already an user of the collection and want to extend it:
Awesome! Everyone is welcome to contribute!
This collection is based on the Ansible role ``gekmihesg.openwrt`` and as such it does not require Python
installed on the OpenWrt devices - all the code is written in plain shell scripts.

There are skills that are going to help you immensely if you intend to work on Ansible modules for ``community.openwrt``:

* A fair understanding of how modules work in general. Having contributed with Python-based modules will definitely help you.
* A very good experience with shell scripts and its idiosyncrasies.

You are welcome to use AI to help you write modules, roles and anything - but remember that your code will be your responsibility,
so you MUST understand what is happening in it.

Challenges
^^^^^^^^^^^

Using shell-based modules on the target instead of Python brings a few practical drawbacks that developers should keep in mind:

* The AnsiballZ framework, used to transfer the Python modules to the target destination, has limited support for shell scripts.
  In particular, if the module script uses ``source`` or ``.`` to include another file that does not exist in the target,
  that dependency is not recognized by Ansible and the dependency script is **not** transferred over.
  Therefore, there is no ``module_utils`` available to the shell module.

  * There is no Python standard library with all its functions, only the commands available in the router's shell.
  * There is no ``module_utils``, so all the convenience of the ``AnsibleModule`` class is not available.
    As a consequence, there is no consolidated mechanism to validate parameters or to
    `enforce dependencies between options <https://docs.ansible.com/projects/ansible/latest/dev_guide/developing_program_flow_modules.html#dependencies-between-module-options>`_.

* Many sanity checks are useless for shell-scripts, for example the cross-checking of documented parameters and those declared in the code, as they do in Python.
* Debuggability is harder: stack traces and structured errors are not available; logs depend on ``set -x`` tracing and are noisy.
* Ansible unit tests are base in ``pytest`` and it is not trivial to run sophisticated shell-script tests in that scenario.
* Both unit and integration tests are impacted by the fact that this collection requires non-standard container images to run the tests.
* Testing is slower and narrower: meaningful coverage needs molecule/container. Cross-version verification takes time.
* Security hardening is manual: input sanitization, temporary file handling, and permission fixes (see wrapper script) must be explicitly coded; Python's safer defaults and libraries are absent.

Most of these challenges have not been solved yet, some may never be. But they clearly show that there is a lot of room for improvements.


Runtime architecture
^^^^^^^^^^^^^^^^^^^^^

The first thing to solve is to actually make it possible to run modules written as shell-scripts. Without that, there are no modules at all.
Ansible modules are programs that, when executed, read JSON content from their ``stdin`` and write back results (successful or otherwise) as
JSON content to their ``stdout`` file descriptor.

Handling ``stdin`` and ``stdout`` is not a problem for shell scripts, but there is no native mechanism to handle JSON content.
For this OpenWrt has a builtin utility named ``jshn`` (JSON SHell Notation) that can be used by shell scripts. See more about it below.

The next problem is: how to include a "standard shell library" in every script? The ``gekmihesg.openwrt`` role solved that by creating coding the
"standard library" in this ``wrapper.sh`` script and "monkeypatching" the default action plugin in Ansible, to _inject_ the module script
into the wrapper, upon use.

This collection takes a slightly different approach. Instead of patching Python code and shell code during runtime:

* ``wrapper.sh`` has been made into a module, meaning it was moved to the directory ``plugins/modules`` and, as a "module",
  it now reads JSON input, where it expects to find a parameter containing the name of a script.
  Instead of patching, it sources the module script, and then run some standard lifecycle functions from it.
* a reusable class ``OpenwrtActionBase`` derived from ``ActionBase`` was created (in ``plugins/plugin_utils``), and
  every single module in this collection **MUST** also implement a companion action plugin based on that class.
  That class overrides the ``run()`` method and implements an elegant solution:

    1. Find the module (shell-script) file on the control node
    2. Transfer that module to a temporary location on the target node (OpenWrt)
    3. Instead of executing the original named module, runs the wrapper module instead, passing the path
       of the temporary file as a proper Ansible parameter
    4. The wrapper executes, including the original module


Wrapper helper library
^^^^^^^^^^^^^^^^^^^^^^^

The ``wrapper.sh`` script exposes a compact library of functions and conventions that shell-based modules
must use to parse parameters, produce results, handle files, and implement idempotent behaviour.
The following sections group those helpers by functional domain and explain their intended use.

Lifecycle
""""""""""

Every shell module executed via the wrapper MUST implement the canonical lifecycle functions. The wrapper will invoke these functions in a strict sequence; modules must not rely on ad-hoc top-level execution.

  init()
      Perform setup. If ``init`` fails, exit non‑zero to stop execution.

  validate()
      Perform parameter validation and any checks that should prevent ``main`` from running.

  main()
      Implement the module's primary behaviour here.

  cleanup()
      Remove temporaries and perform finalization.

Example (module skeleton):

.. code-block:: sh

  init() {
      PARAMS="name/s state/s"
  }

  validate() {
      [ "$state" != "present" -a "$state" != "absent" ] && fail "state must be one of: present, absent"
  }

  main() {
      # do work here
      changed
      json_add_string msg "ok"
  }

  cleanup() {
      # remove temporaries
      :
  }


Parameter parsing
""""""""""""""""""

Module parameters must be declared by setting the ``PARAMS`` variable.
It is a string, with a space-delimited list of parameters declared in a specific format::

  NAME[=ALIAS1[=ALIAS2[=...]]]/TYPE/[REQ]/DEFAULT

Example (from ``sysctl``):

.. list-table::
  :header-rows: 1
  :widths: 50 50

  * - shell-based module
    - Python equivalent
  * - .. code-block:: sh

        PARAMS="
            ignore_errors=ignoreerrors/bool
            name=key/str/r
            reload/bool//true
            state/str//present
            sysctl_file/str
            sysctl_set/bool//false
            value=val/str
        "
    - .. code-block:: python

        argument_spec=dict(
            ignore_errors=dict(type="bool", aliases=["ignoreerrors"]),
            name=dict(type="str", required=True, aliases=["key"]),
            reload=dict(type="bool", default=True),
            state=dict(type="str", default="present"),
            sysctl_file=dict(type="str"),
            sysctl_set=dict(type="bool", default=False),
            value=dict(type="str", aliases=["val"]),
        ),

It is recommended that the ``PARAMS`` variable is set outside any function in the script.
The actual parsing happens by calling the shell function ``_parse_params()``, and the wrapper
automatically does that after the script is sourced. If you define it inside ``init()``,
then your code must make sure ``_parse_params()`` is called after ``PARAMS`` is defined.

.. note::

  The "type" field accepts the values and equivalences:

  * ``any``
  * ``s``, ``str``, ``string``
  * ``i``, ``int``, ``integer``
  * ``b``, ``bool``, ``boolean``
  * ``f``, ``d``, ``float``, ``double``
  * ``l``, ``a``, ``list``, ``array``
  * ``o``, ``h``, ``obj``, ``object``, ``hash``, ``map``

.. note::

  There is no support for specifying sub-options.

.. admonition:: TO-DO

  Write about ``FILE_PARAMS``


JSON helpers
"""""""""""""

As mentioned above, OpenWrt provides ``jshn`` to help parsing and generating JSON content.
Check `jshn <https://openwrt.org/docs/guide-developer/jshn>`_ for more information on how
to use it.

When writing modules, you will not need to worry about parsing, and you do not need to use it for producing
return values when using the standard mechanism for generating result values (see below).
You will possibly want to use it to generate content is using the custom mechanism.
Regardless of that, it is a nice addition to the toolbox.

Example (use JSON helpers in ``main``):

.. code-block:: sh

  main() {
      json_set_namespace result
      json_init
      json_add_boolean changed 0
      json_add_string msg "All good"
      json_add_object ansible_facts
      json_add_string my_fact "value"
      json_close_object
      result=$(json_dump)
  }

.. seealso::

  * `jshn.sh - Handling Nested Loops <https://medium.com/@bear_with_me/jshn-sh-handling-nested-loops-ebf1501d7aa7>`_
  * `jshn: shell library to work with JSON <https://github.com/stokito/jshn-jsonc/tree/master>`_ (GitHub repository for ``jshn``)


Result values construction
"""""""""""""""""""""""""""

Standard Mechanism
------------------

Similar to the ``PARAMS`` variable, the return values must be declared in the ``RESPONSE_VARS`` variable.
It should also be declared outside any function in the module, and its expected content is a string,
with a space-delimited list of return value names in the following format::

  NAME[/TYPE[/ALWAYS]]

If the type is specified, then the return value will be rendered using the corresponding type in the resulting JSON output.
Unlike Python or JSON, there is no "null" value, such as ``None`` or ``null`` to represent the lack of a value.
The next best thing is to have a variable with no content, as in an empty string::

  val=    # in shell this is
  val=""  # the same as this

Empty variables are not included in the output by default.
However, if the ``ALWAYS`` element is passed (usually the letter ``a`` is used, see example),
then the value is included regardless of being empty or not.

The name correspond to shell variable names, and the actual return value for each one of them is the
value of the namesake variable itself.

Example (from ``community.openwrt.command``):

.. code:: sh

  RESPONSE_VARS="
      start
      end
      delta
      cmd
      stdout/str/a
      stderr/str/a
      rc/int/a
  "

The value of the shell variables ``start``, ``end``, etc will be passed as return values of the module.
Note that ``stdout``, ``stderr`` and ``rc`` are typed, and they are always returned, which is expected
of the ``command`` module.

.. note::

  There is no support for specifying ``contains`` elements of return values of the type ``dict``.

.. admonition:: TO-DO

  Write about ``FACT_VARS``


Custom Mechanism
-----------------

If you want to have fine-grained control of the output, you can add:

.. code:: sh

  NO_EXIT_JSON=1

To your script, and it will refrain from generating the JSON output automatically.
In that case, the module is responsible for writing the output JSON content to ``stdout``.

See the file ``plugins/modules/setup.sh`` for an example of that mechanism.


Additional constructs
----------------------

The wrapper script also provides some convenience constructs that affect the outcome and the exit flow
of the module.

  changed
      Command receives no parameter. Once called, the module will register ``changed=true`` in its output.

  fail
      Command arguments are made into a string that becomes the return value ``msg``,
      and the module returns a non-zero exit code indicating failure.

  try
      Command will attempt to execute its arguments as a command in itself, and it invokes ``fail`` if the
      command is not successful. Example (from ``copy``):

      .. code:: sh

        try mkdir "$p"

      If the ``mkdir`` command fails, then the entire module fails.

  final
      Similar to ``try``, but if the command is successful, then the module exits indicating success.


File, checksum and base64 utilities
""""""""""""""""""""""""""""""""""""

.. admonition:: TO-DO

  To be done.

.. Common file and checksum tasks are implemented as helpers so modules can be idempotent:

.. - ``_get_file_attributes`` / ``set_file_attributes``: gather permission/owner/mode information and apply changes; ``set_file_attributes`` respects check mode and marks ``changed`` when differences are applied.
.. - ``backup_local``: create a timestamped local copy of a file before overwriting it.
.. - ``dgst`` / ``md5``: compute checksums using available system utilities (falls back to openssl when possible); used by modules that need checksum verification.
.. - ``base64``: wrapper to perform Base64 encoding with available utilities or fallbacks.

.. Example (backup, checksum and install in `main`):

.. .. code-block:: sh

..   main() {
..     old_backup=$(backup_local /etc/config/foo) || true
..     checksum_before=$(md5 /etc/config/foo 2>/dev/null || echo "")
..     # write new content to temp
..     printf '%s' "$new_content" > /tmp/foo.new
..     checksum_after=$(md5 /tmp/foo.new)
..     if [ "$checksum_before" != "$checksum_after" ]; then
..       mv /tmp/foo.new /etc/config/foo || fail "install failed"
..       changed
..     fi
..   }


Pathname helpers
"""""""""""""""""

Utilities to work reliably with paths and symlinks:

  is_abs()
      Test whether a path is absolute.

  abspath()
      Compute an absolute path for a given file (with optional ``-P`` semantics for physical resolution).

  realpath()
      Resolve symlinks to return the canonical path. These helpers make scripts more robust when moving files or resolving included filenames.

Example:

.. code-block:: sh

  main() {
      src="./relative/path"
      abs_src=$(abspath "$src")
      real_src=$(realpath "$abs_src")
      cp "$real_src" /tmp/ || fail "copy failed"
      changed
  }


Diff and change detection
""""""""""""""""""""""""""

.. admonition:: TO-DO

  To be done.


.. The wrapper provides a small diff helper set used by modules that implement textual changes:

.. - ``set_diff``: record ``before`` and ``after`` string values and optional headers; when present, the wrapper includes a ``diff`` object in the final JSON output.
.. - Modules that produce diffs must populate the corresponding ``_diff_before`` and ``_diff_after`` values (or call ``set_diff``) so the final JSON contains useful before/after data for Ansible's reporting.

.. Example (set diff for a textual change inside `main`):

.. .. code-block:: sh

..   main() {
..     _ diff _ before="$(cat /etc/config/foo)"
..     _ diff _ after="${_diff_before/old/new}"
..     set_diff "$_diff_before" "$_diff_after" "before header" "after header"
..     changed
..   }

Check mode and idempotence support
"""""""""""""""""""""""""""""""""""

Modules that support check mode must set the variable:

.. code:: sh

  SUPPORTS_CHECK_MODE=1

Otherwise, the module will automatically bail out if executed in check mode.


.. versionadded:: 0.3.0

Ucode modules
^^^^^^^^^^^^^

Besides the shell-based modules, the collection also ships modules implemented in `ucode
<https://github.com/jow-/ucode>`_, OpenWrt's native scripting language. Ucode is available on
every modern OpenWrt build (with ``fw4``) and provides native JSON handling through the
``uci``, ``ubus`` and ``fs`` ucode modules. This avoids the JSON manipulation issues that
affect the shell/jshn path for very large configurations.

A ucode module is a plain ``.uc`` file in ``plugins/modules/`` plus a ``.yml`` sidecar with
its ``DOCUMENTATION``/``EXAMPLES``/``RETURN`` (there is no ``.py`` file - Ansible reads the
docs from the ``.yml`` sidecar, the same way it does for PowerShell modules). For example,
``uc_uci.uc`` + ``uc_uci.yml``.

Runtime architecture
""""""""""""""""""""

Ucode modules run as ``non_native_want_json`` scripts: Ansible passes the module arguments as
a JSON file whose path is the first command-line argument (``ARGV[0]``); the module prints a
JSON result on ``stdout`` and exits ``0`` on success, non-zero on failure.

A dedicated action plugin (``plugins/plugin_utils/ucode_action.py``,
``UcodeOpenwrtActionBase``) takes care of:

1. Transferring the module ``.uc`` file to the target.
2. Transferring its shared helper library (``plugins/module_utils/ansible_common.uc``) into
   the same remote directory, so the module's relative ``import`` resolves.
3. Writing the arguments as a JSON file and executing ``ucode <module> <args>``.
4. Parsing the JSON printed on ``stdout`` into the Ansible result.

No shell wrapper is involved; JSON is produced and consumed natively by ucode.

Shared helper library
"""""""""""""""""""""

All ucode modules share a single helper library, ``plugins/module_utils/ansible_common.uc``.
It exports (with an ``ac_`` prefix) helpers for the Ansible module contract, argument
coercion, change detection and diff redaction:

  ac_load_args()
      Read and parse the module args from ``ARGV[0]`` (the JSON args file).

  ac_result()
      Build the standard ``{changed, failed, msg}`` result object.

  ac_exit(result, rc) / ac_fail(result, msg)
      Print the result as JSON and exit; mark the result failed.

  ac_bool(v)
      Coerce a JSON value to a boolean (accepts bool, int and ``"true"/"yes"/"1"/"on"``).

  ac_get(obj, key, default)
      Safely read a value with a fallback.

  ac_same(a, b)
      Deep-compare two values (used for idempotency / change detection).

  ac_strip_meta(section)
      Drop UCI meta keys (``.name``, ``.type``, ``.anonymous``, ``.index``) from a cursor
      ``get_all`` section so it compares cleanly against a desired option map.

  ac_redact(before, after, redact_keys)
      Mask the values of the listed keys in a diff pair with ``REDACTED`` markers.

  ac_check_mode(args) / ac_trace()
      Read the check-mode flag; return a stack trace (when the optional ``debug`` ucode
      module is present) for error reporting.

A ucode module imports it with:

.. code-block:: js

   import { ac_load_args, ac_result, ac_exit, ac_fail, ac_bool } from './ansible_common.uc';

ucode language notes
""""""""""""""""""""

ucode is ECMAScript-inspired but has its own rules. The hard-learned ones:

- ``'use strict';`` at the top of every module.
- ``export function name(...) {...};`` must end with a semicolon.
- No function hoisting - declare functions before use; no forward declarations.
- No ``throw`` - use ``die()``. No ``String(x)`` - use ``sprintf("%s", x)``.
- Arrays use global helpers: ``push(arr, ...)``, ``sort(arr)``, ``length(arr)`` - there are no
  ``arr.push()`` methods.
- Strings are not ``[]``-indexable - use ``substr(s, i, 1)`` / ``ord(s, i)``.
- ``for (let x in arr)`` yields the elements; over objects it yields the keys. Loop variables
  must be declared with ``let``.
- JSON: decode with ``json(str)``, encode with ``sprintf("%J", obj)``.
- ``uci`` option values are strings; coerce with ``ac_bool``/``int``/``sprintf`` as needed.

Linting
"""""""

Ucode modules are linted with a small Node script, ``tests/uc-lint.mjs``. It uses Node's ESM
parser for a syntax check (ucode is ECMAScript-based) and enforces the ucode-specific rules
above (the ``;`` terminator on exported functions, global array helpers, no ``[]``-indexing of
strings, no forward-declared exports). Run it with:

.. code-block:: console

   $ node tests/uc-lint.mjs

or via the ``ucode-lint`` nox session or the ``ucode-lint`` pre-commit hook.

Check mode and diff support
"""""""""""""""""""""""""""

Ucode modules honour check mode (skip persisting changes when ``_ansible_check_mode`` is set)
and diff mode (produce a structured ``diff`` when ``_ansible_diff`` is set and the task has
``diff: true``). The ``ac_result``/``ac_exit`` helpers carry the ``changed``/``failed``/``msg``
contract automatically.

.. versionadded:: 1.9.0
