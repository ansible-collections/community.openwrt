..
  Copyright (c) 2026, Alexei Znamensky (@russoz)
  GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
  SPDX-License-Identifier: GPL-3.0-or-later

.. _ansible_collections.community.openwrt.docsite.ucode_language_notes:


ucode Language Notes
====================

ucode reads like JavaScript, and that is exactly what makes it worth writing these notes down: the places
where the resemblance stops are the places where a module breaks. What follows are the differences that come
up while writing modules for this collection. It is not a tutorial - the
`ucode documentation <https://ucode.mein.io/>`_ is, and it is worth keeping open.

Functions
^^^^^^^^^

Parameters have no default values. Writing ``function f(x = 1)`` does not compile, so test for ``null`` inside
the function and fill the default in yourself.

Rest parameters work: ``function f(a, ...rest)`` collects the remaining arguments into an array, empty when
none were passed, and it has to be the last parameter. Spreading works too, in calls and in array and object
literals:

.. code-block:: text

    push(cmd, 'add', ...packages);
    let merged = { ...defaults, ...overrides };

There are no classes. Where you would reach for one, write a function that builds an object and returns it,
with the state captured in the closure - which is what ``AnsibleModule()`` is.

Values and collections
^^^^^^^^^^^^^^^^^^^^^^

Arrays and objects are manipulated with global functions rather than methods: ``push()``, ``length()``,
``sort()``, ``map()``, ``split()``, ``join()``, ``substr()``, ``replace()``, ``match()``. There is no
``array.push()`` and no ``string.length``.

``for (let item in array)`` iterates over the **values** of an array, not over its indices. Over an object, it
iterates over the keys. Use a counting ``for`` loop when you need an index.

There is no ``undefined``: a key that is not there reads as ``null``, so ``value == null`` is the test for
"not set". Strings cannot be indexed with ``[]`` - take one character with ``substr(s, i, 1)``.

``type()`` names the type of a value, and the names are not always the ones you expect: a string is
``string``, a floating point number is ``double``, an array is ``array`` and a dictionary is ``object``.

Errors
^^^^^^

Errors are raised with ``die()``, not ``throw``, and caught with ``try``/``catch`` as usual:

.. code-block:: text

    let meta;
    try {
        meta = json(dump.stdout);
    } catch (e) {
        meta = null;
    }

Standard library corners
^^^^^^^^^^^^^^^^^^^^^^^^

A few behaviors are worth knowing before they cost you an afternoon:

* ``printf()`` and ``sprintf()`` take ``%J`` to format a value as JSON, and ``json()`` parses a JSON string.
* Template literals in backticks interpolate with ``${...}``, as in JavaScript.
* Regular expressions are written as literals - ``match(value, /^[0-9]+$/)`` - and ``replace()`` takes the
  ``g`` flag for a global replacement.
* ``math.rand()`` seeds itself from the clock with millisecond resolution, so two processes starting together
  produce the same sequence. Do not use it to make something unique.
* ``fs.mkstemp()`` unlinks the file it creates and hands back an open handle, so there is no path to give to
  another program. ``fs.mkdtemp()`` returns a directory path, and ``open(path, "x")`` creates a file only if
  it does not exist yet.
* There is no ``getpid()``. Reading the link ``/proc/self`` gives the process id as a string.
