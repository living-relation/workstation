import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import collect

LONG = "Measure the harness run from the firewall pass-through to the ECU plug " * 12  # ~860 chars

TRACKER = f"""# Open items

## Blockers

- {LONG.strip()}

## Open

| ID | Item | Status |
|---|---|---|
| T7 | Pick the connector | Open |

## Needs a decision

| ID | Topic | Question |
|---|---|---|
| N1 | Drawings | {"Approve the drawing set as it stands today " * 10} |
"""


class FullTextAndLine(unittest.TestCase):
    def setUp(self) -> None:
        self.parsed = collect.parse_tracker(TRACKER)

    def test_long_bullet_keeps_full_text(self) -> None:
        item = self.parsed["blockers"][0]
        self.assertLessEqual(len(item["text"]), 300)
        self.assertTrue(item["text"].endswith("…"))
        self.assertEqual(item["textFull"], collect._clip(LONG, collect.FULL_LIMIT))
        self.assertGreater(len(item["textFull"]), 800)

    def test_line_numbers_point_at_the_row(self) -> None:
        lines = TRACKER.split("\n")
        blocker = self.parsed["blockers"][0]
        task = self.parsed["tasks"][0]
        prompt = self.parsed["prompts"][0]
        self.assertTrue(lines[blocker["line"] - 1].startswith("- Measure"))
        self.assertIn("| T7 |", lines[task["line"] - 1])
        self.assertIn("| N1 |", lines[prompt["line"] - 1])

    def test_table_id_kept(self) -> None:
        self.assertEqual(self.parsed["tasks"][0]["id"], "T7")
        self.assertEqual(self.parsed["prompts"][0]["id"], "N1")
        self.assertNotIn("id", self.parsed["blockers"][0])

    def test_question_preview_clipped_full_kept(self) -> None:
        prompt = self.parsed["prompts"][0]
        self.assertIn("N1: Drawings — Approve", prompt["text"])
        self.assertLess(len(prompt["text"]), len(prompt["textFull"]))
        self.assertTrue(prompt["textFull"].rstrip().endswith("today"))

    def test_full_text_capped(self) -> None:
        parsed = collect.parse_tracker("## Blockers\n\n- " + "x" * 20_000 + "\n")
        self.assertEqual(len(parsed["blockers"][0]["textFull"]), collect.FULL_LIMIT)


class GithubLink(unittest.TestCase):
    def test_anchor_on_clean_main(self) -> None:
        url = collect.tracker_github_url("owner/repo", "docs/OPEN-ITEMS.md", 42, "main", 0)
        self.assertEqual(url, "https://github.com/owner/repo/blob/main/docs/OPEN-ITEMS.md#L42")

    def test_no_anchor_off_main_or_ahead(self) -> None:
        plain = "https://github.com/owner/repo/blob/main/OPEN-ITEMS.md"
        self.assertEqual(collect.tracker_github_url("owner/repo", "OPEN-ITEMS.md", 5, "feat/x", 0), plain)
        self.assertEqual(collect.tracker_github_url("owner/repo", "OPEN-ITEMS.md", 5, "main", 2), plain)

    def test_no_link_without_slug_or_tracker(self) -> None:
        self.assertIsNone(collect.tracker_github_url(None, "OPEN-ITEMS.md", 5, "main", 0))
        self.assertIsNone(collect.tracker_github_url("owner/repo", "", 5, "main", 0))


def _git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


class SnapshotItems(unittest.TestCase):
    def test_project_items_carry_full_text_and_url(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "demo"
            (repo / "docs").mkdir(parents=True)
            (repo / "docs" / "OPEN-ITEMS.md").write_text(TRACKER, encoding="utf-8")
            _git(repo, "init", "-q", "-b", "main")
            _git(repo, "remote", "add", "origin", "https://github.com/owner/demo.git")
            with mock.patch.object(collect, "_gh_json", return_value=[]):
                project = collect.collect_project(repo, lite=True)
        blocker = project["blockers"][0]
        self.assertEqual(project["tracker"], "docs/OPEN-ITEMS.md")
        self.assertGreater(len(blocker["textFull"]), len(blocker["text"]))
        self.assertTrue(blocker["githubUrl"].startswith("https://github.com/owner/demo/blob/main/docs/OPEN-ITEMS.md"))
        # Nothing secret-looking rides along in the item.
        self.assertEqual(set(blocker) - {"text", "textFull", "line", "id", "githubUrl"}, set())


if __name__ == "__main__":
    unittest.main()
