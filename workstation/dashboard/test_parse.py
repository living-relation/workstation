import tempfile
import unittest
from pathlib import Path

import collect


SAMPLE = """
# Tracker

## Needs a decision

| ID | Topic | Question |
|---|---|---|
| N1 | Drawings | Approve the set |

## Open

| # | Item | Status |
|---|---|---|
| 2 | Pick the connector | Open |
| 3 | Waiting on a measurement | Blocked |
| 4 | Gauge note | Closed |

## Warnings

- Shield label is still generic

## History

- Landed the pinout
- [x] Wrote the base map

## Parked

- Old idea
"""


class PictureFilter(unittest.TestCase):
    def test_icon_is_rejected(self) -> None:
        self.assertFalse(collect.usable_picture(32, 32, 400, "favicon.png"))
        self.assertFalse(collect.usable_picture(128, 128, 3000, "sprite.png"))

    def test_document_is_kept(self) -> None:
        self.assertTrue(collect.usable_picture(1400, 900, 80_000, "harness.png"))
        self.assertTrue(collect.usable_picture(220, 900, 40_000, "drawing.png"))

    def test_png_header(self) -> None:
        raw = b"\x89PNG\r\n\x1a\n" + b"\x00" * 8 + (1400).to_bytes(4, "big") + (900).to_bytes(4, "big")
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as handle:
            handle.write(raw)
            name = handle.name
        try:
            self.assertEqual(collect.image_size(Path(name)), (1400, 900))
        finally:
            Path(name).unlink(missing_ok=True)


class ParseTracker(unittest.TestCase):
    def test_rows(self) -> None:
        parsed = collect.parse_tracker(SAMPLE)
        self.assertTrue(any("Approve the set" in item for item in parsed["prompts"]))
        self.assertTrue(any(item.startswith("2:") for item in parsed["tasks"]))
        self.assertTrue(any("measurement" in item for item in parsed["blockers"]))
        self.assertTrue(any("Gauge note" in item for item in parsed["completed"]))
        self.assertTrue(any("Landed the pinout" in item for item in parsed["completed"]))
        self.assertTrue(any("Shield" in item for item in parsed["warnings"]))
        self.assertFalse(any("Old idea" in item for item in parsed["tasks"]))

    def test_path_jail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / "demo"
            project.mkdir()
            ok = project / "shot.png"
            ok.write_bytes(b"png")
            secret = project / ".env"
            secret.write_text("nope", encoding="utf-8")
            outside = root / "other.png"
            outside.write_bytes(b"png")
            self.assertTrue(collect.is_allowed_file(project, ok))
            self.assertFalse(collect.is_allowed_file(project, secret))
            self.assertFalse(collect.is_allowed_file(project, outside))


if __name__ == "__main__":
    unittest.main()
