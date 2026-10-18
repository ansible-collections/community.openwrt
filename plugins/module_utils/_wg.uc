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
    let error = null;
    try {
        output = sprintf('%s', render(loadstring(source, { raw_mode: false })));
    } catch (e) {
        error = e;
    }

    for (let name in saved)
        global[name] = saved[name];
    for (let name in absent)
        delete global[name];

    if (error != null)
        die(error.message);
    return output;
};

export function peer_section(template, iface, section, proto) {
    return render_template(template, {
        iface_name: iface,
        section: section ?? '',
        proto: proto,
    });
};

// The protocol of a peer: its own, then the one of its interface section,
// then `fallback`, then wireguard. A peer only works in a section typed after
// the protocol of its interface, so the interface wins over module defaults.
export function peer_protocol(cursor, peer, fallback) {
    if (peer.proto != null)
        return peer.proto;
    let proto = cursor.get('network', peer.iface, 'proto');
    if (proto == 'wireguard' || proto == 'amneziawg')
        return proto;
    return fallback ?? 'wireguard';
};
