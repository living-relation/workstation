#!/usr/bin/env python3
"""Rebuild one Claude-importable zip per skill folder that contains SKILL.md.

Output: skills/<name>.zip beside the skill folders (not inside them). Each zip
holds a single top folder named after the skill, with SKILL.md at that folder's
root plus any supporting files.

Zips are deterministic (sorted entries, fixed timestamps, Unix create_system) so
an unchanged skill produces byte-identical output. Skill files are never edited.

The GitHub Action owns the committed zips (it writes them onto PRs). This script
is the packer that Action runs; a local run is optional.

Validation (Claude import limits) is reported as WARN lines; packing still
happens. Exit 1 only with --strict.
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sys
import zipfile
from pathlib import Path

ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
NAME_RE = re.compile(r"^[a-z0-9-]{1,64}$")
TAG_RE = re.compile(r"<[^>]+>")
RESERVED = ("claude", "anthropic")
SKIP_DIRS = {".git", "__pycache__", ".venv", "node_modules"}
SKIP_FILES = {".ds_store", "thumbs.db"}
DESC_MAX = 1024
NAME_MAX = 64


class Report:
    def __init__(self) -> None:
        self.packed: list[str] = []
        self.unchanged: list[str] = []
        self.removed: list[str] = []
        self.warnings: list[str] = []
        self.lines: list[str] = []


def skill_dirs(skills_dir: Path) -> list[Path]:
    """Immediate child directories that contain SKILL.md. Zip files are ignored."""
    if not skills_dir.is_dir():
        return []
    found = []
    for child in sorted(skills_dir.iterdir(), key=lambda p: p.name):
        if not child.is_dir() or child.is_symlink():
            continue
        if (child / "SKILL.md").is_file():
            found.append(child)
    return found


def _unquote(val: str) -> str:
    val = val.strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
        return val[1:-1]
    return val


def parse_frontmatter_fields(block: str) -> dict[str, str]:
    """Minimal YAML subset: `key: value` and folded/literal `key: >-` / `|` blocks."""
    data: dict[str, str] = {}
    lines = block.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if line[0] in " \t":
            i += 1
            continue
        if ":" not in line:
            i += 1
            continue
        key, _, rest = line.partition(":")
        key = key.strip()
        rest = rest.strip()
        if rest in (">", ">-", ">+", "|", "|-", "|+"):
            folded = rest.startswith(">")
            strip_final = rest.endswith("-")
            i += 1
            chunks: list[str] = []
            while i < len(lines) and (not lines[i] or lines[i][0] in " \t"):
                raw = lines[i]
                if raw.startswith("  "):
                    chunks.append(raw[2:])
                elif raw.startswith("\t"):
                    chunks.append(raw[1:])
                else:
                    chunks.append(raw)
                i += 1
            if folded:
                text = " ".join(c.strip() for c in chunks)
                text = re.sub(r" +", " ", text).strip()
            else:
                text = "\n".join(chunks)
                if strip_final:
                    text = text.rstrip("\n")
            data[key] = text
            continue
        data[key] = _unquote(rest)
        i += 1
    return data


def parse_skill_md(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return {}
    rest = text[3:].lstrip("\r\n")
    # Next --- on its own line ends the frontmatter.
    m = re.search(r"(?m)^---\s*$", rest)
    if not m:
        return {}
    return parse_frontmatter_fields(rest[: m.start()])


def validate_skill(skill_dir: Path, meta: dict[str, str]) -> list[str]:
    warnings = []
    folder = skill_dir.name
    name = (meta.get("name") or "").strip()
    desc = meta.get("description") or ""

    if not name:
        warnings.append(f"{folder}: missing frontmatter name")
    else:
        if len(name) > NAME_MAX:
            warnings.append(f"{folder}: name is {len(name)} chars (max {NAME_MAX})")
        if not NAME_RE.fullmatch(name):
            warnings.append(
                f"{folder}: name {name!r} must be lowercase letters, numbers and hyphens, max {NAME_MAX} chars"
            )
        lower = name.lower()
        for word in RESERVED:
            if word in lower:
                warnings.append(f"{folder}: name {name!r} must not contain {word!r}")
        if name != folder:
            warnings.append(f"{folder}: folder name does not match frontmatter name {name!r}")

    if not desc.strip():
        warnings.append(f"{folder}: missing frontmatter description")
    else:
        if len(desc) > DESC_MAX:
            warnings.append(f"{folder}: description is {len(desc)} chars (max {DESC_MAX})")
        tags = TAG_RE.findall(desc)
        if tags:
            shown = ", ".join(tags[:5])
            warnings.append(f"{folder}: description contains angle-bracket tag(s): {shown}")
    return warnings


def iter_skill_files(skill_dir: Path) -> list[tuple[str, Path]]:
    """(archive-relative posix path inside the skill folder, file path)."""
    out: list[tuple[str, Path]] = []
    for dirpath, dirnames, filenames in os.walk(skill_dir, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(filenames):
            if name.lower() in SKIP_FILES:
                continue
            lower = name.lower()
            if lower.endswith(".pyc") or lower.endswith(".zip"):
                continue
            full = Path(dirpath) / name
            if not full.is_file() or full.is_symlink():
                continue
            rel = full.relative_to(skill_dir).as_posix()
            out.append((rel, full))
    out.sort(key=lambda t: t[0])
    return out


def build_zip_bytes(skill_dir: Path) -> bytes:
    folder = skill_dir.name
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel, full in iter_skill_files(skill_dir):
            info = zipfile.ZipInfo(f"{folder}/{rel}")
            info.date_time = ZIP_EPOCH
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3  # Unix: same bytes on Windows and Linux
            info.external_attr = 0o644 << 16
            info.create_version = 20
            info.extract_version = 20
            zf.writestr(info, full.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return buf.getvalue()


def pack_all(skills_dir: Path) -> Report:
    report = Report()
    skills_dir = skills_dir.resolve()
    dirs = skill_dirs(skills_dir)
    wanted = {d.name + ".zip" for d in dirs}

    for skill in dirs:
        meta = parse_skill_md(skill / "SKILL.md")
        for w in validate_skill(skill, meta):
            report.warnings.append(w)
        data = build_zip_bytes(skill)
        dest = skills_dir / f"{skill.name}.zip"
        if dest.is_file() and dest.read_bytes() == data:
            report.unchanged.append(skill.name)
            report.packed.append(skill.name)
            report.lines.append(f"unchanged {skill.name}.zip")
            continue
        dest.write_bytes(data)
        report.packed.append(skill.name)
        report.lines.append(f"wrote {skill.name}.zip")

    for child in sorted(skills_dir.glob("*.zip"), key=lambda p: p.name):
        if child.name not in wanted:
            child.unlink()
            report.removed.append(child.name)
            report.lines.append(f"removed orphan {child.name}")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skills-dir",
        type=Path,
        default=None,
        help="Skills folder (default: <repo>/skills)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 when a skill fails Claude import limits (zips are still written)",
    )
    args = parser.parse_args(argv)
    repo = Path(__file__).resolve().parent.parent
    skills_dir = args.skills_dir or (repo / "skills")
    if not skills_dir.is_dir():
        print(f"error: skills dir not found: {skills_dir}", file=sys.stderr)
        return 2
    report = pack_all(skills_dir)
    for line in report.lines:
        print(line)
    if report.warnings:
        print(
            f"\n{len(report.warnings)} validation warning(s) (skill content not modified):",
            file=sys.stderr,
        )
        for w in report.warnings:
            print(f"WARN: {w}", file=sys.stderr)
    elif not report.packed and not report.removed:
        print("no skill folders with SKILL.md found")
    if args.strict and report.warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
