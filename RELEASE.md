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
