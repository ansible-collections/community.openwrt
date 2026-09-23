..
  Copyright (c) 2026, Alexei Znamensky (@russoz)
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.ucode_mod_dev_guide:


Community OpenWrt ucode Module Developer Guide
==============================================

This guide is about writing modules for ``community.openwrt`` in `ucode <https://github.com/jow-/ucode>`_.
If you are reading it, you probably already use the collection and want to extend it: Awesome! Everyone is
welcome to contribute!

ucode is OpenWrt's own scripting language. It looks like JavaScript, it is small enough to live on a router,
and - the part that matters here - it speaks JSON natively. Modules written in it hold to the premise of this
collection: the target does not need Python, and the module runs on the device rather than on the controller.

Every OpenWrt release this collection supports carries ``ucode`` in its base image, together with the ``fs``,
``uci``, ``ubus`` and ``math`` modules, so a module can read files, drive UCI and call ubus straight away.

The language gives you JSON in and out with no encoding work, arrays and dictionaries that nest and can be
passed around, and exceptions with ``try``/``catch``.

One word of warning before anything else: ucode is not JavaScript. It is close enough to be readable at a
glance and different enough to trip you up - there are no default values for function parameters, arrays are
manipulated with global functions such as ``push()`` and ``length()``, strings cannot be indexed with ``[]``,
and errors are raised with ``die()`` rather than ``throw``. Knowing JavaScript helps, but do not assume it
carries over: the differences that come up while writing modules are collected in
:ref:`ansible_collections.community.openwrt.docsite.ucode_language_notes`.

Skills that help
^^^^^^^^^^^^^^^^

* A fair understanding of how Ansible modules work in general. Having written Python modules helps the most,
  since some of the idioms here deliberately resemble the ones used on the Python side.
* Enough JavaScript to read ucode comfortably, plus the willingness to check the
  `ucode documentation <https://ucode.mein.io/>`_ when something behaves unexpectedly.
* Familiarity with the OpenWrt userspace - ``uci``, ``ubus``, ``opkg``/``apk``, BusyBox - since that is still
  what a module ends up driving.

You are welcome to use AI to help you write modules, roles and anything else - but remember that your code will
be your responsibility, so you MUST understand what is happening in it.

Target requirements
^^^^^^^^^^^^^^^^^^^

A ucode module runs on the device, so everything it relies on must already be there. In practice that is a
short list, and it is worth knowing where its edges are before writing code against it.

The interpreter is not a concern. ``ucode`` is part of the base image of every OpenWrt release this collection
supports, so nothing needs to be installed for a module to run: on a stock image, or on anything derived from
one, the interpreter is simply present.

A few ucode modules ship with it, and those are the ones a module may import:

* on all supported releases: ``fs``, ``math``, ``uci``, ``ubus``, ``html`` and ``lucihttp``;
* on 25.12 also ``log``, ``uclient`` and ``uloop``.

Importing anything from the second group makes the module fail on older releases, so use it only in a module
that targets 25.12 and above anyway. The versions currently exercised by the test suite are listed in
``tests/molecule/openwrt.yml``; unless a module is deliberately release-specific, write it for the oldest of
them.

Everything else is what the router happens to carry, and the assumptions worth spelling out are:

* Nothing beyond the base image is guaranteed. A module needing an external command or an extra package
  declares it under ``requirements`` in its documentation, just as a Python module does: providing it is the
  user's job, detecting its absence and failing cleanly is the module's.
* Devices are small. Flash is limited and RAM even more so, so reading a whole file into memory or shelling
  out in a loop over a large set of items is a real cost, not a theoretical one.

The control node needs nothing at all: ``ucode`` is never executed there.

Runtime architecture
^^^^^^^^^^^^^^^^^^^^

A ucode module is an ordinary program: it is copied to the target, run there once per host, and judged by what
it prints. Three consequences of that shape how you write it.

**Getting there.** Write every module as two files: the ``.uc`` file that runs on the device, and a companion
action plugin that runs on the control node. The action plugin is mandatory: ``ansible-core`` bundles
``module_utils`` only for Python modules, so a ucode module's dependencies are transferred by its action
plugin.

Declare there every ucode module your module imports symbols from, apart from the ones bundled with the
interpreter. Only what is declared gets transferred, so an import you did not declare may not be available on
the target and the module fails. The form of that declaration is covered further down.

What is declared lands in a temporary directory alongside the module, and the interpreter is started with those
module utils on its search path, so a plain name resolves to one of them:

.. code-block:: text

    import { AnsibleModule } from 'basic';

Importing by path works as it does anywhere else - it names a file, and that file has to be on the target.

