# Copyright (c) 2026, Alexei Znamensky (@russoz)
# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

from unittest.mock import MagicMock

from ansible_collections.community.openwrt.plugins.action.copy import ActionModule


def _make_action(src=None, dest="/tmp/dest.txt", content=None):
    """Helper to build a fully wired action with common mocks."""
    obj = object.__new__(ActionModule)
    obj._task = MagicMock()
    obj._task.action = "community.openwrt.copy"
    obj._task.async_val = 0
    obj._task.args = {"dest": dest}
    if src is not None:
        obj._task.args["src"] = src
    if content is not None:
        obj._task.args["content"] = content
    obj._connection = MagicMock()
    obj._connection._shell.join_path = MagicMock(return_value="/tmp/remote/source")
    obj._templar = MagicMock()
    obj._loader = MagicMock()
    obj._loader.get_real_file = MagicMock(side_effect=lambda path, decrypt=True: path)
    obj._loader.cleanup_tmp_file = MagicMock()
    obj._play_context = MagicMock()
    obj._shared_loader_obj = MagicMock()
    obj._make_tmp_path = MagicMock(return_value="/tmp/remote")
    obj._transfer_file = MagicMock()
    obj._fixup_perms2 = MagicMock()
    obj._find_needle = MagicMock(return_value="/controller/files/secret.pem")
    obj._execute_module = MagicMock(return_value={"changed": False, "failed": False})
    return obj


def test_get_real_file_called_for_src():
    """get_real_file must be called so vault content is decrypted before transfer."""
    action = _make_action(src="secret.pem")
    action.run(task_vars={})
    action._loader.get_real_file.assert_called_once_with("/controller/files/secret.pem", decrypt=True)


def test_transfer_uses_decrypted_path():
    """The decrypted temp path must be used for transfer, not the original vault path."""
    action = _make_action(src="secret.pem")
    decrypted_path = "/tmp/ansible-decrypted-XXXX"
    action._loader.get_real_file = MagicMock(return_value=decrypted_path)

    action.run(task_vars={})

    action._transfer_file.assert_any_call(decrypted_path, "/tmp/remote/source")


def test_cleanup_called_when_decrypted_path_differs():
    """Temp file created by vault decryption must be cleaned up after transfer."""
    action = _make_action(src="secret.pem")
    original_path = "/controller/files/secret.pem"
    decrypted_path = "/tmp/ansible-decrypted-XXXX"
    action._find_needle = MagicMock(return_value=original_path)
    action._loader.get_real_file = MagicMock(return_value=decrypted_path)

    action.run(task_vars={})

    action._loader.cleanup_tmp_file.assert_called_once_with(decrypted_path)


def test_cleanup_called_unconditionally():
    """cleanup_tmp_file is always called; the loader decides whether the path is a temp file."""
    action = _make_action(src="plain.txt")
    same_path = "/controller/files/plain.txt"
    action._find_needle = MagicMock(return_value=same_path)
    action._loader.get_real_file = MagicMock(return_value=same_path)

    action.run(task_vars={})

    action._loader.cleanup_tmp_file.assert_called_once_with(same_path)


def test_cleanup_called_even_when_transfer_fails():
    """Decrypted temp file must be cleaned up even if the subsequent transfer raises."""
    action = _make_action(src="secret.pem")
    original_path = "/controller/files/secret.pem"
    decrypted_path = "/tmp/ansible-decrypted-XXXX"
    action._find_needle = MagicMock(return_value=original_path)
    action._loader.get_real_file = MagicMock(return_value=decrypted_path)
    action._transfer_file = MagicMock(side_effect=Exception("SFTP error"))

    result = action.run(task_vars={})

    assert result["failed"] is True
    action._loader.cleanup_tmp_file.assert_called_once_with(decrypted_path)


def test_original_basename_uses_original_path():
    """_original_basename must reflect the original source filename, not the decrypted temp name."""
    action = _make_action(src="secret.pem")
    action._find_needle = MagicMock(return_value="/controller/files/secret.pem")
    action._loader.get_real_file = MagicMock(return_value="/tmp/ansible-decrypted-XXXX")

    action.run(task_vars={})

    assert action._task.args.get("_original_basename") == "secret.pem"


def test_get_real_file_called_for_content_tempfile():
    """get_real_file is also called for content= paths; cleanup_tmp_file handles the rest."""
    action = _make_action(content="inline text")
    action._create_content_tempfile = MagicMock(return_value="/tmp/content-tempfile")

    action.run(task_vars={})

    action._loader.get_real_file.assert_called_once_with("/tmp/content-tempfile", decrypt=True)


def test_decrypt_false_passed_to_get_real_file():
    """When decrypt=false is set, get_real_file must receive decrypt=False."""
    action = _make_action(src="secret.pem")
    action._task.args["decrypt"] = False

    action.run(task_vars={})

    action._loader.get_real_file.assert_called_once_with("/controller/files/secret.pem", decrypt=False)
