# Community OpenWrt Release Notes

**Topics**

- <a href="#v0-3-0">v0\.3\.0</a>
    - <a href="#release-summary">Release Summary</a>
- <a href="#v0-2-0">v0\.2\.0</a>
    - <a href="#release-summary-1">Release Summary</a>
    - <a href="#minor-changes">Minor Changes</a>
    - <a href="#new-modules">New Modules</a>
- <a href="#v0-1-0">v0\.1\.0</a>
    - <a href="#release-summary-2">Release Summary</a>

<a id="v0-3-0"></a>
## v0\.3\.0

<a id="release-summary"></a>
### Release Summary

Add <code>\.devcontainer</code> setup\.
Create User and Module Dev Guides\.
Generate collection docs in GitHub\.
Simplify collection\-level molecule tests\.
Rename setup role to <code>community\.openwrt\.init</code>\.

<a id="v0-2-0"></a>
## v0\.2\.0

<a id="release-summary-1"></a>
### Release Summary

Use action plugins to \"wrap\" shell\-based modules\.
Update <code>build\_ignore</code> in <code>galaxy\.yml</code>\.
Move module docs to <code>\.py</code> files\.
Mark <code>shell\=ash</code> for <code>shellcheck</code>\.

<a id="minor-changes"></a>
### Minor Changes

* command \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* command action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* copy \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* copy action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* file \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* file action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* lineinfile \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* lineinfile action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* nohup \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* nohup action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* openwrt\_action plugin utils \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* opkg \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* opkg action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* ping \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* ping action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* service \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* service action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* setup \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* setup action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* slurp \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* slurp action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* stat \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* stat action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* sysctl \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* sysctl action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* uci \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* uci action plugin \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.
* wrapper \- revamp the shell wrapping mechanism \([https\://github\.com/ansible\-collections/community\.openwrt/pull/14](https\://github\.com/ansible\-collections/community\.openwrt/pull/14)\)\.

<a id="new-modules"></a>
### New Modules

* community\.openwrt\.wrapper \- Internal wrapper module for OpenWRT shell\-based modules\.

<a id="v0-1-0"></a>
## v0\.1\.0

<a id="release-summary-2"></a>
### Release Summary

This is the first release of the <code>community\.openwrt</code> collection\.
The code in this collection was mostly brought over from gekmihesg\.openwrt \(Ansible role\)\.
