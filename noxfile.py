# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
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
ZUUL_API = "https://gateway-cloud-softwarefactory.apps.ocp.cloud.ci.centos.org/zuul/api/tenant/ansible"
ZUUL_RELEASE_JOB = "release-ansible-collection-galaxy"
GALAXY_VERSION_URL_TPL = (
    "https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/"
    "community/openwrt/versions/{version}/"
)
RUNS_OK = {"success", "skipped", "neutral"}
RELEASE_MANUAL_STEPS = """\
Release {version} is out. Remaining manual steps:
  - Announce in the Ansible forum (optional): https://forum.ansible.com
  - Announce in Ansible Bullhorn
  - Announce in the OpenWrt forum: https://forum.openwrt.org
  - Update the release history: https://github.com/ansible-collections/community.openwrt/issues/100
"""


def rewrite_docs_urls(old: str, new: str) -> None:
    for path in DOCS_FILES:
        p = Path(path)
        p.write_text(p.read_text().replace(old, new))


def get_galaxy_version() -> str:
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


OPENWRT_FILE = Path("tests/molecule/openwrt.yml")


def _read_openwrt() -> dict:
    with open(OPENWRT_FILE) as f:
        return yaml.safe_load(f)


def _write_openwrt(openwrt_cfg: dict) -> None:
    with open(OPENWRT_FILE, "w") as f:
        yaml.safe_dump(openwrt_cfg, f)


def _run_integration(session: nox.Session):
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    session.run("molecule", "-vvv", "test", "--scenario-name", "molecule_integration", external=True, env=env)


def check_no_modifications(session: nox.Session, exclude: str | None = None) -> None:
    modified = session.run(
        "git",
        "status",
        "--porcelain=v1",
        "--untracked=normal",
        external=True,
        silent=True,
    )
    modified = [x for x in modified.splitlines() if not exclude or exclude not in x]
    if modified:
        session.error(
            "There are modified or untracked files. Commit, restore, or remove them before running this session."
        )


def _do_release(session: nox.Session, version: str) -> None:
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

    galaxy_version = get_galaxy_version()
    if version != galaxy_version:
        session.error(f"Version specified ({version}) differs from galaxy.yml ({galaxy_version})")

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


def _do_tag(session: nox.Session, version: str, retag: bool = False, commit: str | None = None) -> None:
    session.run("git", "checkout", "main", external=True)
    session.run("git", "pull", "--rebase", "upstream", "main", external=True)

    gv = get_galaxy_version()
    if version != gv:
        session.error(f"Version specified ({version}) differs from galaxy.yml ({gv})")

    if retag:
        session.run("git", "push", "upstream", "--delete", version, external=True)
    else:
        session.run("git", "tag", "-a", version, "-m", f"Release {version}", *filter(None, [commit]), external=True)
    session.run("git", "push", "upstream", version, external=True)


def _do_github_release(session: nox.Session, version: str) -> None:
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


def _do_bump_version(session: nox.Session, version: str, new_version: str | None = None) -> None:
    session.run("git", "checkout", "main", external=True)
    check_no_modifications(session)
    session.run("git", "pull", "--rebase", "upstream", "main", external=True)

    gv = get_galaxy_version()
    if version != gv:
        session.error(f"Version specified ({version}) differs from galaxy.yml ({gv})")

    new_version = new_version or next_minor(version)
    set_galaxy_version(new_version)
    released_docs_url = DOCS_URL_TAG_TPL.format(version=version)
    rewrite_docs_urls(released_docs_url, DOCS_URL_DEV)

    session.run("git", "add", "galaxy.yml", "README.md", external=True)
    session.run("git", "commit", "-m", f"Bump version to {new_version}", external=True)
    session.run("git", "push", "upstream", "main", external=True)
    session.run("git", "push", "origin", "main", external=True)


@nox.session(default=False)
def release(session: nox.Session):
    """
    Release collection without release branches
    https://docs.ansible.com/projects/ansible/latest/community/collection_contributors/collection_release_without_branches.html
    """

    session.install("antsibull-changelog[toml]", "pyaml")

    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <version>\n\ngalaxy.yml version is {get_galaxy_version()}\n")
    _do_release(session, session.posargs[0])


@nox.session(default=False)
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

    session.install("pyaml")
    _do_tag(session, args[0], retag=retag)


@nox.session(default=False)
def github_release(session: nox.Session):
    """
    Create a GitHub release from an existing tag.

    Usage: nox -e github_release -- <version>
    """
    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <version>")
    _do_github_release(session, session.posargs[0])


