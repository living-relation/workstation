#!/usr/bin/env python3
"""Git Bash lookup ignores the WSL launcher and prefers Git for Windows."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from find_git_bash import (  # noqa: E402
    NOT_FOUND,
    find_git_bash,
    find_windows_git_bash,
    is_rejected_windows_bash,
)


class RejectedWindowsBash(unittest.TestCase):
    def test_rejects_wsl_and_store_launchers(self):
        rejected = [
            Path(r"C:\Windows\System32\bash.exe"),
            Path(r"C:\Windows\SysWOW64\bash.exe"),
            Path(r"C:\Windows\system32\bash.exe"),
            Path(r"C:\Users\example\AppData\Local\Microsoft\WindowsApps\bash.exe"),
            Path(r"C:\Users\example\AppData\Local\Microsoft\WindowsApps\MicrosoftCorporationII.WindowsSubsystemForLinux_8wekyb3d8bbwe\bash.exe"),
        ]
        for path in rejected:
            with self.subTest(path=str(path)):
                self.assertTrue(is_rejected_windows_bash(path), path)

    def test_accepts_git_bash_locations(self):
        accepted = [
            Path(r"C:\Program Files\Git\bin\bash.exe"),
            Path(r"C:\Program Files\Git\usr\bin\bash.exe"),
            Path(r"C:\Program Files (x86)\Git\bin\bash.exe"),
            Path(r"C:\Users\example\scoop\apps\git\current\bin\bash.exe"),
        ]
        for path in accepted:
            with self.subTest(path=str(path)):
                self.assertFalse(is_rejected_windows_bash(path), path)


class FindGitBashWindowsMocked(unittest.TestCase):
    """Windows lookup tests that run on Linux and Windows.

    Call find_windows_git_bash() directly so Path() stays native (patching
    os.name to nt on Linux cannot instantiate WindowsPath).
    """

    def test_prefers_git_exec_path_over_wsl_on_path(self):
        with tempfile.TemporaryDirectory() as td:
            git_root = Path(td) / "Git"
            bash = git_root / "bin" / "bash.exe"
            bash.parent.mkdir(parents=True)
            bash.write_bytes(b"")
            exec_path = git_root / "mingw64" / "libexec" / "git-core"
            exec_path.mkdir(parents=True)
            git_exe = str(git_root / "cmd" / "git.exe")

            def which(name):
                if name == "git":
                    return git_exe
                if name == "bash":
                    return r"C:\Windows\System32\bash.exe"
                return None

            def fake_run(args, **kwargs):
                if list(args)[:2] == [git_exe, "--exec-path"]:
                    return subprocess.CompletedProcess(
                        args, 0, stdout=str(exec_path) + "\n", stderr=""
                    )
                raise AssertionError(args)

            with mock.patch(
                "find_git_bash.shutil.which", side_effect=which
            ), mock.patch(
                "find_git_bash.subprocess.run", side_effect=fake_run
            ), mock.patch(
                "find_git_bash._known_windows_git_bash", return_value=[]
            ):
                found = find_windows_git_bash()
            self.assertEqual(found, bash)

    def test_uses_known_install_dir_when_git_is_missing(self):
        with tempfile.TemporaryDirectory() as td:
            bash = Path(td) / "Program Files" / "Git" / "bin" / "bash.exe"
            bash.parent.mkdir(parents=True)
            bash.write_bytes(b"")

            def which(name):
                if name == "bash":
                    return r"C:\Windows\System32\bash.exe"
                return None

            with mock.patch(
                "find_git_bash.shutil.which", side_effect=which
            ), mock.patch(
                "find_git_bash._known_windows_git_bash", return_value=[bash]
            ):
                found = find_windows_git_bash()
            self.assertEqual(found, bash)

    def test_returns_none_when_only_wsl_launcher_is_found(self):
        wsl = Path(r"C:\Windows\System32\bash.exe")

        def which(name):
            if name == "bash":
                return str(wsl)
            return None

        with mock.patch(
            "find_git_bash.shutil.which", side_effect=which
        ), mock.patch(
            "find_git_bash._known_windows_git_bash", return_value=[wsl]
        ):
            found = find_windows_git_bash()
        self.assertIsNone(found)


class FindGitBashLive(unittest.TestCase):
    def test_posix_uses_path_bash(self):
        if os.name == "nt":
            self.skipTest("posix lookup")
        found = find_git_bash()
        self.assertIsNotNone(found)
        self.assertTrue(found.is_file())

    def test_windows_ignores_wsl_bash_on_path(self):
        if os.name != "nt":
            self.skipTest("windows lookup")
        wsl = r"C:\Windows\System32\bash.exe"
        real_which = __import__("shutil").which

        def which(name):
            if name == "bash":
                return wsl
            return real_which(name)

        with mock.patch("find_git_bash.shutil.which", side_effect=which):
            found = find_git_bash()
        self.assertIsNotNone(found, NOT_FOUND)
        self.assertFalse(is_rejected_windows_bash(found), found)
        self.assertTrue(found.is_file())
        self.assertEqual(found.name.lower(), "bash.exe")

    def test_windows_result_is_not_the_wsl_launcher(self):
        if os.name != "nt":
            self.skipTest("windows lookup")
        found = find_git_bash()
        self.assertIsNotNone(found, NOT_FOUND)
        self.assertFalse(is_rejected_windows_bash(found), f"looked up a rejected bash: {found}")
        self.assertTrue(found.is_file())


if __name__ == "__main__":
    unittest.main()
