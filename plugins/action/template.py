# Copyright (c) 2026 Alexei Znamensky (@russoz)
# Copyright (c) 2026 Ilya Bogdanov (@zeerayne)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from unittest import mock

from ansible.errors import AnsibleAction
from ansible.module_utils.common.text.converters import to_native
from ansible.plugins.action.template import ActionModule as TemplateActionModule
from ansible.plugins.loader import action_loader


class ActionModule(TemplateActionModule):
    def run(self, tmp=None, task_vars=None):

        _getter = self._shared_loader_obj.action_loader.get

        def _get_action(name, task, connection, play_context, loader, templar, shared_loader_obj):
            if name == "ansible.legacy.copy":
                name = "community.openwrt.copy"
                task.action = name

            return _getter(
                name,
                task=task,
                connection=connection,
                play_context=play_context,
                loader=loader,
                templar=templar,
                shared_loader_obj=shared_loader_obj,
            )

        # ansible-core >= 2.19 (https://github.com/ansible/ansible/pull/84621) dropped the
        # try/except that used to keep this action from ever raising, so errors such as a
        # missing "src" file now escape uncaught and bypass failed_when/changed_when
        # evaluation entirely (https://github.com/ansible/ansible/issues/87491). Restore the
        # pre-2.19 contract of always returning a result dict instead of raising.
        try:
            with mock.patch.object(action_loader, "get", _get_action):
                return super().run(tmp, task_vars)
        except AnsibleAction as e:
            return e.result
        except Exception as e:
            return {"failed": True, "msg": to_native(e)}
