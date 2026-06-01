# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
import html
import os
import re
import subprocess
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

import nox
import yaml
from looseversion import LooseVersion

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
    major, minor, _patch = LooseVersion(version).version
    return f"{major}.{minor + 1}.0"


OPENWRT_VERSIONS_FILE = Path("tests/molecule/openwrt-versions.yml")


def _read_openwrt_versions() -> list[str]:
    with open(OPENWRT_VERSIONS_FILE) as f:
        return yaml.safe_load(f)["versions"]


def _write_openwrt_versions(versions: list[str]) -> None:
    text = OPENWRT_VERSIONS_FILE.read_text()
    header = text[: text.index("versions:")]
    OPENWRT_VERSIONS_FILE.write_text(header + "versions:\n" + "".join(f'  - "{v}"\n' for v in versions))


def _assert_clean_workdir(session: nox.Session) -> None:
    modified = session.run("git", "status", "--porcelain=v1", "--untracked=normal", external=True, silent=True)
    if modified:
        session.error("Dirty working directory. Commit, stash, or remove changes before running this session.")


def _run_integration(session: nox.Session):
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    session.run("molecule", "-vv", "test", "--scenario-name", "molecule_integration", external=True, env=env)


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
def bump_version(session: nox.Session):
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
        session.error(f"usage: nox -e {session.name} -- released_version [<next_version>]")

    if version != gv:
        session.error(f"Version specified ({version}) differs from galaxy.yml ({gv})")

    set_galaxy_version(new_version)
    released_docs_url = DOCS_URL_TAG_TPL.format(version=version)
    rewrite_docs_urls(released_docs_url, DOCS_URL_DEV)

    session.run("git", "add", "galaxy.yml", "README.md", external=True)
    session.run("git", "commit", "-m", f"Bump version to {new_version}", external=True)
    session.run("git", "push", "upstream", "main", external=True)
    session.run("git", "push", "origin", "main", external=True)


@nox.session(reuse_venv=True, default=False)
def test(session: nox.Session):
    """Run ansible_test_integration scenario for a single target. Posargs: <target>"""
    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <target>")
    target = session.posargs[0]
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1", "TEST_TARGET_ROLE": target}
    session.run("molecule", "-vv", "test", "-s", "ansible_test_integration", external=True, env=env)


@nox.session(reuse_venv=True, default=False)
def test_default(session: nox.Session):
    """Run the default molecule scenario."""
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    session.run("molecule", "-vv", "test", "-s", "default", external=True, env=env)


@nox.session(reuse_venv=True, default=False)
def test_gather_facts(session: nox.Session):
    """Run the default molecule scenario."""
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    session.run("molecule", "-vv", "test", "-s", "gather_facts", external=True, env=env)


@nox.session(reuse_venv=True, default=False)
def integration(session: nox.Session):
    """Run molecule integration tests for all plugins (molecule_integration scenario)."""
    _run_integration(session)


