# Community OpenWrt Release Notes

**Topics**

- <a href="#v1-2-0">v1\.2\.0</a>
    - <a href="#release-summary">Release Summary</a>
    - <a href="#minor-changes">Minor Changes</a>
    - <a href="#bugfixes">Bugfixes</a>
    - <a href="#new-modules">New Modules</a>
- <a href="#v1-1-0">v1\.1\.0</a>
    - <a href="#release-summary-1">Release Summary</a>
    - <a href="#minor-changes-1">Minor Changes</a>
    - <a href="#bugfixes-1">Bugfixes</a>
    - <a href="#new-modules-1">New Modules</a>
- <a href="#v1-0-0">v1\.0\.0</a>
    - <a href="#release-summary-2">Release Summary</a>
- <a href="#v0-4-0">v0\.4\.0</a>
    - <a href="#release-summary-3">Release Summary</a>
    - <a href="#minor-changes-2">Minor Changes</a>
    - <a href="#new-modules-2">New Modules</a>
- <a href="#v0-3-0">v0\.3\.0</a>
    - <a href="#release-summary-4">Release Summary</a>
- <a href="#v0-2-0">v0\.2\.0</a>
    - <a href="#release-summary-5">Release Summary</a>
    - <a href="#minor-changes-3">Minor Changes</a>
    - <a href="#new-modules-3">New Modules</a>
- <a href="#v0-1-0">v0\.1\.0</a>
    - <a href="#release-summary-6">Release Summary</a>

<a id="v1-2-0"></a>
## v1\.2\.0

<a id="release-summary"></a>
### Release Summary

Regular and bugfix release\.

<a id="minor-changes"></a>
### Minor Changes

* copy action plugin \- remove redundant code \([https\://github\.com/ansible\-collections/community\.openwrt/pull/192](https\://github\.com/ansible\-collections/community\.openwrt/pull/192)\)\.
* openwrt\_action plugin utils \- remove redundant code \([https\://github\.com/ansible\-collections/community\.openwrt/pull/192](https\://github\.com/ansible\-collections/community\.openwrt/pull/192)\)\.

<a id="bugfixes"></a>
### Bugfixes

* copy \- fix destination file name if <code>dest</code> is a directory \([https\://github\.com/ansible\-collections/community\.openwrt/pull/165](https\://github\.com/ansible\-collections/community\.openwrt/pull/165)\)\.
* openwrt\_action plugin utils \- exception classes were not calling the parent\'s constructor correctly \([https\://github\.com/ansible\-collections/community\.openwrt/pull/161](https\://github\.com/ansible\-collections/community\.openwrt/pull/161)\)\.

<a id="new-modules"></a>
### New Modules

* community\.openwrt\.group \- Add or remove groups\.

<a id="v1-1-0"></a>
## v1\.1\.0

<a id="release-summary-1"></a>
### Release Summary

See [https\://github\.com/ansible\-collections/community\.openwrt/blob/main/CHANGELOG\.md](https\://github\.com/ansible\-collections/community\.openwrt/blob/main/CHANGELOG\.md) for all changes\.

<a id="minor-changes-1"></a>
### Minor Changes

* init role \- enable check mode in the task checking package manager compatibility \([https\://github\.com/ansible\-collections/community\.openwrt/pull/136](https\://github\.com/ansible\-collections/community\.openwrt/pull/136)\)\.
* nohup \- use <code>init\(\)</code> function to declare parameters \([https\://github\.com/ansible\-collections/community\.openwrt/pull/131](https\://github\.com/ansible\-collections/community\.openwrt/pull/131)\)\.
* setup \- collect <code>ansible\_date\_time</code> facts as well \([https\://github\.com/ansible\-collections/community\.openwrt/issues/52](https\://github\.com/ansible\-collections/community\.openwrt/issues/52)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/138](https\://github\.com/ansible\-collections/community\.openwrt/pull/138)\)\.
* setup \- report <code>ansible\_pkg\_mgr</code> fact with the detected package manager used \([https\://github\.com/ansible\-collections/community\.openwrt/pull/136](https\://github\.com/ansible\-collections/community\.openwrt/pull/136)\)\.

<a id="bugfixes-1"></a>
### Bugfixes

* ping \- module code must indicate it does not support check mode \([https\://github\.com/ansible\-collections/community\.openwrt/pull/132](https\://github\.com/ansible\-collections/community\.openwrt/pull/132)\)\.
* setup \- generate an empty factoid when the underlying command <code>ubus call</code> returns empty \([https\://github\.com/ansible\-collections/community\.openwrt/issues/149](https\://github\.com/ansible\-collections/community\.openwrt/issues/149)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/151](https\://github\.com/ansible\-collections/community\.openwrt/pull/151)\)\.

<a id="new-modules-1"></a>
### New Modules

* community\.openwrt\.package\_facts \- Gather package facts in OpenWrt systems\.
* community\.openwrt\.tempfile \- Creates temporary files and directories on OpenWrt nodes\.

<a id="v1-0-0"></a>
## v1\.0\.0

<a id="release-summary-2"></a>
### Release Summary

First GA release of the community\.openwrt collection\.

<a id="v0-4-0"></a>
## v0\.4\.0

<a id="release-summary-3"></a>
### Release Summary

Establish mechanism for integration testing\.
Add support to the <code>apk</code> package manager\.
Modules now have lifecycle functions <code>init\(\)</code> and <code>validate\(\)</code>\.

<a id="minor-changes-2"></a>
### Minor Changes

* command \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* copy \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* file \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* lineinfile \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* opkg \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* service \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* slurp \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* stat \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* sysctl \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* uci \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.
* wrapper \- use functions <code>init\(\)</code> and <code>validate\(\)</code> \([https\://github\.com/ansible\-collections/community\.openwrt/issues/47](https\://github\.com/ansible\-collections/community\.openwrt/issues/47)\, [https\://github\.com/ansible\-collections/community\.openwrt/pull/67](https\://github\.com/ansible\-collections/community\.openwrt/pull/67)\)\.

<a id="new-modules-2"></a>
### New Modules

* community\.openwrt\.apk \- Manage packages with apk on OpenWrt\.

<a id="v0-3-0"></a>
## v0\.3\.0

<a id="release-summary-4"></a>
### Release Summary

Add <code>\.devcontainer</code> setup\.
Create User and Module Dev Guides\.
Generate collection docs in GitHub\.
Simplify collection\-level molecule tests\.
Rename setup role to <code>community\.openwrt\.init</code>\.

<a id="v0-2-0"></a>
## v0\.2\.0

<a id="release-summary-5"></a>
### Release Summary

Use action plugins to \"wrap\" shell\-based modules\.
Update <code>build\_ignore</code> in <code>galaxy\.yml</code>\.
Move module docs to <code>\.py</code> files\.
Mark <code>shell\=ash</code> for <code>shellcheck</code>\.

<a id="minor-changes-3"></a>
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

<a id="new-modules-3"></a>
### New Modules

* community\.openwrt\.wrapper \- Internal wrapper module for OpenWrt shell\-based modules\.

<a id="v0-1-0"></a>
## v0\.1\.0

<a id="release-summary-6"></a>
### Release Summary

This is the first release of the <code>community\.openwrt</code> collection\.
The code in this collection was mostly brought over from gekmihesg\.openwrt \(Ansible role\)\.
