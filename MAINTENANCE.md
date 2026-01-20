# Release and Maintenance

This document describes _how_ and _when_ community.openwrt is released and maintained.

These rules become effective after the release of community.openwrt 1.0.0.

## Versioning

- This collection uses [Semantic Versioning](https://semver.org/).
- `galaxy.yml` in the `main` branch will always contain the version of the **next** major or minor release. It will be updated right after a release.
- `version_added` needs to be used for every new feature and module/plugin, and needs to coincide with the next minor/major release version. (This will eventually be enforced by CI.)

## Collection Releases

### Major versions

The collection will release major versions twice per year, around January and July. Exact dates will decided by RMs closer to the release and will be announced and published in the [Release History](https://github.com/ansible-collections/community.openwrt/issues/100) issue in GitHub.

Upon releasing a major version, support is dropped for:

- **community.openwrt:** all previous major versions of the collection.
- **OpenWrt:** all the versions that are End of Life except the last one.
- **ansible-core:** all the versions that are End of Life.

Note that dropping previous major versions simplifies the maintenance process of the collection significantly. This is likely going to change if the collection gathers traction and users start demanding backports to older versions.

### Minor versions

TBD

### Patch versions

- Patch versions `x.y.z` until the last minor release of a major release branch will only be released when necessary. The intended frequency is *never*, they are reserved for packaging failures, or fixing major breakage / security problems.
- Once the last minor release of a major release branch (usually `x.2.0`, generally `x.Y.0`) has been released, there will be bugfix releases `x.Y.z`.
- These releases will happen regularly and when necessary.
TBD

## Deprecation policy

- Deprecations are done by version number (not by date).
- New deprecations can be added during every minor release, under the condition that they **do not break backwards compatibility**.
- Deprecations are expected to have a deprecation cycle of at least 2 major versions (that means at least 1 year). Maintainers can use a longer deprecation cycle if they want to support the old code for that long.

That policy has been copied literally from community.general, but there is a lot of uncertainty about life cycles and policies at this time. This derives from:

- the collection just starting its lifetime: there is no measurement, subjective or otherwise, to the demand for deprecating features in the code base
- the shell-based implementation of community.openwrt does not support the standard deprecation mechanism in modules or other plugins

## Version Release Process

The

## Dependencies

The release and support of community.openwrt will be aligned with those of both OpenWrt and `ansible-core`.

### OpenWrt

#### Releases

The [OpenWrt project](https://openwrt.org/) does not follow a fixed schedule, but it has a [Support Status](https://openwrt.org/docs/guide-developer/security#support_status) documentation.

The project has its own version numbering scheme, as stated in its [Release history](https://openwrt.org/about/history#release_history) documentation.

It typically rolls out one release per year, and a number of service releases as needed during the lifetime of that release. Historically, the actual release happens a number of months after the stable branch numbering.

#### Support

Per the project rules, there is always one release in the **Supported** status. There will be a release in the **Security Maintenance** status for a period of time, and the long list of **End of Life** releases.

The collection community.openwrt will support the OpenWrt in status **Supported**, **Security Maintenance** (if one exists), and the latest **End of Life** release.

Reference: [OpenWrt support status](https://openwrt.org/docs/guide-developer/security#support_status)

### ansible-core

#### Releases

The project is governed by a [flexible release cycle](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-release-cycle). It uses Semantic Versioning.

Typically, it releases two minor versions per year. As indicated, the schedule is flexible, but the plans for upcoming releases are usually found in the [ansible-core Roadmaps](https://docs.ansible.com/projects/ansible/latest/roadmap/ansible_core_roadmap_index.html#ansible-core-roadmaps).

#### Support

Per the project rules, the last 3 releases are supported with bug and security fixes.

The collection community.openwrt will support the **last 3 releases of ansible-core**.

Reference: [ansible-core support status](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-support-matrix)
