// Copyright (c) 2026, Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, it, assert } from 'utest';
import { peer_section, render_template } from '_wg';

const PEER_ID = '{% if (section): %}peer_{{ iface_name }}_{{ section }}{% else %}peer_{{ iface_name }}{% endif %}';

describe('render_template()', () => {
    it('renders the scope variables', () => {
        assert.match('wg0_in', render_template('{{ iface_name }}_in', { iface_name: 'wg0' }));
    });

    it('renders an integer variable', () => {
        assert.match('port-51820', render_template('port-{{ listen_port }}', { listen_port: 51820 }));
    });

    it('renders an unset variable as nothing', () => {
        assert.match('x_', render_template('x_{{ nowhere_to_be_found }}', {}));
    });

    it('returns an empty string for a template that is not a string', () => {
        assert.match('', render_template(null, {}));
        assert.match('', render_template(42, {}));
    });

    it('raises the error of a template that does not compile', () => {
        assert.throws(() => render_template('{{ iface_name ', { iface_name: 'wg0' }), 'Unterminated template block');
    });

    it('raises the error of a template that fails to render', () => {
        assert.throws(() => render_template('{{ die("boom") }}', {}), 'boom');
    });

    it('removes the globals it added when the template fails', () => {
        assert.throws(() => render_template('{{ die("boom") }}', { wg_test_failed: 'scoped' }), 'boom');
        assert.match(false, exists(global, 'wg_test_failed'));
    });

    it('restores a global it shadowed', () => {
        global.wg_test_shadowed = 'kept';
        render_template('{{ wg_test_shadowed }}', { wg_test_shadowed: 'scoped' });
        assert.match('kept', global.wg_test_shadowed);
        delete global.wg_test_shadowed;
    });

    it('removes a global it added', () => {
        render_template('{{ wg_test_added }}', { wg_test_added: 'scoped' });
        assert.match(false, exists(global, 'wg_test_added'));
    });
});

describe('peer_section()', () => {
    it('names the peer after the interface alone without a section', () => {
        assert.match('peer_wg0', peer_section(PEER_ID, 'wg0', null, 'wireguard'));
        assert.match('peer_wg0', peer_section(PEER_ID, 'wg0', '', 'wireguard'));
    });

    it('appends the section to the peer name', () => {
        assert.match('peer_wg0_spoke1', peer_section(PEER_ID, 'wg0', 'spoke1', 'wireguard'));
    });

    it('has the protocol in scope', () => {
        assert.match('amneziawg_awg1', peer_section('{{ proto }}_{{ iface_name }}', 'awg1', null, 'amneziawg'));
    });
});
