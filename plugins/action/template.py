# Copyright (c) 2026 Ilya Bogdanov
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from unittest import mock

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

        with mock.patch.object(action_loader, "get", _get_action):
            return super().run(tmp, task_vars)
