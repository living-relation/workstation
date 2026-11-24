#!/usr/bin/env python3
"""Locate a real bash for this repo's tests (Git Bash on Windows).

On Windows, PATH often lists the WSL launcher
(C:\\Windows\\System32\\bash.exe or
C:\\Users\\...\\AppData\\Local\\Microsoft\\WindowsApps\\bash.exe)
ahead of Git Bash. This helper never uses those. It prefers Git Bash
from git --exec-path, the git.exe location, then known install dirs.
It does not change PATH or any machine settings.

Linux and macOS use whatever bash is on PATH.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


def is_rejected_windows_bash(path: Path) -> bool:
    """True for the WSL / Microsoft Store bash launchers, not Git Bash."""
    try:
        text = str(path.resolve()) if path.exists() else str(path)
    except OSError:
        text = str(path)
    # Split as a Windows path even when this helper runs on Linux in CI.
    lowered = text.replace("/", "\\").lower()
    parts = [p for p in lowered.split("\\") if p]
    if "windowsapps" in lowered:
        return True
    name = parts[-1] if parts else ""
    if name == "bash.exe" and ("system32" in parts or "syswow64" in parts):
        return True
    return False


def _bash_under_git_root(root: Path) -> Path | None:
    for rel in ("bin/bash.exe", "usr/bin/bash.exe"):
        cand = root / rel
        if cand.is_file() and not is_rejected_windows_bash(cand):
            return cand
    return None


def _bash_from_git_exec_path(git: str) -> Path | None:
    try:
        proc = subprocess.run(
            [git, "--exec-path"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    current = Path(proc.stdout.strip())
    # Typical: <Git>/mingw64/libexec/git-core. Walk up looking for bin/bash.exe.
    for folder in [current, *current.parents]:
        found = _bash_under_git_root(folder)
        if found:
            return found
    return None


def _bash_beside_git(git: str) -> Path | None:
    exe = Path(git)
    try:
        folder = exe.resolve().parent
    except OSError:
        folder = exe.parent
    if folder.name.lower() in {"cmd", "bin", "mingw64"}:
        folder = folder.parent
    return _bash_under_git_root(folder)


def _git_executable() -> str | None:
    found = shutil.which("git")
    if found:
        return found
    if os.name == "nt":
        where = shutil.which("where")
        if where:
            try:
                proc = subprocess.run(
                    [where, "git"],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
            except (OSError, subprocess.SubprocessError):
                proc = None
            if proc and proc.returncode == 0:
                for line in proc.stdout.splitlines():
                    line = line.strip()
                    if line and Path(line).is_file():
                        return line
    return None


def _known_windows_git_bash() -> list[Path]:
    paths = [
        Path(r"C:\Program Files\Git\bin\bash.exe"),
        Path(r"C:\Program Files\Git\usr\bin\bash.exe"),
        Path(r"C:\Program Files (x86)\Git\bin\bash.exe"),
        Path(r"C:\Program Files (x86)\Git\usr\bin\bash.exe"),
    ]
    home = Path.home()
    paths.extend(
        [
            home / r"scoop\apps\git\current\bin\bash.exe",
            home / r"scoop\apps\git\current\usr\bin\bash.exe",
        ]
    )
    local = os.environ.get("LOCALAPPDATA")
    if local:
        paths.extend(
            [
                Path(local) / r"Programs\Git\bin\bash.exe",
                Path(local) / r"Programs\Git\usr\bin\bash.exe",
            ]
        )
    return paths


def find_windows_git_bash() -> Path | None:
    """Locate Git Bash on Windows. Never returns a WindowsApps or System32 launcher."""
    git = _git_executable()
    if git:
        found = _bash_from_git_exec_path(git)
        if found:
            return found
        found = _bash_beside_git(git)
        if found:
            return found

    for cand in _known_windows_git_bash():
        if cand.is_file() and not is_rejected_windows_bash(cand):
            return cand

    # Last resort: a PATH bash that is not the WSL/Store launcher.
    found = shutil.which("bash")
    if found and not is_rejected_windows_bash(Path(found)):
        return Path(found)
    return None


def find_git_bash() -> Path | None:
    """Return the bash executable to use, or None if none is acceptable."""
    if os.name != "nt":
        found = shutil.which("bash")
        return Path(found) if found else None
    return find_windows_git_bash()


NOT_FOUND = (
    "Git Bash was not found. On Windows these tests need Git for Windows "
    r"(for example C:\Program Files\Git\bin\bash.exe). "
    r"The WSL launcher at WindowsApps or System32\bash.exe is ignored. "
    "Install Git for Windows. This helper does not change PATH or machine settings."
)


def main() -> int:
    found = find_git_bash()
    if found:
        print(found)
        return 0
    print(NOT_FOUND, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
