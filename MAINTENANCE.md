# Release and Maintenance

This document describes _how_ and _when_ community.openwrt is released and maintained.

The policies written here are meant more as guidelines than as strict rules - objective results, flexibility and adaptability are to be valued over compliance.

These policies become effective after the release of community.openwrt 1.0.0.

## Versioning

- This collection uses [Semantic Versioning](https://semver.org/).
- `galaxy.yml` in the `main` branch will always contain the `version` of the **next** major or minor release. It will be updated right after a release.
- `version_added` needs to be used for every new feature and module/plugin, and needs to coincide with the next minor/major release version. (This will eventually be enforced by CI.)

## Collection Releases

### Major versions

The collection will release major versions twice per year, around January and July. Exact dates will decided by RMs closer to the release and will be announced and published in the [Release History](https://github.com/ansible-collections/community.openwrt/issues/100) issue in GitHub.

Upon releasing a major version, support is updated:

- **OpenWrt:** all the versions that are End of Life except the last one.
  - If OpenWrt has a release candidate (rc) published for an upcoming release by the time of the community.openwrt release, it may or may not be supported by the collection, at the discretion of the RMs.
    - If an `rc` version is included in the support, it will be replaced by the official release when available.
  - The automated tests use OpenWrt images with their full version number, including service release (see below for the reference about their numbering scheme). The service number for those images will be updated to match the last available release, but that will happen on a best-effort basis. At any given time, the collection might be testing against one or two service releases prior to the latest one.
- **ansible-core:** drop support for all versions that are End of Life.
- **community.openwrt:** drop support for all previous major versions of the collection.
  - Note that dropping previous major versions of community.openwrt itself simplifies its maintenance process considerably. This is going to be revisited if demand for backports builds up.

### Minor versions

The collection will release minor versions periodically, between major versions.

- release will happen shortly after (may vary depending on circumstances) community.general `x.y.0` releases, or roughly every four weeks.
- RMs may skip a minor release if no new features were added in the previous period.

There is no dependency between community.openwrt and community.general, their releases are being used as a benchmark/reminder for the release scheduling of this collection.

### Patch versions

- Patch versions `x.y.z` until the last minor release of a major release branch will only be released when necessary. The intended frequency is _never_, they are reserved for packaging failures, or fixing major breakage / security problems.
- These releases will happen regularly and when necessary.

## Deprecation policy

- Deprecations are done by version number (not by date).
- New deprecations can be added during every minor release, under the condition that they **do not break backwards compatibility**.
- Deprecations are expected to have a deprecation cycle of at least 2 major versions (that means at least 1 year). Maintainers can use a longer deprecation cycle if they want to support the old code for that long.

Note that these policies have been copied literally from community.general, and they are not without caveats:

- the collection just starting its lifetime: there is no measurement, subjective or otherwise, to the demand for deprecating features in the code base
- the shell-based implementation of community.openwrt does not support the standard deprecation mechanism in modules or other plugins, so the **deprecation is documentary only**. Until that mechanism is implemented, there is no deprecation warnings sent to the users or developers.

## Collection Release Process

The collection uses the [Releasing collections without release branches](https://docs.ansible.com/projects/ansible/latest/community/collection_contributors/collection_release_without_branches.html)
process.

## Changelogs

Per the process mentioned above, changelogs are generated using the [antsibull-changelog](https://github.com/ansible-community/antsibull-changelog) tool. Check its documentation for details.

Changelogs are added as [fragments](https://docs.ansible.com/ansible/devel/community/development_process.html#changelogs-how-to), following the rules:

- Fragments MUST NOT be added for new module PRs and new plugin PRs.
- Fragments MUST NOT be added for PRs that only affect docs or tests.
- All other changes MUST provide a changelog fragment.
  - Exception: fixing/extending a feature that already has a changelog fragment and has not yet been released. Such PRs **must** always link to the original PR(s) they update.
  - Use your common sense!
- The `(x+1).0.0` changelog continues the `x.0.0` changelog.
- The `x.y.0` changelog with `y > 0` continues the `x.0.0` changelog.
- The `x.y.z` changelog with `z > 0` continues the `x.y.0` changelog.
- Changelogs do not contain previous major releases, and only use the `ancestor` feature (in `changelogs/changelog.yaml`) to point to the previous major release.
- Changelog fragments are removed after a release is made.

## External Dependencies

The collection is affected by many direct and indirect dependencies, but especially by the OpenWrt and ansible-core projects.

The purpose of this section is to establish context about these dependencies' release and support policies.
This section is merely descriptive of these external dependencies and does not establish any specific policy.
However, major events in those projects might prompt adjustments or other adhoc actions related to community.openwrt releases.

### OpenWrt

The [OpenWrt project](https://openwrt.org/) does not follow a fixed schedule, but it has a [Support Status](https://openwrt.org/docs/guide-developer/security#support_status) documentation.
The project has its own version numbering scheme, as stated in its [Release history](https://openwrt.org/about/history#release_history) documentation.

It typically rolls out one release (major version) per year, and a number of service releases as needed during the lifetime of that release. Historically, the actual release happens a number of months after that stable branch numbering.

Per the project rules, there is always one release in the **Supported** status. There will be a release in the **Security Maintenance** status for a period of time, and the expected long list of **End of Life** releases.

### ansible-core

The project is governed by a [flexible release cycle](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-release-cycle). It uses Semantic Versioning.

Typically, it releases two minor versions per year. As indicated, the schedule is flexible, and the plans for upcoming releases are usually found in the [ansible-core Roadmaps](https://docs.ansible.com/projects/ansible/latest/roadmap/ansible_core_roadmap_index.html#ansible-core-roadmaps).

Per the project rules, the last 3 releases are supported with bug and security fixes.