**Parameters in.** Read the task's parameters from ``module.params``, keyed by the name you gave them in the
``argument_spec``. They arrive validated: converted to the declared type, defaults filled in, aliases resolved
to the parameter they stand for, and a parameter the user did not set present with a ``null`` value.
Parameters not matching the spec cause the module to fail.

**Results out.** End the module with ``module.exit_json()`` or ``module.fail_json()``, which write the result
as a single JSON object on standard output for ``ansible-core`` to read. Keep that channel clean: print
nothing else to standard output, and put whatever you would want to look at in the result instead. Use
``module.run_command()`` to run commands - it captures their output and hands it to you, leaving standard
output untouched.

Anatomy of a module
^^^^^^^^^^^^^^^^^^^

A module is three files, all named after it. For ``apk`` they are:

* ``plugins/modules/apk.uc`` - the implementation, which runs on the device;
* ``plugins/modules/apk.py`` or ``plugins/modules/apk.yml`` - the documentation, holding ``DOCUMENTATION``,
  ``EXAMPLES`` and ``RETURN``: a Python file carrying nothing but those, or a YAML file of the same name.
  ``ansible-core`` reads either;
* ``plugins/action/apk.py`` - the action plugin, which runs on the control node.

Write the action plugin first, since it is the shortest thing in the collection: derive it from
``UCodeActionBase`` and list the ucode modules to transfer.

.. code-block:: python

    from ansible_collections.community.openwrt.plugins.plugin_utils.ucode_action import UCodeActionBase


    class ActionModule(UCodeActionBase):
        module_utils = ["basic"]

Include ``basic`` in that list whenever the module uses ``AnsibleModule()``, which is to say always.

Give the module itself the shape below: declare the interface, do the work, report the result.

.. code-block:: text

    import { AnsibleModule } from 'basic';

    const module = AnsibleModule({
        argument_spec: {
            name:  { type: 'str', required: true },
            state: { type: 'str', default: 'present', choices: [ 'present', 'absent' ] },
        },
        supports_check_mode: true,
    });

    const params = module.params;

    // ... the work ...

    module.exit_json();

Document the module as you would document any other Ansible module: ``version_added`` takes the version in
``galaxy.yml``, and the ``check_mode`` and ``diff_mode`` attributes state what the module actually supports.
Keep the documentation in step with the ``argument_spec`` by hand - the two are not cross-checked, so a
parameter renamed in one and not the other is only found by someone using it.

A new module also needs an entry in ``.github/BOTMETA.yml`` for each of its files, and an integration test
target under ``tests/integration/targets/``.

The AnsibleModule API
^^^^^^^^^^^^^^^^^^^^^

Call ``AnsibleModule()`` once, at the top of the module. The object it returns is everything the module gets
from the framework:

* ``module.params`` - the validated parameters;
* ``module.check_mode`` and ``module.diff_mode`` - whether the task runs in check mode or diff mode;
* ``module.result`` - the result being built up;
* ``module.run_command()`` - run a command on the device;
* ``module.exit_json()`` and ``module.fail_json()`` - end the module;
* ``module.deprecate()`` - record a deprecation.

Building the result
"""""""""""""""""""

``module.result`` starts with ``changed`` and ``failed`` set to false and an empty ``msg``. Add to it as the
module goes, rather than assembling a dict at the end:

.. code-block:: text

    result.update({ rc: res.rc, stdout: res.stdout, stderr: res.stderr });
    result.changed();

``result.changed()`` marks the task as changed and ``result.changed(false)`` clears it again. Every field you
put in the result is returned to the user, and the ones your module adds should be described in ``RETURN``.
The `common return values <https://docs.ansible.com/projects/ansible/latest/reference_appendices/common_return_values.html>`_
are documented by ``ansible-core`` and do not belong there.

Running commands
""""""""""""""""

``module.run_command()`` returns ``{ rc, stdout, stderr }``:

.. code-block:: text

    let res = module.run_command([ 'apk', 'info', '-e', pkg ]);
    if (res.rc != 0)
        ...

Pass the command as an array. Each element is quoted before the command line is assembled, so a parameter value
containing spaces, quotes or a semicolon is passed through as the single argument it is meant to be. A string
is handed to the shell as written, which buys you pipelines and redirections at the price of quoting everything
yourself - use it only when you need those, and never build it out of parameter values.

Pass ``{ check_rc: true }`` to end the module in failure when the command exits non-zero, with the command's
standard error as the message.

Deprecations
""""""""""""

Deprecating something the module used to do is ``module.deprecate(msg, version)``, where ``version`` is the
version the behavior is removed in. It is mandatory: a deprecation without a removal target is a bug, and the
module fails instead of recording it. The warning reaches the user when the module ends.

Ending the module
"""""""""""""""""

``module.exit_json()`` prints the accumulated result and ends the module, and ``module.fail_json()`` does the
same for a failure. Both take the same argument, and it is optional: a dict, whose fields are merged on top of
the result, or a message, which becomes ``msg``.

