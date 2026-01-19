# Release and Maintenance

This document describes _how_ and _when_ community.openwrt is released and maintained.

## Versioning

This collection uses [Semantic Versioning](https://semver.org/).

## Dependencies

The release and support of community.openwrt will be aligned with those of both OpenWrt and `ansible-core`.

### OpenWrt

#### Releases

The [OpenWrt project](https://openwrt.org/) does not follow a fixed schedule, but it has a [Support Status](https://openwrt.org/docs/guide-developer/security#support_status) documentation.

The project has its own version numbering scheme, as stated in its [Release history](https://openwrt.org/about/history#release_history) documentation.

It typically rolls out one release per year, and a number of service releases as needed during the lifetime of that release. Historically, the actual release happens a number of months after the stable branch numbering.

#### Support

Per the project rules, there is always one release in the **Supported** status. There will be a release in the **Security Maintenance** status for a period of time, and the long list of **End of Life** releases.

The collection community.openwrt will support the OpenWrt in status **Supported**, **Security Maintenance** (if one exists), and the latest **Enf of Life** release.

Reference: [OpenWrt support status](https://openwrt.org/docs/guide-developer/security#support_status)

### ansible-core

#### Releases

The project is governed by a [flexible release cycle](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-release-cycle). It uses Semantic Versioning.

Typically, it releases two minor versions per year. As indicated, the schedule is flexible, but the plans for upcoming releases are usually found in the [ansible-core Roadmaps](https://docs.ansible.com/projects/ansible/latest/roadmap/ansible_core_roadmap_index.html#ansible-core-roadmaps).

#### Support

Per the project rules, the last 3 releases are supported with bug and security fixes.

The collection community.openwrt will support the **last 3 releases of ansible-core**.

Reference: [ansible-core support status](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-support-matrix)

## Collection Releases

We acknowledge the importance and impact that the releases of both OpenWrt and ansible-core may have in this collection. On the other hand, the timing of their releases is not fixed and often many months apart from each other.

## Deprecation policy

Like any other software, this collection is bound to remove features or components, usually in favor of a better option.

There is no policy for deprecations at this time. This derives from:

- the fact that there is no fixed release schedule at this point for the collection
- despite the fact that Ansible has a deprecation mechanism to let users and developers know about deprecated features, the shell-based implementation of community.openwrt does not support that mechanism.
