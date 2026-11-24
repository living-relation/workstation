#!/usr/bin/env python3
"""Run this repo's Python and PowerShell test suites (living-relation/workstation only).

Do not copy this runner or .github/workflows/repo-tests.yml into other repos,
state-init, git-checker templates, or the plugin install path used by repos
that only consume workstation.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def find_pwsh() -> str | None:
    return shutil.which("pwsh") or shutil.which("powershell")


def iter_powershell_tests() -> list[Path]:
    tests: list[Path] = []
    for path in ROOT.rglob("*.ps1"):
        if "archives" in path.parts:
            continue
        name = path.name.lower()
        if name.startswith("test-") or name.startswith("test_"):
            tests.append(path)
    return sorted(tests)


def run(cmd: list[str], env: dict[str, str] | None = None) -> int:
    print("+", " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, cwd=ROOT, env=env)
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python-only", action="store_true")
    parser.add_argument("--powershell-only", action="store_true")
    args = parser.parse_args()

    env = os.environ.copy()
    env.setdefault("CI", "true")
    side = env.get("WORKSTATION_PASTE_SIDE_EFFECT_LOG")
    if not side:
        side = str(Path(env.get("RUNNER_TEMP") or env.get("TMPDIR") or env.get("TEMP") or "/tmp") / "paste-side-effects.log")
        env["WORKSTATION_PASTE_SIDE_EFFECT_LOG"] = side
    side_path = Path(side)
    if side_path.exists():
        side_path.unlink()

    failed: list[str] = []

    if not args.powershell_only:
        py = sys.executable
        code = run([py, "-m", "pytest", "-q", "scripts"], env=env)
        if code != 0:
            failed.append("pytest scripts")

    if not args.python_only:
        pwsh = find_pwsh()
        if not pwsh:
            print("FAIL: pwsh or powershell is required for the PowerShell tests", flush=True)
            failed.append("powershell missing")
        else:
            tests = iter_powershell_tests()
            if not tests:
                print("FAIL: no PowerShell tests found", flush=True)
                failed.append("no powershell tests")
            for test in tests:
                rel = test.relative_to(ROOT).as_posix()
                code = run([pwsh, "-NoProfile", "-File", str(test)], env=env)
                if code != 0:
                    failed.append(rel)

    if side_path.is_file() and side_path.stat().st_size > 0:
        print("FAIL: paste helper invoked a real editor or clipboard:", flush=True)
        print(side_path.read_text(encoding="utf-8"), end="", flush=True)
        failed.append("real editor/clipboard side effects")
    else:
        print("OK: no real editor or clipboard side effects", flush=True)

    if failed:
        print("FAILED:", "; ".join(failed), flush=True)
        return 1
    print("ALL REPO TESTS PASSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
