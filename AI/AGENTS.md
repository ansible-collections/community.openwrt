<!--
Copyright (c) Ansible Project
GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Why

Users of OpenWRT devices need a consistent and maintained set of ansible components they can use.

# What

`community.openwrt` is an Ansible collection supporting OpenWRT devices. It has no code in it yet, but it is meant to be based on the no longer maintained ansible role `gekmihesg.openwrt` - accessible in this workspace under the `ansible-openwrt` project directory.

The collection will support Ansible 2.18 onwards.

# How

- Transport the code from the role to the collection, transforming the idiom from "role" to "collection modules"
  - When moving the modules (shell script), remove the prefix `openwrt_` from them.
- Note that OpenWRT devices often have no Python installed, therefore the modules are written in shell script. Keep the module code as-is, since they work.
  - As a side-effect from it, `gather_facts` must **always** be `false` for OpenWRT hosts
- Make the modules accesible within the collection namespace using FQCN rather than base names as instructed by the role docs.
- Do not make any modification whatsoever in the metadata of the collection, except for the requirements
  - Check the requirements in ansible-openwrt (both in the project directory and in the Pull Requests links in this document)
- Do not embed the wrapper.sh logic into the existing modules - that will harm the extensibility and maintainability of the collection
- Do not repeat the same code in multiple files, use common components as needed - for Python and shell files alike.
- The original code had a "feature" that would make the code only apply to hosts that belonged to the group `openwrt`.
  Remove that completely from everywhere in the code. There should be no hardcoded inventory names in the files.

# With What

- The repo is already in a new git branch dedicated to this task
- Look at the https://github.com/gekmihesg/ansible-openwrt/pull/67 for ideas
  - Likely going to need an action plugin as described in this PR
  - Possibly need the bootstrap playbook from that PR
- Look at https://github.com/gekmihesg/ansible-openwrt/pull/77 for compatibility fixes for Ansible 2.19+
- The current project directpry has a virtualenv managed by `pipenv` in place. Use `pipenv run` to execute Python commands
- Note the role has `molecule` tests implemented.
  - Those tests were written for an old version of molecule and will require updating.
  - Also be aware that of the PR https://github.com/gekmihesg/ansible-openwrt/pull/71 (never merged) that contained _some_
    updates to the tests. Specially the image names have changed.
  - Adapt those tests to the collection, and use the adapted tests to validate the new calling convention for the modules.
  - Do test the new code using `molecule`
- If creating new Python files:
  - No need to add utf-8 markers at the top of the file
  - Do not add the `__metaclass__` statement
  - Only import `annotations` from `__future__`, nothing else

# Definition of Success

- The collection must pass the molecule tests

# Ucode modules

Beyond the shell-based modules, the collection ships modules written in OpenWrt's native
`ucode` language (see `docs/docsite/rst/mod_dev_guide.rst`). A ucode module is a `.uc` file in
`plugins/modules/` plus a `.yml` sidecar with `DOCUMENTATION`/`EXAMPLES`/`RETURN`; there is no
`.py`. It runs as a `non_native_want_json` script: Ansible passes the args as a JSON file whose
path is `ARGV[0]`, and the module prints a JSON result on `stdout`.

Modules share a single helper library at `plugins/module_utils/ansible_common.uc` (functions
prefixed `ac_`), and a reusable action base at `plugins/plugin_utils/ucode_action.py`
(`UcodeOpenwrtActionBase`). The action plugin transfers the module and the helper into the same
remote directory so the module's relative `import { ... } from './ansible_common.uc'` resolves,
then executes `ucode <module> <args>` and parses the JSON result. No shell wrapper is involved.

Hard-learned ucode rules:

- `'use strict';` at the top; `#!/usr/bin/ucode` shebang and a `WANT_JSON` marker.
- JSON: decode with `json(str)`, encode with `sprintf("%J", obj)`. There is no `serialize()`.
- `export function name(...) {...};` must end with a semicolon. Functions are not hoisted:
  declare before use; no forward declarations; no `throw` (use `die()`).
- Arrays use global helpers: `length(arr)`, `push(arr, ...)`, `sort(arr)`. There are no
  `arr.push()`/`arr.sort()` methods.
- Strings are not `[]`-indexable — use `substr(s, i, 1)` / `ord(s, i)`.
- `for (let x in arr)` yields the elements; over objects it yields the keys. Loop variables must
  be declared with `let`. Iterate objects with `for (let k in obj)`; iterate arrays by index.
- No `String(x)` global — use `sprintf("%s", x)`.
- `uci`: `import { cursor } from 'uci'; const u = cursor();` — `get/get_all/set/foreach/add/
  save/commit`. `set(config, section, type)` creates a named section; `add` requires the config
  to be explicitly `load()`ed first; `save()` persists changes as a delta so a subsequent module
  invocation (new process) sees them.
- Check mode: the args include `_ansible_check_mode`; compute the diff/changed but skip
  `save`/`commit`.
- Idempotency: strip UCI meta keys (`.name`, `.type`, `.anonymous`, `.index`) from `get_all`
  output before comparing; compare via sorted-key equality (`sprintf("%J", ...)`), not raw object
  equality.

Lint ucode modules with `node tests/uc-lint.mjs` (or the `ucode-lint` nox session /
pre-commit hook). Run unit tests with `ansible-test units`; run a module's integration target with
`nox -e test -- <target>`.

# Conventions

- YAML multiline scalars in Ansible vars: use `>-` for pure `{{ }}` expressions (Ansible
  evaluates them natively). Use `|-` when the value contains Jinja block logic (`{% set %}`,
  `{% for %}`, etc.) — this produces a string Ansible parses as a data structure. Do NOT use `>-`
  with block logic or `from_yaml` hacks.
- Task names should be short and concise (e.g. "Configure general", not "Configure babeld general
  section").
- Keep links absolute unless requested otherwise; prefer minimal, targeted patches.
