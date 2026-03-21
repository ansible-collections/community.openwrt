# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

import sys
from pathlib import Path

import nox

try:
    import antsibull_nox
except ImportError:
    print("You need to install antsibull-nox in the same Python environment as nox.")
    sys.exit(1)


antsibull_nox.load_antsibull_nox_toml()


def check_no_modifications(session: nox.Session, fragment_path) -> None:
    modified = session.run(
        "git",
        "status",
        "--porcelain=v1",
        "--untracked=normal",
        external=True,
        silent=True,
    )
    modified = [x for x in modified.splitlines() if fragment_path not in x]
    if modified:
        session.error("There are modified or untracked files. Commit, restore, or remove them before running this")


@nox.session(reuse_venv=True, default=False)
def release(session: nox.Session):
    """
    Release collection without release branches
    https://docs.ansible.com/projects/ansible/latest/community/collection_contributors/collection_release_without_branches.html
    """

    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <version>")
    version = session.posargs[0]
    fragment_path = Path(f"changelogs/fragments/{version}.yml")
    release_branch = f"release-{version}"

    session.install("antsibull-changelog[toml]", "pyaml")
    import yaml

    session.run("git", "checkout", "main", external=True)
    check_no_modifications(session, str(fragment_path))

    if not fragment_path.is_file():
        session.error(f"{fragment_path} must already exist")
    with open(fragment_path) as fragment_file:
        fragment = yaml.safe_load(fragment_file)
    if not isinstance(fragment, dict) or len(fragment) != 1 or "release_summary" not in fragment:
        session.error(f"{fragment_path} must contain a single `release_summary` entry")

    session.run("git", "pull", "--rebase", "upstream", "main", external=True)

    with open("galaxy.yml") as galaxy_file:
        galaxy_file_lines = galaxy_file.readlines()
        galaxy = yaml.safe_load("".join(galaxy_file_lines))
    if version != galaxy['version']:
        session.error(
            f"Version specified ({version}) differs from version in galaxy.yml: {galaxy['version']})"
        )

    session.run("git", "checkout", "-b", release_branch, external=True)
    session.run("antsibull-changelog", "release", "--refresh-plugins")
    session.run(
        "git",
        "add",
        "CHANGELOG.rst",
        "CHANGELOG.md",
        "changelogs/changelog.yaml",
        "changelogs/fragments/",
        external=True,
    )

    session.run("git", "commit", "-m", f"Release {version}", external=True)
    session.run("git", "push", "origin", release_branch, external=True)
    origin_url = session.run("git", "remote", "get-url", "origin", external=True, silent=True).strip()
    fork_owner = origin_url.rstrip("/").split("/")[-2].split(":")[-1]
    pr = session.run(
        "gh",
        "pr",
        "create",
        "-R",
        "ansible-collections/community.openwrt",
        "--head",
        f"{fork_owner}:{release_branch}",
        "--title",
        f"Release {version}",
        "--body",
        fragment["release_summary"],
        external=True,
        silent=True,
    )
    session.log(f"PR created: {pr.splitlines()[-1]}")
    session.run(
        "gh",
        "pr",
        "comment",
        pr.splitlines()[-1],
        "--body",
        "bot_skip",
        external=True,
    )


if __name__ == "__main__":
    nox.main()
