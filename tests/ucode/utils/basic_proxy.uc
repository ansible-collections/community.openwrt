// Copyright (c) 2026, Alexei Znamensky (@russoz)
// GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

// utest proxy for _basic.uc. utest cannot inspect an ES module, so the shim is
// generated from `api`, which must list every export of _basic.uc. Unpatched,
// the shim calls the real module; while _basic is patched, calls go to the
// behavior overrides given to mock.global.patch() and nothing else.

const API = [ 'AnsibleModule', 'deep_equal', 'process_id', 'shell_quote' ];

function forward(ctx, fn_name) {
    return function(...args) {
        let behavior = ctx.get_behavior(fn_name);
        if (behavior == null)
            die(`_basic.${fn_name}() called while _basic is mocked, with no behavior for it`);
        return behavior(...args);
    };
}

return {
    api: API,
    create: function(name, real, ctx) {
        let proxy = {};
        for (let fn_name in API)
            proxy[fn_name] = forward(ctx, fn_name);
        return proxy;
    },
};
