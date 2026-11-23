"""Tests for skills/git-checker/hooks/registry-check.py STALE-OUTPUT (content compare, slow fallback).

Run: python3 scripts/test_registry_check.py   (stdlib only; makes throwaway git repos in a temp folder)
"""
import os, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "skills" / "git-checker" / "hooks" / "registry-check.py"
COPY = ROOT / ".github" / "registry-check.py"
PY = sys.executable.replace("\\", "/")
if " " in PY: PY = "python3" if os.name != "nt" else "python"   # run_cmd is an unquoted YAML scalar
GEN = "import pathlib\npathlib.Path('out.txt').write_text(pathlib.Path('in.txt').read_text().upper(), newline='\\n')\n"


class StaleOutputTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="test-registry-check-"))
        self.repo = self.tmp / "repo"; self.repo.mkdir()
        self.t = 1_700_000_000
        self.git("init", "-q"); self.git("config", "user.email", "t@example.com"); self.git("config", "user.name", "t")
        self.git("config", "core.autocrlf", "false")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *a):
        return subprocess.run(["git", *a], cwd=self.repo, capture_output=True, text=True, check=True).stdout

    def write(self, name, text, crlf=False):
        p = self.repo / name; p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(text.replace("\n", "\r\n" if crlf else "\n").encode())

    def commit(self, *paths, msg="c"):
        self.t += 3600   # every commit an hour later, so commit dates order the files
        self.git("add", *paths)
        env = dict(os.environ, GIT_AUTHOR_DATE=f"{self.t} +0000", GIT_COMMITTER_DATE=f"{self.t} +0000")
        subprocess.run(["git", "commit", "-q", "-m", msg], cwd=self.repo, env=env, check=True, capture_output=True)

    def registry(self, run_cmd=None, slow=False):
        run_cmd = run_cmd or f"{PY} gen.py"
        self.write("automation.yml", "automations:\n  - id: gen\n    script: gen.py\n    trigger: manual\n"
                   "    reads: [in.txt]\n    writes: [out.txt]\n    committed: yes\n    auto_commit: false\n"
                   f"    enabled: true\n    run_cmd: {run_cmd}\n" + ("    slow: true\n" if slow else ""))

    def check(self):
        r = subprocess.run([sys.executable, str(SCRIPT)], cwd=self.repo, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return [l for l in r.stdout.splitlines() if "STALE-OUTPUT" in l]

    def base(self, **kw):
        self.registry(**kw); self.write("gen.py", GEN); self.write("in.txt", "hello\n"); self.write("out.txt", "HELLO\n")

    def test_same_commit_not_stale(self):
        self.base(); self.commit(".")
        self.assertEqual(self.check(), [])

    def test_input_newer_by_date_identical_output_not_stale(self):
        self.base(); self.commit("automation.yml", "gen.py", "out.txt")
        self.commit("in.txt")   # input committed later, but a fresh run gives the same out.txt
        self.write("gen.py", GEN + "# comment only\n"); self.commit("gen.py")   # script newer too
        self.assertEqual(self.check(), [])

    def test_real_drift_is_stale(self):
        self.base(); self.commit(".")
        self.write("in.txt", "changed\n"); self.commit("in.txt")
        flags = self.check()
        self.assertEqual(len(flags), 1, flags)
        self.assertIn("a fresh run changes 1 declared output(s): out.txt", flags[0])

    def test_real_tree_untouched(self):
        self.base(); self.commit(".")
        self.write("in.txt", "changed\n"); self.commit("in.txt")
        self.check()
        self.assertEqual((self.repo / "out.txt").read_text(), "HELLO\n")
        self.assertEqual(self.git("status", "--porcelain", "--untracked-files=all"), "")

    def test_crlf_only_difference_not_stale(self):
        self.base(); self.write("out.txt", "HELLO\n", crlf=True); self.commit(".")
        self.write("in.txt", "hello\n", crlf=False); self.write("gen.py", GEN + "\n"); self.commit("gen.py")
        self.assertEqual(self.check(), [])

    def test_slow_falls_back_to_commit_date_and_is_not_run(self):
        marker = self.tmp / "ran"
        self.base(run_cmd=f"{PY} mark.py", slow=True)
        self.write("mark.py", f"open({marker.as_posix()!r}, 'w')\n")
        self.commit("automation.yml", "gen.py", "mark.py", "out.txt"); self.commit("in.txt")
        flags = self.check()
        self.assertEqual(len(flags), 1, flags)
        self.assertIn("commit-date check: marked slow: true", flags[0])
        self.assertFalse(marker.exists(), "a slow generator must not be re-run")

    def test_slow_same_commit_not_stale(self):
        self.base(slow=True); self.commit(".")
        self.assertEqual(self.check(), [])

    def test_failed_rerun_falls_back_to_commit_date(self):
        self.base(run_cmd=f"{PY} fail.py"); self.write("fail.py", "raise SystemExit(3)\n")
        self.commit("automation.yml", "gen.py", "fail.py", "out.txt"); self.commit("in.txt")
        flags = self.check()
        self.assertEqual(len(flags), 1, flags)
        self.assertIn("commit-date check: re-run exited 3", flags[0])

    def test_placeholder_falls_back_to_commit_date(self):
        self.base(run_cmd=f"{PY} gen.py <input JSON>")
        self.commit("automation.yml", "gen.py", "out.txt"); self.commit("in.txt")
        flags = self.check()
        self.assertEqual(len(flags), 1, flags)
        self.assertIn("run_cmd has a <placeholder>", flags[0])

    def test_optional_part_falls_back_to_commit_date(self):
        self.base(run_cmd=f"{PY} gen.py [--offline]")
        self.commit("automation.yml", "gen.py", "out.txt"); self.commit("in.txt")
        flags = self.check()
        self.assertEqual(len(flags), 1, flags)
        self.assertIn("[optional] part", flags[0])


class CopyParityTests(unittest.TestCase):
    def test_github_copy_byte_identical(self):
        self.assertEqual(COPY.read_bytes(), SCRIPT.read_bytes(), ".github/registry-check.py must be a byte-identical copy")


if __name__ == "__main__":
    unittest.main(verbosity=2)
