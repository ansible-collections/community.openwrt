# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

import os
import sys
from pathlib import Path

import nox

try:
    import antsibull_nox
except ImportError:
    print("You need to install antsibull-nox in the same Python environment as nox.")
    sys.exit(1)


antsibull_nox.load_antsibull_nox_toml()


UPSTREAM = "ansible-collections/community.openwrt"
DOCS_URL_DEV = "https://ansible-collections.github.io/community.openwrt/branch/main/"
DOCS_URL_TAG_TPL = "https://ansible-collections.github.io/community.openwrt/tag/{version}/"
DOCS_FILES = ("README.md", "galaxy.yml")
RELEASE_NOTES = (
    "See the [CHANGELOG](https://github.com/ansible-collections/community.openwrt/blob/main/CHANGELOG.md) for details."
)


def rewrite_docs_urls(old: str, new: str) -> None:
    for path in DOCS_FILES:
        p = Path(path)
        p.write_text(p.read_text().replace(old, new))


def galaxy_version() -> str:
    import yaml

    with open("galaxy.yml") as f:
        return yaml.safe_load(f)["version"]


def set_galaxy_version(new_version: str) -> None:
    p = Path("galaxy.yml")
    lines = p.read_text().splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith("version:"):
            lines[i] = f"version: {new_version}\n"
            break
    p.write_text("".join(lines))


def next_minor(version: str) -> str:
    major, minor, _patch = (int(x) for x in version.split("."))
    return f"{major}.{minor + 1}.0"


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

    session.install("antsibull-changelog[toml]", "pyaml")
    import yaml

    with open("galaxy.yml") as galaxy_file:
        galaxy_file_lines = galaxy_file.readlines()
        galaxy_version = yaml.safe_load("".join(galaxy_file_lines))["version"]

    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <version>\n\ngalaxy.yml version is {galaxy_version}\n")
    version = session.posargs[0]
    fragment_path = Path(f"changelogs/fragments/{version}.yml")
    release_branch = f"release-{version}"

    session.run("git", "checkout", "main", external=True)
    check_no_modifications(session, str(fragment_path))

    if not fragment_path.is_file():
        with open(fragment_path, "w") as frag_skel:
            frag_skel.write("release_summary: |-\n  CHANGEME <type of release>, info")
        editor = os.getenv("IDE", os.getenv("EDITOR", "vi"))
        session.run(editor, fragment_path, external=True)
        session.error(f"{fragment_path} must already exist")

    with open(fragment_path) as fragment_file:
        fragment = yaml.safe_load(fragment_file)
    if not isinstance(fragment, dict) or len(fragment) != 1 or "release_summary" not in fragment:
        session.error(f"{fragment_path} must contain a single `release_summary` entry")
    if "CHANGEME" in fragment["release_summary"]:
        session.error(f"{fragment_path} needs editing")

    session.run("git", "pull", "--rebase", "upstream", "main", external=True)

    with open("galaxy.yml") as galaxy_file:
        galaxy_file_lines = galaxy_file.readlines()
        galaxy = yaml.safe_load("".join(galaxy_file_lines))
    if version != galaxy_version:
        session.error(f"Version specified ({version}) differs from version in galaxy.yml: {galaxy['version']})")

    session.run("git", "checkout", "-b", release_branch, external=True)
    session.run("antsibull-changelog", "release", "--refresh-plugins")
    rewrite_docs_urls(DOCS_URL_DEV, DOCS_URL_TAG_TPL.format(version=version))
    session.run(
        "git",
        "add",
        "CHANGELOG.rst",
        "CHANGELOG.md",
        "changelogs/changelog.yaml",
        "changelogs/fragments/",
        "README.md",
        "galaxy.yml",
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


@nox.session(reuse_venv=True, default=False)
def tag(session: nox.Session):
    """
    Tag the release on upstream/main and push the tag.

    Usage: nox -e tag -- <version> [--retag]

    --retag deletes the remote tag and re-pushes the existing local tag
    (used when Zuul needs re-triggering). The local tag is not touched.
    """
    retag = "--retag" in session.posargs
    args = [a for a in session.posargs if not a.startswith("--")]
    if len(args) != 1:
        session.error(f"usage: nox -e {session.name} -- <version> [--retag]")
    version = args[0]

    session.install("pyaml")
    session.run("git", "checkout", "main", external=True)
    session.run("git", "pull", "--rebase", "upstream", "main", external=True)

    gv = galaxy_version()
    if version != gv:
        session.error(f"Version specified ({version}) differs from galaxy.yml ({gv})")

    if retag:
        session.run("git", "push", "upstream", "--delete", version, external=True)
    else:
        session.run("git", "tag", "-a", version, "-m", f"Release {version}", external=True)
    session.run("git", "push", "upstream", version, external=True)


@nox.session(reuse_venv=True, default=False)
def github_release(session: nox.Session):
    """
    Create a GitHub release from an existing tag.

    Usage: nox -e github_release -- <version>
    """
    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <version>")
    version = session.posargs[0]

    session.run(
        "gh",
        "release",
        "create",
        version,
        "-R",
        UPSTREAM,
        "--title",
        version,
        "--notes",
        RELEASE_NOTES,
        external=True,
    )


@nox.session(reuse_venv=True, default=False)
def version_bump(session: nox.Session):
    """
    Bump galaxy.yml to the next development version, revert pinned doc URLs,
    push directly to upstream/main, and sync origin.

    Usage: nox -e version_bump -- [<next_version>]

    If <next_version> is not given, rotates the minor component
    (e.g. 1.3.0 -> 1.4.0).
    """
    session.install("pyaml")
    session.run("git", "checkout", "main", external=True)
    check_no_modifications(session, "")
    session.run("git", "pull", "--rebase", "upstream", "main", external=True)

    gv = galaxy_version()
    if len(session.posargs) == 1:
        version = session.posargs[0]
        new_version = next_minor(version)
    elif len(session.posargs) == 2:
        version = session.posargs[0]
        new_version = session.posargs[1]
    else:
        session.error(f"usage: nox -e {session.name} -- [<next_version>]")

    if version != gv:
        session.error(f"Version specified ({version}) differs from galaxy.yml ({gv})")

    set_galaxy_version(new_version)
    released_docs_url = DOCS_URL_TAG_TPL.format(version=version)
    rewrite_docs_urls(released_docs_url, DOCS_URL_DEV)

    session.run("git", "add", "galaxy.yml", "README.md", external=True)
    session.run("git", "commit", "-m", f"Bump version to {new_version}", external=True)
    session.run("git", "push", "upstream", "main", external=True)
    session.run("git", "push", "origin", "main", external=True)


if __name__ == "__main__":
    nox.main()
