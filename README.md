# Community OpenWrt Collection

[![CI](https://github.com/ansible-collections/community.openwrt/actions/workflows/ansible-test.yml/badge.svg)](https://github.com/ansible-collections/community.openwrt/actions/workflows/ansible-test.yml)
[![Collection Docs (PUSH)](https://github.com/ansible-collections/community.openwrt/actions/workflows/docs-push.yml/badge.svg)](https://github.com/ansible-collections/community.openwrt/actions/workflows/docs-push.yml)

<!--
[![Codecov](https://img.shields.io/codecov/c/github/ansible-collections/community.openwrt)](https://codecov.io/gh/ansible-collections/community.openwrt)
 -->

This collection enables the automated configuration of your OpenWrt devices.

We encourage new users to read the [User Guide](https://ansible-collections.github.io/community.openwrt/branch/main/docsite/user_guide.html).

If you are migrating from the `gekmihesg.openwrt` role, please read the
[Migration Guide](https://ansible-collections.github.io/community.openwrt/branch/main/docsite/migration_guide.html).

## Our mission

<!-- Put your collection's mission statement in here. Example follows. -->

At the `community.openwrt`, our mission is to produce and maintain simple, flexible,
and powerful open-source software tailored to manage and support [OpenWrt](https://openwrt.org/) devices.

This Ansible collection is originally based on the role `gekmihesg.openwrt`, maintained by [Markus Weippert](https://github.com/gekmihesg) until 2022.
We acknowledge and we are grateful for the time and effort he dispensed to maintain that role over the years.

We welcome members from all skill levels to participate actively in our open, inclusive, and vibrant community.
Whether you are an expert or just beginning your journey with Ansible and `community.openwrt`,
you are encouraged to contribute, share insights, and collaborate with fellow enthusiasts!

## Code of Conduct

We follow the [Ansible Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html) in all our interactions within this project.

If you encounter abusive behavior, please refer to the [policy violations](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html#policy-violations) section of the Code for information on how to raise a complaint.

## Communication

- Join the Ansible forum:
  - [Get Help](https://forum.ansible.com/c/help/6): get help or help others. Please add appropriate tags if you start new discussions, for example the `community-openwrt` tag.
  - [Posts tagged with 'community-openwrt'](https://forum.ansible.com/tag/community-openwrt): subscribe to participate in collection/technology-related conversations.
  - [Refer to your forum group here if exists](https://forum.ansible.com/g/): by joining the team you will automatically get subscribed to the posts tagged with [your group forum tag here](https://forum.ansible.com/tags).
  - [Social Spaces](https://forum.ansible.com/c/chat/4): gather and interact with fellow enthusiasts.
  - [News & Announcements](https://forum.ansible.com/c/news/5): track project-wide announcements including social events. The [Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn), which is used to announce releases and important changes, can also be found here.

For more information about communication, see the [Ansible communication guide](https://docs.ansible.com/ansible/devel/community/communication.html).

## Contributing to this collection

<!--Describe how the community can contribute to your collection. At a minimum, fill up and include the CONTRIBUTING.md file containing how and where users can create issues to report problems or request features for this collection. List contribution requirements, including preferred workflows and necessary testing, so you can benefit from community PRs. If you are following general Ansible contributor guidelines, you can link to - [Ansible Community Guide](https://docs.ansible.com/ansible/devel/community/index.html). List the current maintainers (contributors with write or higher access to the repository). The following can be included:-->

The content of this collection is made by people like you, a community of individuals collaborating on making the world better through developing automation software.

We are actively accepting new contributors and all types of contributions are very welcome.

Don't know how to start? Refer to the [Ansible community guide](https://docs.ansible.com/ansible/devel/community/index.html)!

Want to submit code changes? Take a look at the [Quick-start development guide](https://docs.ansible.com/ansible/devel/community/create_pr_quick_start.html).

We also use the following guidelines:

- [Collection review checklist](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_reviewing.html)
- [Ansible development guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
- [Ansible collection development guide](https://docs.ansible.com/ansible/devel/dev_guide/developing_collections.html#contributing-to-collections)

## Collection maintenance

<!-- The current maintainers are listed in the [MAINTAINERS](MAINTAINERS) file. If you have questions or need help, feel free to mention them in the proposals. -->

To learn how to maintain/become a maintainer of this collection, refer to the [Maintainer guidelines](https://docs.ansible.com/ansible/devel/community/maintainers.html).

It is necessary for maintainers of this collection to be subscribed to:

- The collection itself (the `Watch` button -> `All Activity` in the upper right corner of the repository's homepage).
- The [news-for-maintainers repository](https://github.com/ansible-collections/news-for-maintainers).

They also should be subscribed to Ansible's [The Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn).

## Governance

<!--Describe how the collection is governed. Here can be the following text:-->

The process of decision making in this collection is based on discussing and finding consensus among participants.

Every voice is important. If you have something on your mind, create an issue or dedicated discussion and let's discuss it!

## Tested with Ansible

<!-- List the versions of Ansible the collection has been tested with. Must match what is in galaxy.yml. -->

The collection is currently tested with `ansible-core` versions:

- 2.17
- 2.18
- 2.19
- 2.20
- devel

## External requirements

The collection is currently tested against OpenWRT versions:

- 21.02
- 22.03
- 23.05
- 24.10

Keep in mind that OpenWrt, per its
[Support Status policy](https://openwrt.org/docs/guide-developer/security#support_status),
support at most two different release numbers. In fact, OpenWrt 23.05 was
[declared EOL](https://forum.openwrt.org/t/openwrt-23-05-6-service-release/239506) in Aug 2025.

Though this collection is tested against older versions of OpenWrt, it is likely that,
in the future, it will synchronize support, to some extent, to that of the OpenWrt releases.

### Testing Requirements

The test uses [Ansible Molecule](https://docs.ansible.com/projects/molecule/) to
spin up containers running OpenWrt (there are images available for the `x86_64` architecture).

Tests require:

- a container runtime (docker, podman, containerd, etc...)
- Python packages specified in [requirements-test.txt](./requirements-test.txt)

#### SSH Connection Limitations

OpenWRT versions prior to 24.10 have been failing while connecting to the containers using SSH.
The client side uses OpenSSH 9.6+ whilst the OpenWrt images use a range of versions of Dropbear SSH server.
There seems to be some incompatibility related to CVE-2023-48795, but OpenWrt 22.03 and 23.05
have had security patches backported into them, so possibly some specific SSH configuration
is missing for that to work.

For the time being, the tests are being performed using:

- OpenWRT 24.10: SSH connections
- OpenWRT 21.02, 22.03, 23.05: Docker connections (SSH incompatible)

All the offending OpenWrt releases are no longer supported by OpenWrt, so this is not a priority for this project.

## Included content

Please check the included content on the [Ansible Galaxy page for this collection](https://galaxy.ansible.com/ui/repo/published/community/openwrt/docs/)

<!-- or the [documentation on the Ansible docs site](https://docs.ansible.com/projects/ansible/latest/collections/community/openwrt/). -->

## Using this collection

<!--Include some quick examples that cover the most common use cases for your collection content. It can include the following examples of installation and upgrade (change community.openwrt correspondingly):-->

```yaml
---
- hosts: openwrt_devices
  gather_facts: false
  roles:
    - community.openwrt.init
  tasks:
    - name: Gather OpenWRT facts
      community.openwrt.setup:

    - name: Install a package
      community.openwrt.opkg:
        name: luci
        state: present

    - name: Configure UCI settings
      community.openwrt.uci:
        command: set
        key: system.@system[0].hostname
        value: myrouter
```

### Installing the Collection from Ansible Galaxy

Before using this collection, you need to install it with the Ansible Galaxy command-line tool:

```bash
ansible-galaxy collection install community.openwrt
```

You can also include it in a `requirements.yml` file and install it with `ansible-galaxy collection install -r requirements.yml`, using the format:

```yaml
---
collections:
  - name: community.openwrt
```

Note that if you install the collection from Ansible Galaxy, it will not be upgraded automatically when you upgrade the `ansible` package. To upgrade the collection to the latest available version, run the following command:

```bash
ansible-galaxy collection install community.openwrt --upgrade
```

You can also install a specific version of the collection, for example, if you need to downgrade when something is broken in the latest version (please report an issue in this repository). Use the following syntax to install version `0.3.0`:

```bash
ansible-galaxy collection install community.openwrt:==0.3.0
```

See [using Ansible collections](https://docs.ansible.com/ansible/devel/user_guide/collections_using.html) for more details.

## Release notes

See the [changelog](https://github.com/ansible-collections/community.openwrt/tree/main/CHANGELOG.rst).

## Roadmap

<!-- Optional. Include the roadmap for this collection, and the proposed release/versioning strategy so users can anticipate the upgrade/update cycle. -->

There is no roadmap for this collection at this moment. One should be created and published if community feedback shows an appetite for it.

## More information

<!-- List out where the user can find additional information, such as working group meeting times, slack/IRC channels, or documentation for the product this collection automates. At a minimum, link to: -->

- [Ansible user guide](https://docs.ansible.com/ansible/devel/user_guide/index.html)
- [Ansible developer guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
- [Ansible collections requirements](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_requirements.html)
- [Ansible community Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html)
- [The Bullhorn (the Ansible contributor newsletter)](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn)
- [Important announcements for maintainers](https://github.com/ansible-collections/news-for-maintainers)

## Licensing

<!-- Include the appropriate license information here and a pointer to the full licensing details. If the collection contains modules migrated from the ansible/ansible repo, you must use the same license that existed in the ansible/ansible repo. See the GNU license example below. -->

GNU General Public License v3.0 or later.

See [LICENSE](https://www.gnu.org/licenses/gpl-3.0.txt) to see the full text.
