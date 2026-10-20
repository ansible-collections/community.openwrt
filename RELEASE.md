<!--
Copyright (c) Ansible Project
GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Release Process

The release process is fairly automated, but it still requires a human to check and verify the state at some checkpoints.

The process to release version `x.y.z` is as follows:

1. `nox -e release -- x.y.z` - this step also requires a release changelog fragment `changelogs/fragments/x.y.z.yml`
2. Open the PR that is generated. Wait for the tests to pass and merge.
3. After the PR is merged, wait for all the workflows in `main` to complete
4. `nox -e tag -- x.y.z`
5. Wait for Zuul to complete the release. If it fails and Zuul needs to be triggered again, use `nox -e tag -- x.y.z --retag`.
6. `nox -e github_release -- x.y.z`
7. `nox -e bump_version -- x.y.z`
8. Announce in [Ansible forum](https://forum.ansible.com) (optional)
9. Announce in Ansible Bullhorn
10. Announce in [OpenWrt forum](https://forum.openwrt.org)
11. Update [Release History](https://github.com/ansible-collections/community.openwrt/issues/100).

## Automated release

`nox -e release_process -- x.y.z [<next_version>]` runs steps 1 to 7 in one go:

- creates the release PR, waits for its workflows to pass and squash-merges it;
- waits for the workflows on `main`, then tags the merge commit;
- waits for the Zuul release job and for `x.y.z` to appear on Galaxy, retagging once if the job fails or does not finish in time;
- creates the GitHub release and bumps the version.

Steps already done are skipped, so after any stop (fragment to edit, failed workflow, timeout), fix the problem and run the same command again.
Steps 8 to 11 remain manual; the session lists them at the end.
Polling can be tuned with `--interval`, `--timeout` and `--zuul-timeout` (in seconds).