@nox.session(reuse_venv=True, default=False)
def roles(session: nox.Session):
    """Run molecule tests for all role scenarios. Posargs: [--role|-r ROLE] [--scenario|-s SCENARIO]"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", "-r")
    parser.add_argument("--scenario", "-s")
    args = parser.parse_args(session.posargs)
    if args.scenario and not args.role:
        session.error("--scenario requires --role")

    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    roles = args.role if args.role else "*"
    scenarios = args.scenario if args.scenario else "*"

    session.log(f"roles={roles}  scenarios={scenarios}")

    role_dirs = sorted(Path("roles").glob(f"{roles}/"))
    if not role_dirs:
        session.skip(f"""Cannot find role(s) in roles{f"/{'' if roles == '*' else roles}"}""")

    for role_dir in sorted(Path("roles").glob(f"{roles}/")):
        role = role_dir.parts[1]
        session.log(f"role={role}")

        with session.chdir(role_dir):
            scenario_dirs = sorted(Path("molecule").glob(f"{scenarios}/"))
            if not scenario_dirs:
                session.skip(
                    f"""Cannot find scenario(s) in roles/{role}/molecule{f"/{'' if scenarios == '*' else scenarios}"}"""
                )

            for scenario_dir in scenario_dirs:
                scenario = scenario_dir.parts[1]

                session.log(f"role={role}  scenario={scenario}")

                session.run("molecule", "-vv", "test", "--scenario-name", scenario, external=True, env=env)


@nox.session(reuse_venv=True, default=False)
def regen_shellcheck_ignores(session: nox.Session):
    """Regenerate shellcheck ignore entries in tests/sanity/ignore-*.txt."""
    sanity_dir = Path("tests") / "sanity"
    if not sanity_dir.is_dir():
        session.error("Run this from the top directory of the project")

    class TitleParser(HTMLParser):
        def __init__(self, body: str) -> None:
            super().__init__()
            self.in_title = False
            self.title_parts = []
            self.feed(body)

        def handle_starttag(self, tag, attrs):
            if tag.lower() == "title":
                self.in_title = True

        def handle_endtag(self, tag):
            if tag.lower() == "title":
                self.in_title = False

        def handle_data(self, data):
            if self.in_title:
                self.title_parts.append(data)

        @property
        def title(self) -> str:
            return html.unescape("".join(self.title_parts).strip())

    sc_desc_cache = {}

    def retrieve_sc_description(sc_code: str) -> str:
        if sc_code in sc_desc_cache:
            return sc_desc_cache[sc_code]
        url = f"https://www.shellcheck.net/wiki/{sc_code}"
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                charset = resp.headers.get_content_charset() or "utf-8"
                body = resp.read().decode(charset, errors="replace")
        except Exception as e:
            sc_desc_cache[sc_code] = f"(failed to fetch: {e})"
            return sc_desc_cache[sc_code]
        parser = TitleParser(body)
        title = parser.title.replace(f"ShellCheck: {sc_code} – ", "").rstrip(".")
        sc_desc_cache[sc_code] = f"{title} - {url}" if title else f"(no title found at {url})"
        return sc_desc_cache[sc_code]

    ig_version_re = re.compile(r".*/ignore-(?P<version>\d\.\d+)\.txt")

    def get_version(filename):
        if not (match := ig_version_re.search(str(filename))):
            raise ValueError(f"ignore filename not recognized: {filename}")
        version = match.group("version")
        return f"ac{version.replace('.', '')}", version

    ignore_files = sorted(sanity_dir.glob("ignore-*.txt"))
    tox_targets = [get_version(f)[0] for f in ignore_files[:-1]] + ["dev"]
    ignore_versions = [get_version(f)[1] for f in ignore_files]

    for tox_target, ignore_version in zip(tox_targets, ignore_versions, strict=True):
        ignore_file = sanity_dir / f"ignore-{ignore_version}.txt"
        session.log(f"Processing {ignore_file} ({tox_target}/{ignore_version})")

        with ignore_file.open("r", encoding="utf-8") as f:
            kept = [ll for ll in f if "shellcheck" not in ll]
        with ignore_file.open("w", encoding="utf-8") as f:
            f.writelines(kept)

        proc = subprocess.run(
            [
                "andebox",
                "tox-test",
                "-e",
                tox_target,
                "--",
                "sanity",
                "--python",
                "default",
                "--docker",
                "default",
                "--test",
                "shellcheck",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        found = set()
        for line in proc.stdout.splitlines():
            if not line.startswith("ERROR"):
                continue
            parts = line.split(":", 5)
            if "/" not in parts[1]:
                continue
            path, sc_code = parts[1].strip(), parts[4].strip()
            desc = retrieve_sc_description(sc_code)
            found.add(f"{path} shellcheck:{sc_code}   # {desc}")

        if found:
            with ignore_file.open("a", encoding="utf-8") as f:
                f.writelines(f"{ll}\n" for ll in sorted(found))

        session.log(f"Added {len(found)} shellcheck ignore entries to {ignore_file}")


@nox.session(reuse_venv=True, default=False)
def openwrt_version(session: nox.Session):
    """
    Manage OpenWrt versions in tests/molecule/openwrt-versions.yml.

    Usage:
        nox -e openwrt_version -- list
        nox -e openwrt_version -- bump <major.minor>
        nox -e openwrt_version -- add <major.minor.patch>
        nox -e openwrt_version -- remove <major.minor>
    """
    _SUBCOMMANDS = ("list", "bump", "add", "remove")

    if not session.posargs or session.posargs[0] not in _SUBCOMMANDS:
        session.error(
            f"usage: nox -e {session.name} -- <{'|'.join(_SUBCOMMANDS)}> [args]\n"
            "  list                     show current versions\n"
            "  bump <major.minor>       increment patch of matching version\n"
            "  add <major.minor.patch>  add a new version to the matrix\n"
            "  remove <major.minor>     remove a version series from the matrix\n"
        )

    cmd = session.posargs[0]
    args = session.posargs[1:]

    if cmd == "list":
        for v in _read_openwrt_versions():
            session.log(v)
        return

    _assert_clean_workdir(session)
    session.run("git", "checkout", "main", external=True)
    session.run("git", "pull", "--rebase", "upstream", "main", external=True)
    versions = _read_openwrt_versions()

    match cmd:
        case "bump":
            if len(args) != 1:
                session.error(f"usage: nox -e {session.name} -- bump <major.minor>")
            minor = args[0]
            matches = [v for v in versions if v.startswith(f"{minor}.")]
            if not matches:
                session.error(f"No version matching {minor}.* found in {versions}")
            old_version = matches[0]
            maj, min_, old_patch = LooseVersion(old_version).version
            new_version = f"{maj}.{min_}.{old_patch + 1}"
            new_versions = [new_version if v == old_version else v for v in versions]
            branch = f"openwrt-bump-{new_version}"
            title = f"test: bump OpenWrt to {new_version} (from .{old_patch})"
            body = f"Bump OpenWrt {minor} patch level from {old_version} to {new_version}."
            commit_msg = title

        case "add":
            if len(args) != 1:
                session.error(f"usage: nox -e {session.name} -- add <major.minor.patch>")
            new_version = args[0]
            if not re.match(r"^\d+\.\d+\.\d+$", new_version):
                session.error(f"Invalid version: {new_version!r} (expected major.minor.patch)")
            minor = ".".join(new_version.split(".")[:2])
            if any(v.startswith(f"{minor}.") for v in versions):
                session.error(f"Version {minor}.* already exists. Use 'bump' to update it.")
            new_versions = sorted(versions + [new_version], key=LooseVersion, reverse=True)
            branch = f"openwrt-add-{new_version}"
            title = f"test: add OpenWrt {new_version} to test matrix"
            body = f"Add OpenWrt {new_version} to the test matrix."
            commit_msg = title

        case "remove":
            if len(args) != 1:
                session.error(f"usage: nox -e {session.name} -- remove <major.minor>")
            minor = args[0]
            matches = [v for v in versions if v.startswith(f"{minor}.")]
            if not matches:
                session.error(f"No version matching {minor}.* found in {versions}")
            removed = matches[0]
            new_versions = [v for v in versions if v != removed]
            if not new_versions:
                session.error("Cannot remove the last remaining version.")
            branch = f"openwrt-remove-{minor}"
            title = f"test: remove OpenWrt {minor} from test matrix"
            body = f"Remove OpenWrt {removed} from the test matrix."
            commit_msg = title

    session.run("git", "checkout", "-b", branch, external=True)
    _write_openwrt_versions(new_versions)
    session.run("git", "add", str(OPENWRT_VERSIONS_FILE), external=True)
    session.run("git", "commit", "-m", commit_msg, external=True)

    _run_integration(session)

    session.run("git", "push", "origin", branch, external=True)

    origin_url = session.run("git", "remote", "get-url", "origin", external=True, silent=True).strip()
    fork_owner = origin_url.rstrip("/").split("/")[-2].split(":")[-1]
    pr = session.run(
        "gh",
        "pr",
        "create",
        "-R",
        UPSTREAM,
        "--head",
        f"{fork_owner}:{branch}",
        "--title",
        title,
        "--body",
        body,
        external=True,
        silent=True,
    )
    session.log(f"PR created: {pr.splitlines()[-1]}")


if __name__ == "__main__":
    nox.main()
