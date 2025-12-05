# Why

Users of OpenWRT devices need a consistent and maintained set of ansible components they can use.

# What

`community.openwrt` is an Ansible collection supporting OpenWRT devices. It has no code in it yet, but it is meant to be based on the no longer maintained ansible role `gekmihesg.openwrt` - accessible in this workspace under the `ansible-openwrt` proejct directory.

The collection will support Ansible 2.17 onwards.

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