.. code-block:: text

    module.exit_json();
    module.exit_json('nothing to do on this host');
    module.fail_json(`failed to install ${pkg}`);
    module.fail_json({ msg: 'could not parse the package metadata', rc: res.rc });

Neither of them returns, so nothing after the call is reached.

Declaring parameters
^^^^^^^^^^^^^^^^^^^^

Declare every parameter the module accepts in the ``argument_spec``. A parameter that is neither declared nor
an alias of something declared fails the module, so the spec is also what keeps a typo in a playbook from
being silently ignored.

Each parameter takes:

* ``type`` - ``str`` (the default), ``bool``, ``int``, ``float``, ``list``, ``dict`` or ``raw``. Values are
  converted to it: ``yes``, ``on`` and ``1`` all reach a ``bool`` parameter as true, a comma-separated string
  reaches a ``list`` parameter as an array, a JSON string reaches a ``dict`` parameter as an object, and
  ``raw`` takes the value as it comes. A value that cannot be converted fails the module.
* ``elements`` - the type of the items of a ``list`` parameter, converted the same way.
* ``required`` - the module fails when the parameter is not supplied.
* ``default`` - the value to use when the parameter is not supplied. Without one, the parameter is ``null``.
* ``choices`` - the values the parameter may take; for a list, every item must be one of them.
* ``aliases`` - other names the user may write. Read the parameter by its declared name, whichever name the
  user wrote.

Checks across parameters
""""""""""""""""""""""""

Relations between parameters are declared next to the ``argument_spec``, not coded by hand:

.. code-block:: text

    const module = AnsibleModule({
        argument_spec: {
            state:   { type: 'str', default: 'present', choices: [ 'present', 'absent' ] },
            src:     { type: 'str' },
            content: { type: 'str' },
            owner:   { type: 'str' },
            group:   { type: 'str' },
        },
        mutually_exclusive: [ [ 'src', 'content' ] ],
        required_if:        [ [ 'state', 'present', [ 'src', 'content' ], true ] ],
        required_together:  [ [ 'owner', 'group' ] ],
        supports_check_mode: true,
    });

* ``mutually_exclusive`` - groups of parameters of which at most one may be given.
* ``required_together`` - groups in which giving one parameter requires all the others.
* ``required_one_of`` - groups of which at least one parameter is required.
* ``required_if`` - conditions of the form ``[ name, value, [ required... ] ]``, requiring those parameters
  when ``name`` holds ``value``. Add ``true`` as a fourth element to require only one of them.
* ``required_by`` - parameters that another parameter requires as soon as it is given.

``mutually_exclusive`` is checked against what the user actually wrote, before defaults are applied, so a
parameter that merely declares a default does not count as given. The other checks run afterwards, on the
complete set, where a default does count. This is how ``ansible-core`` orders them too.

What the spec does not do
"""""""""""""""""""""""""

Some of what an ``argument_spec`` covers in Python has no counterpart here, and reaching for it silently gets
you nothing:

* ``no_log`` does not redact anything. Keep secrets out of the result and out of anything you log.
* Sub-options - a nested ``options`` spec - are not validated. A ``dict`` parameter arrives as it was written.
* ``fallback``, ``apply_defaults`` and the ``path``, ``jsonarg``, ``bytes`` and ``bits`` types are not
  implemented.
* Parameters cannot be deprecated through the spec. Announce the deprecation with ``module.deprecate()``
  instead.

Internal arguments
^^^^^^^^^^^^^^^^^^

Beyond the parameters of the task, ``ansible-core`` sends every module a few arguments of its own. Three of
them reach you as fields of the module object: ``module.check_mode``, ``module.diff_mode`` and
``module.verbosity``.

Check mode
""""""""""

Declare check mode support twice: ``supports_check_mode: true`` in the ``AnsibleModule()`` call, and
``check_mode: support: full`` in the ``attributes`` of the documentation. Without the first, a check-mode run
ends with a skipped result and your code never runs.

Work out what has to change, guard only the change itself, and report it either way:

.. code-block:: text

    if (!is_installed(pkg)) {
        if (!module.check_mode)
            install(pkg);

        result.changed();
    }

A check-mode run must report the same ``changed`` a real run would.

Diff
""""

Build the diff yourself and put it in the result, only when ``module.diff_mode`` is set:

.. code-block:: text

    if (module.diff_mode)
        result.update({ diff: { before: before_text, after: after_text } });

State what the module supports in the ``diff_mode`` attribute of the documentation.

