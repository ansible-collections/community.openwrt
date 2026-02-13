# Copyright: (c) 2026, Ilya Bogdanov (@zeerayne)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later
import ast
import inspect
import textwrap

from ansible.plugins.action.template import ActionModule as TemplateActionModule


def patch_and_create_class(original_cls):
    source = textwrap.dedent(inspect.getsource(original_cls))
    tree = ast.parse(source)

    class AnsibleActionTransformer(ast.NodeTransformer):
        def visit_Assign(self, node):
            # Find line: copy_action = self._shared_loader_obj.action_loader.get('ansible.legacy.copy', ...)
            # Check that this is an assignment to the variable copy_action
            if (isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'copy_action'):

                # Check that this is a call to .get('ansible.legacy.copy', ...)
                if (isinstance(node.value, ast.Call) and
                        isinstance(node.value.args[0], ast.Constant) and
                        node.value.args[0].value == 'ansible.legacy.copy'):
                    # Create NEW line 1: new_task.action = 'community.openwrt.copy'
                    line1 = ast.Assign(
                        targets=[ast.Attribute(value=ast.Name(id='new_task', ctx=ast.Load()), attr='action', ctx=ast.Store())],
                        value=ast.Constant(value='community.openwrt.copy')
                    )

                    # Modify OLD line: change argument in .get()
                    node.value.args[0].value = 'community.openwrt.copy'

                    # Return list of two lines (they will replace one old line)
                    return [line1, node]

            return self.generic_visit(node)

        def visit_Call(self, node):
            # Replace super(ActionModule, self) with super()
            # This is necessary because the class has been renamed, and ActionModule references the ORIGINAL class from globals
            if (isinstance(node.func, ast.Name) and node.func.id == 'super' and
                    len(node.args) == 2 and
                    isinstance(node.args[0], ast.Name) and node.args[0].id == 'ActionModule' and
                    isinstance(node.args[1], ast.Name) and node.args[1].id == 'self'):
                return ast.Call(
                    func=ast.Name(id='super', ctx=ast.Load()),
                    args=[],
                    keywords=[]
                )
            return self.generic_visit(node)

    # Apply transformation
    new_tree = AnsibleActionTransformer().visit(tree)
    new_tree.body[0].name = "PatchedTemplateActionModule"  # Rename class to avoid conflicts

    # Fix line numbers (required for compilation)
    ast.fix_missing_locations(new_tree)

    # Compile
    code = compile(new_tree, filename="<ast_patch>", mode="exec")
    namespace = {}
    # Pass globals of the original module so the class can see imports (ansible, etc.)
    exec(code, inspect.getmodule(original_cls).__dict__, namespace)

    return namespace["PatchedTemplateActionModule"]


class ActionModule(patch_and_create_class(TemplateActionModule)):
    pass