@nox.session(default=False)
def bump_version(session: nox.Session):
    """
    Bump galaxy.yml to the next development version, revert pinned doc URLs,
    push directly to upstream/main, and sync origin.

    Usage: nox -e bump_version -- <released_version> [<next_version>]

    If <next_version> is not given, rotates the minor component of
    <released_version> (e.g. 1.3.0 -> 1.4.0).
    """
    session.install("pyaml")
    if len(session.posargs) not in (1, 2):
        session.error(f"usage: nox -e {session.name} -- released_version [<next_version>]")
    _do_bump_version(session, *session.posargs)


def _gh_json(*args: str):
    return json.loads(subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout)


def _http_json(url: str):
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def _wait_for(session: nox.Session, what: str, probe, timeout: int, interval: int):
    """Poll ``probe`` until it returns something other than None. Returns None on timeout."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            result = probe()
        except (OSError, ValueError, subprocess.CalledProcessError) as e:
            session.warn(f"{what}: {e}")
            result = None
        if result is not None:
            return result
        if time.monotonic() >= deadline:
            return None
        session.log(f"Waiting for {what}...")
        time.sleep(interval)


def _release_pr(version: str) -> dict | None:
    prs = _gh_json(
        "pr", "list", "-R", UPSTREAM, "--head", f"release-{version}", "--state", "all",
        "--json", "number,state,url,headRefOid,mergeCommit",
    )  # fmt: skip
    prs = [pr for pr in prs if pr["state"] != "CLOSED"]
    return prs[0] if prs else None


def _failed_runs(runs: list[dict]) -> list[str] | None:
    """URLs of the failed runs, or None while no run is reported or some are still running."""
    failed = [run["url"] for run in runs if run["status"] == "completed" and run["conclusion"] not in RUNS_OK]
    if failed:
        return failed
    if not runs or any(run["status"] != "completed" for run in runs):
        return None
    return []


def _wait_for_runs(session: nox.Session, what: str, commit: str, event: str | None, args) -> None:
    query = ["run", "list", "-R", UPSTREAM, "--commit", commit, "--json", "status,conclusion,url"]
    query += ["--event", event] if event else []
    failed = _wait_for(session, what, lambda: _failed_runs(_gh_json(*query)), args.timeout, args.interval)
    if failed is None:
        session.error(f"Timed out waiting for {what}")
    if failed:
        session.error(f"{what} failed: {' '.join(failed)}")


def _upstream_tag_exists(version: str) -> bool:
    cmd = ["git", "ls-remote", "--tags", "upstream", f"refs/tags/{version}"]
    return bool(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip())


def _zuul_release_builds(version: str) -> list[dict]:
    query = urllib.parse.urlencode({"project": UPSTREAM, "ref": f"refs/tags/{version}", "job_name": ZUUL_RELEASE_JOB})
    return _http_json(f"{ZUUL_API}/builds?{query}") or []


def _zuul_finished_build(version: str, ignored: set[str]) -> dict | None:
    builds = [build for build in _zuul_release_builds(version) if build["uuid"] not in ignored]
    if builds and builds[0]["result"] not in (None, "RETRY"):
        return builds[0]
    return None


def _wait_for_zuul(session: nox.Session, version: str, args) -> None:
    ignored: set[str] = set()
    for attempt in range(2):
        build = _wait_for(
            session,
            "the Zuul release job",
            lambda ignored=ignored: _zuul_finished_build(version, ignored),
            args.zuul_timeout,
            args.interval,
        )
        if build and build["result"] == "SUCCESS":
            return
        reason = (
            f"failed ({build['result']}): {build['log_url']}" if build else f"did not finish in {args.zuul_timeout}s"
        )
        if attempt:
            session.error(f"Zuul release job {reason}")
        session.warn(f"Zuul release job {reason}; retagging {version}")
        ignored = {previous["uuid"] for previous in _zuul_release_builds(version)}
        _do_tag(session, version, retag=True)


def _galaxy_has(version: str) -> bool:
    return _http_json(GALAXY_VERSION_URL_TPL.format(version=version)) is not None


def _github_release_exists(version: str) -> bool:
    return (
        subprocess.run(["gh", "release", "view", version, "-R", UPSTREAM], capture_output=True, check=True).returncode
        == 0
    )


def _upstream_galaxy_version(session: nox.Session) -> str:
    session.run("git", "fetch", "upstream", "main", external=True, silent=True)
    galaxy = subprocess.run(["git", "show", "upstream/main:galaxy.yml"], capture_output=True, text=True, check=True)
    return yaml.safe_load(galaxy.stdout)["version"]


@nox.session(default=False)
def release_process(session: nox.Session):
    """
    Run the release process in RELEASE.md from start to finish.

    Usage: nox -e release_process -- <version> [<next_version>] [--interval S] [--timeout S] [--zuul-timeout S]

    Steps already done are skipped, so after any stop, fix the problem and run it again.
    """
    parser = argparse.ArgumentParser(prog=f"nox -e {session.name} --")
    parser.add_argument("version")
    parser.add_argument("next_version", nargs="?", help="version to bump galaxy.yml to (default: next minor)")
    parser.add_argument("--interval", type=int, default=60, help="seconds between polls (default: %(default)s)")
    parser.add_argument(
        "--timeout",
        type=int,
        default=3600,
        help="seconds to wait for the release PR workflows, and then for the main workflows (default: %(default)s)",
    )
    parser.add_argument(
        "--zuul-timeout",
        type=int,
        default=1800,
        help="seconds to wait for the Zuul release job, and then for Galaxy (default: %(default)s)",
    )
    args = parser.parse_args(session.posargs)
    version = args.version

    session.install("antsibull-changelog[toml]", "pyaml")

    pr = _release_pr(version)
    if pr is None:
        _do_release(session, version)
        pr = _release_pr(version)
    if pr["state"] == "OPEN":
        _wait_for_runs(session, f"the workflows of {pr['url']}", pr["headRefOid"], None, args)
        session.run("gh", "pr", "merge", str(pr["number"]), "-R", UPSTREAM, "--squash", external=True)
        pr = _release_pr(version)
    merge_commit = pr["mergeCommit"]["oid"]

    if not _upstream_tag_exists(version):
        _wait_for_runs(session, f"the workflows of {merge_commit} on main", merge_commit, "push", args)
        _do_tag(session, version, commit=merge_commit)

    if not _galaxy_has(version):
        _wait_for_zuul(session, version, args)
        if not _wait_for(
            session, f"{version} on Galaxy", lambda: _galaxy_has(version) or None, args.zuul_timeout, args.interval
        ):
            session.error(f"{version} did not show up on Galaxy in {args.zuul_timeout}s")

    if not _github_release_exists(version):
        _do_github_release(session, version)

    if _upstream_galaxy_version(session) == version:
        _do_bump_version(session, version, args.next_version)

    session.log(RELEASE_MANUAL_STEPS.format(version=version))


@nox.session(default=False)
def test(session: nox.Session):
    """Run ansible_test_integration scenario for a single target. Posargs: <target>"""
    if len(session.posargs) != 1:
        session.error(f"usage: nox -e {session.name} -- <target>")
    target = session.posargs[0]
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1", "TEST_TARGET_ROLE": target}
    session.run("molecule", "-vvv", "test", "-s", "ansible_test_integration", external=True, env=env)


@nox.session(default=False)
def test_default(session: nox.Session):
    """Run the default molecule scenario."""
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    session.run("molecule", "-vvv", "test", "-s", "default", external=True, env=env)


@nox.session(default=False)
def test_gather_facts(session: nox.Session):
    """Run the gather_facts molecule scenario."""
    env = {"PY_COLORS": "1", "ANSIBLE_FORCE_COLOR": "1"}
    session.run("molecule", "-vvv", "test", "-s", "gather_facts", external=True, env=env)


@nox.session(default=False)
def integration(session: nox.Session):
    """Run molecule integration tests for all plugins (molecule_integration scenario)."""
    _run_integration(session)


UCODE_TESTS = Path("tests/ucode")
UTEST_FEED = "https://m00qek.github.io/packages.ucode.dev"
# utest is only published in a third-party feed, so the package is pinned by file and checksum.
# OpenWrt series without an entry here are skipped. Bump every entry together.
UTEST_PACKAGES = {
    "24.10": (
        "24.10/ucode-utest_1.5.1-r1_all.ipk",
        "2d77a33730dacde690042c5b846728841de31f2004c9dcf61e87164d616fa326",
        "mkdir -p /var/lock && opkg install",
    ),
    "25.12": (
        "25.12/noarch/ucode-utest-1.5.1-r1.apk",
        "8fbd018ac964c4a1d54964fd3be5f9e95ed3a45d8e814f37922c79720ea9af08",
        "apk add --allow-untrusted",
    ),
}


def _openwrt_series(version: str) -> str:
    return ".".join(version.split(".")[:2])


def _utest_command(registry: str, version: str, utest_args: list[str]) -> list[str]:
    package, sha256, install = UTEST_PACKAGES[_openwrt_series(version)]
    pkg_file = f"/tmp/{Path(package).name}"
    script = (
        f"wget -q -O {pkg_file} {UTEST_FEED}/{package} && "
        f"echo '{sha256}  {pkg_file}' | sha256sum -c -s && "
        f"{install} {pkg_file} >/dev/null 2>&1 && "
        'utest "$@"'
    )
    return [
        "docker", "run", "--rm", "-v", f"{Path.cwd()}:/src:ro", "-w", f"/src/{UCODE_TESTS}",
        f"{registry}/openwrt/rootfs:x86_64-{version}",
        "sh", "-c", script, "sh", *utest_args,
    ]  # fmt: skip


def _utest_summary(version: str, report: dict) -> str:
    stats = report["stats"]
    lines = [
        f"### ucode unit tests: OpenWrt {version}",
        "",
        "| Total | Passed | Failed | Errors | Fatal | Skipped |",
        "| ---: | ---: | ---: | ---: | ---: | ---: |",
        f"| {stats['total']} | {stats['passed']} | {stats['failed']} | {stats['errors']} | {stats['fatals']} "
        f"| {stats['skipped']} |",
        "",
    ]
    for failure in report["failures"]:
        test_name = " › ".join(step["name"] for step in failure.get("path", [])[1:])
        lines += [
            f"- **{failure.get('status', failure['event'])}** `{failure['suite']}` {test_name}".rstrip(),
            "",
            "  ```",
            *(f"  {line}" for line in str(failure["error"]).splitlines()),
            "  ```",
            "",
        ]
    return "\n".join(lines) + "\n"


def _annotation_escape(text: str, is_property: bool = False) -> str:
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return text.replace(":", "%3A").replace(",", "%2C") if is_property else text


def _test_line(test_file: Path, test_name: str) -> int | None:
    for number, line in enumerate(test_file.read_text().splitlines(), start=1):
        if f"'{test_name}'" in line or f'"{test_name}"' in line:
            return number
    return None


def _utest_annotations(version: str, report: dict) -> list[str]:
    annotations = []
    for failure in report["failures"]:
        test_file = UCODE_TESTS / failure["suite"]
        names = [step["name"] for step in failure.get("path", [])[1:]]
        properties = {"file": str(test_file), "title": f"OpenWrt {version}: {' › '.join(names) or failure['event']}"}
        line = _test_line(test_file, names[-1]) if names and test_file.is_file() else None
        if line:
            properties["line"] = str(line)
        props = ",".join(f"{key}={_annotation_escape(value, True)}" for key, value in properties.items())
        annotations.append(f"::error {props}::{_annotation_escape(str(failure['error']))}")
    return annotations


def _run_utest_with_summary(session: nox.Session, cmd: list[str], version: str, summary_file: Path) -> bool:
    output = session.run(*cmd, external=True, silent=True, success_codes=range(256))
    try:
        report = json.loads(output.strip().splitlines()[-1])
    except (IndexError, ValueError):
        session.error(f"utest produced no JSON report on OpenWrt {version}:\n{output}")
    summary = _utest_summary(version, report)
    print(summary)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print("\n".join(_utest_annotations(version, report)))
    with summary_file.open("a") as f:
        f.write(summary)
    stats = report["stats"]
    return not (stats["failed"] or stats["errors"] or stats["fatals"])


@nox.session(default=False)
def ucode_units(session: nox.Session):
    """Run the ucode unit tests with utest in OpenWrt containers. Posargs: [--openwrt VERSION] [--summary FILE] [utest options]"""
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument(
        "--openwrt", action="append", help="OpenWrt version, repeatable (default: tests/molecule/openwrt.yml)"
    )
    parser.add_argument("--summary", type=Path, help="append a Markdown report to this file, e.g. $GITHUB_STEP_SUMMARY")
    args, utest_args = parser.parse_known_args(session.posargs)

    openwrt_cfg = _read_openwrt()
    bundles = sorted({f"{p.parent.relative_to(UCODE_TESTS)}/" for p in UCODE_TESTS.glob("**/test_*.uc")})
    if args.summary:
        utest_args += ["-r", "json"]

    failed = []
    for version in args.openwrt or openwrt_cfg["versions"]:
        if _openwrt_series(version) not in UTEST_PACKAGES:
            if args.openwrt:
                session.error(f"No utest package for OpenWrt {version}")
            session.log(f"Skipping OpenWrt {version}: no utest package for it")
            continue

        cmd = _utest_command(openwrt_cfg["registry"], version, [*utest_args, *bundles])
        session.log(f"OpenWrt {version}")
        if not args.summary:
            session.run(*cmd, external=True)
            continue

        if not _run_utest_with_summary(session, cmd, version, args.summary):
            failed.append(version)

    if failed:
        session.error(f"ucode unit tests failed on OpenWrt {', '.join(failed)}")


@nox.session(default=False)
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


@nox.session(default=False)
def openwrt_version(session: nox.Session):
    """
    Manage OpenWrt versions in tests/molecule/openwrt.yml.

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

    openwrt_test_config = _read_openwrt()
    if cmd == "list":
        for v in openwrt_test_config["versions"]:
            session.log(v)
        return

    check_no_modifications(session)
    session.run("git", "checkout", "main", external=True)
    session.run("git", "pull", "--rebase", "upstream", "main", external=True)
    versions = openwrt_test_config["versions"]

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
    openwrt_test_config["versions"] = new_versions
    _write_openwrt(openwrt_test_config)
    session.run("git", "add", str(OPENWRT_FILE), external=True)
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