Verbosity
"""""""""

``module.verbosity`` is the number of ``-v`` flags the user passed, zero when none. Use it to decide how much
detail to put in the result, never to print.

Idempotency
^^^^^^^^^^^

Aim for a module that can be run again and again and only does something the first time. Read the current
state before touching anything, act only where it differs from what the task asks for, and report ``changed``
only for what you actually changed.

That is what makes a playbook safe to re-run, and it is what the integration tests look for: every target runs
its tasks twice and asserts that the second run changes nothing.

Failing
^^^^^^^

End a module that cannot do its job with ``module.fail_json()``, saying in ``msg`` what failed in the user's
terms - the file that is not there, the package that could not be installed:

.. code-block:: text

    let info = stat(path);
    if (info == null)
        module.fail_json(`${path} does not exist`);

Add whatever lets the user act on the failure. When it comes from a command, that is its ``rc`` and its
output:

.. code-block:: text

    module.fail_json({ msg: `failed to install ${pkg}`, rc: res.rc,
                       stdout: res.stdout, stderr: res.stderr });

Check what you can before you change anything, so that a task that is going to fail fails before it has
touched the device.

Errors you did not plan for
"""""""""""""""""""""""""""

An error nobody catches ends the module the hard way: ucode prints a stack trace on standard error and
nothing on standard output, and the user gets an unparsable result rather than your message. Put a
``try``/``catch`` around anything that can raise - parsing the output of a command is the usual one - and turn
it into a ``fail_json()``:

.. code-block:: text

    let meta;
    try {
        meta = json(res.stdout);
    } catch (e) {
        module.fail_json('could not parse the package metadata');
    }

Testing
^^^^^^^

Integration tests are where a ucode module is proven. There is no unit testing for ``.uc`` files - unit tests
in this collection cover the Python side - so write the integration target as you write the module.

Put the target in ``tests/integration/targets/<name>/`` and run it with:

.. code-block:: console

   $ nox -e test -- <name>

It runs against every OpenWrt version in ``tests/molecule/openwrt.yml``. Test through the module, not around
it: give it parameters, assert what it returns and what it left on the device, run each task a second time and
assert it reports no change, and cover check mode where the module claims to support it. The
:ref:`ansible_collections.community.openwrt.docsite.testing_guide` has the rest.

Sanity tests reject a module whose file is not ``.py`` or ``.ps1``, so every ucode module needs a line in each
``tests/sanity/ignore-X.Y.txt``:

.. code-block:: text

   plugins/modules/<name>.uc validate-modules:invalid-extension

Run the sanity and unit tests with:

.. code-block:: console

   $ ansible-test sanity --docker default --python 3.13
   $ ansible-test units --docker default --python 3.13

A worked example
^^^^^^^^^^^^^^^^

``apk`` installs and removes packages, and is small enough to read in one sitting. Its three files are
``plugins/modules/apk.uc``, its documentation, and ``plugins/action/apk.py``.

It starts by declaring what it accepts, and keeps the two things it uses everywhere at hand:

.. code-block:: text

    const module = AnsibleModule({
        argument_spec: {
            name:         { type: 'str', required: true, aliases: [ 'pkg' ] },
            state:        { type: 'str', default: 'present',
                            choices: [ 'absent', 'installed', 'present', 'removed' ] },
            update_cache: { type: 'bool', default: false },
        },
        supports_check_mode: true,
    });

    const params = module.params;
    const result = module.result;

The state of the device is read through the package manager itself, by asking a question whose answer is an
exit code:

.. code-block:: text

    function is_installed(pkg) {
        return module.run_command([ 'apk', 'info', '-e', pkg ]).rc == 0;
    }

Each operation then follows the same three steps: work out what actually has to be done, do it unless this is
check mode, and report the change either way.

.. code-block:: text

    function install_packages(pkgs) {
        let to_install = [];
        for (let pkg in pkgs) {
            if (!is_installed(pkg))
                push(to_install, pkg);
        }

        if (length(to_install) == 0)
            return;

        if (!module.check_mode) {
            let res = module.run_command([ 'apk', 'add', ...to_install ]);
            result.update({ rc: res.rc, stdout: res.stdout, stderr: res.stderr });

            for (let pkg in to_install) {
                if (!is_installed(pkg))
                    module.fail_json(`failed to install ${pkg}: ${res.stdout} ${res.stderr}`);
            }
        }

        result.changed();
    }

Nothing to install means an early return and no change, which is what makes the second run of a playbook
quiet. The command itself is built as an array, so a package name is a single argument whatever it contains.
Success is not assumed from an exit code: the module asks again, and fails with the command's output when the
package is still not there. ``result.changed()`` sits outside the check-mode guard, so a check-mode run
reports exactly what a real run would.

What is left is the flow, which reads like the documentation:

.. code-block:: text

    if (params.state in ['present', 'installed'])
        install_packages(requested_packages());
    else
        remove_packages(requested_packages());

    module.exit_json();
