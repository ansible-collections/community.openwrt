// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// Helpers shared by the WireGuard modules.

export function render_template(source, scope) {
    if (type(source) != 'string')
        return '';

    let saved = {};
    let absent = {};
    for (let name in scope) {
        if (exists(global, name))
            saved[name] = global[name];
        else
            absent[name] = true;
        global[name] = scope[name];
    }

    let output = '';
    let template = loadstring(source, { raw_mode: false });
    if (template != null) {
        try {
            output = sprintf('%s', render(template));
        } catch (e) {
            output = '';
        }
    }

    for (let name in saved)
        global[name] = saved[name];
    for (let name in absent)
        delete global[name];

    return output;
};

export function peer_section(template, iface, section, proto) {
    return render_template(template, {
        iface_name: iface,
        section: section ?? '',
        proto: proto,
    });
};
