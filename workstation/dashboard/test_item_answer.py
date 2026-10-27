"""Feature 2: answer a Waiting row -> start Claude (the Feature 3 launcher) with the answer as its task.
The dashboard never writes the answer into the repo itself."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import actions  # noqa: E402
from test_item_hand_off import Sandbox  # noqa: E402


class Answer(Sandbox):
    def test_answer_starts_session_with_the_answer_as_task(self) -> None:
        result = actions.launch("answer", "demo", self.prompt_fp, "  No,\n borrow one ", today="2026-10-27")
        (args, kw), = self.popen
        prompt = args[-1]
        self.assertEqual(args[args.index("--name") + 1], "dashboard-answer-demo")
        self.assertIn("Dan answered this open item on 2026-10-27", prompt)
        self.assertIn("Ok to order the crimp tool?", prompt)
        self.assertIn("> No, borrow one", prompt)  # cleaned to one line, words kept
        self.assertIn("where this repo's rules say answers and decisions go", prompt)
        self.assertIn(f"Dashboard item: {self.prompt_fp}", prompt)
        self.assertEqual(actions.load_sessions()[f"demo|{self.prompt_fp}"]["sessionId"], result["sessionId"])

    def test_answer_does_not_edit_the_tracker(self) -> None:
        before = (self.project / "docs" / "OPEN-ITEMS.md").read_text(encoding="utf-8")
        actions.launch("answer", "demo", self.prompt_fp, "Yes")
        self.assertEqual((self.project / "docs" / "OPEN-ITEMS.md").read_text(encoding="utf-8"), before)

    def test_empty_answer_refused(self) -> None:
        with self.assertRaises(actions.ActionError):
            actions.launch("answer", "demo", self.prompt_fp, "   ")
        self.assertEqual(self.popen, [])

    def test_answer_capped(self) -> None:
        actions.launch("answer", "demo", self.prompt_fp, "x" * 2000)
        self.assertIn("> " + "x" * actions.TEXT_LIMIT + "\n", self.popen[0][0][-1])
        self.assertNotIn("x" * (actions.TEXT_LIMIT + 1), self.popen[0][0][-1])


if __name__ == "__main__":
    unittest.main()
