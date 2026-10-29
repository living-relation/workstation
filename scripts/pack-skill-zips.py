#!/usr/bin/env python3
"""Rebuild one Claude-importable zip per skill folder that contains SKILL.md.

Output: skills/<name>.zip beside the skill folders (not inside them). Each zip
holds a single top folder named after the skill, with SKILL.md at that folder's
root plus any supporting files.

Zips are deterministic (sorted entries, fixed timestamps, Unix create_system,
ZIP_STORED) so an unchanged skill produces byte-identical output. Only
git-tracked files are packed; dot paths are skipped. Skill files are never edited.

The GitHub Action owns the committed zips (it writes them onto PRs). This script
is the packer that Action runs; a local run is optional.

Validation (Claude import limits) is reported as WARN lines; packing still
happens. A description over 200 characters prints a GitHub ::warning annotation
and never fails the run. Exit 1 with --strict on real limit violations, and
always if SKILL.md is not git-tracked.
"""
from __future__ import annotations

import argparse
import io
import re
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

try:
    import yaml
except ImportError as e:  # pragma: no cover
    raise SystemExit("PyYAML is required (pip install pyyaml)") from e

ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
# Claude: lowercase letters, numbers, hyphens as separators, max 64 chars.
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TAG_RE = re.compile(r"<[^>]+>")
RESERVED = ("claude", "anthropic")
DESC_MAX = 1024
DESC_SOFT = 200
NAME_MAX = 64
EXCLUDE_FILE = "EXCLUDE.txt"
APP_MARKER = "harness-design-app"
MARKER_RE = re.compile(r"(?m)^source:\s*['\"]?harness-design-app['\"]?\s*$")
# Regular file, mode 0644 (includes Unix file-type bits).
FILE_ATTR = (stat.S_IFREG | 0o644) << 16


class Report:
    def __init__(self) -> None:
        self.packed: list[str] = []
        self.unchanged: list[str] = []
        self.removed: list[str] = []
        self.warnings: list[str] = []
        self.soft_warnings: list[str] = []
        self.errors: list[str] = []
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


def load_excluded(skills_dir: Path) -> set[str]:
    """Names in skills/EXCLUDE.txt (one per line, # comments). Claude-app-owned skills."""
    f = skills_dir / EXCLUDE_FILE
    if not f.is_file():
        return set()
    out = set()
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.add(line)
    return out


def is_app_marked(skill_dir: Path) -> bool:
    """True if SKILL.md frontmatter has `source: harness-design-app`."""
    p = skill_dir / "SKILL.md"
    if not p.is_file():
        return False
    text = p.read_text(encoding="utf-8", errors="replace")
    if not text.startswith("---"):
        return False
    rest = text[3:].lstrip("\r\n")
    m = re.search(r"(?m)^---\s*$", rest)
    head = rest[: m.start()] if m else ""
    return bool(MARKER_RE.search(head))


def is_excluded(skill_dir: Path, excluded: set[str]) -> bool:
    return skill_dir.name in excluded or is_app_marked(skill_dir)


def git_repo_root(path: Path) -> Path | None:
    r = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return None
    return Path(r.stdout.strip())


def parse_skill_md(path: Path) -> dict[str, str]:
    """Parse SKILL.md YAML frontmatter with yaml.safe_load. Raises ValueError on bad YAML."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        raise ValueError(f"{path}: missing YAML frontmatter")
    rest = text[3:].lstrip("\r\n")
    m = re.search(r"(?m)^---\s*$", rest)
    if not m:
        raise ValueError(f"{path}: unclosed YAML frontmatter")
    try:
        data = yaml.safe_load(rest[: m.start()])
    except yaml.YAMLError as e:
        raise ValueError(f"{path}: invalid YAML frontmatter: {e}") from e
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: frontmatter must be a mapping")
    out: dict[str, str] = {}
    for k, v in data.items():
        if v is None:
            out[str(k)] = ""
        elif isinstance(v, str):
            out[str(k)] = v
        else:
            out[str(k)] = str(v)
    return out


def validate_skill(skill_dir: Path, meta: dict[str, str]) -> tuple[list[str], list[str]]:
    """Return (limit_warnings, soft_warnings). Soft warnings never fail the run."""
    warnings: list[str] = []
    soft: list[str] = []
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
                f"{folder}: name {name!r} must be lowercase letters, numbers and hyphens "
                f"(no leading/trailing hyphen), max {NAME_MAX} chars"
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
        elif len(desc) > DESC_SOFT:
            soft.append(
                f"{folder}: description is {len(desc)} chars (soft limit {DESC_SOFT})"
            )
        tags = TAG_RE.findall(desc)
        if tags:
            shown = ", ".join(tags[:5])
            warnings.append(f"{folder}: description contains angle-bracket tag(s): {shown}")
    return warnings, soft


def _is_dot_path(rel: str) -> bool:
    return any(part.startswith(".") for part in rel.split("/"))


def iter_skill_files(skill_dir: Path) -> list[tuple[str, Path]]:
    """Git-tracked files under skill_dir, skipping dot paths. Empty if not a git repo."""
    root = git_repo_root(skill_dir)
    if root is None:
        return []
    skill_abs = skill_dir.resolve()
    root_abs = root.resolve()
    try:
        prefix = skill_abs.relative_to(root_abs).as_posix()
    except ValueError:
        return []
    r = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--", prefix],
        capture_output=True,
        check=False,
    )
    if r.returncode != 0:
        return []
    out: list[tuple[str, Path]] = []
    for p in r.stdout.decode().split("\0"):
        if not p:
            continue
        full = (root_abs / p).resolve()
        try:
            rel = full.relative_to(skill_abs).as_posix()
        except ValueError:
            continue
        if rel in (".", ""):
            continue
        if _is_dot_path(rel):
            continue
        lower = rel.lower()
        if lower.endswith(".pyc") or lower.endswith(".zip"):
            continue
        if not full.is_file() or full.is_symlink():
            continue
        out.append((rel, full))
    out.sort(key=lambda t: t[0])
    return out


def build_zip_bytes(skill_dir: Path) -> bytes:
    folder = skill_dir.name
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_STORED) as zf:
        for rel, full in iter_skill_files(skill_dir):
            info = zipfile.ZipInfo(f"{folder}/{rel}")
            info.date_time = ZIP_EPOCH
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = FILE_ATTR
            info.create_version = 20
            info.extract_version = 20
            zf.writestr(info, full.read_bytes(), compress_type=zipfile.ZIP_STORED)
    return buf.getvalue()


def pack_all(skills_dir: Path) -> Report:
    report = Report()
    skills_dir = skills_dir.resolve()
    excluded = load_excluded(skills_dir)
    dirs = []
    skipped: set[str] = set(excluded)
    for d in skill_dirs(skills_dir):
        if is_excluded(d, excluded):
            skipped.add(d.name)
            report.lines.append(f"skip excluded {d.name} (harness app skill)")
            continue
        dirs.append(d)
    wanted = {d.name + ".zip" for d in dirs}

    for skill in dirs:
        if not any(rel == "SKILL.md" for rel, _ in iter_skill_files(skill)):
            report.errors.append(f"{skill.name}: SKILL.md is not git-tracked")
            continue
        try:
            meta = parse_skill_md(skill / "SKILL.md")
        except ValueError as e:
            report.warnings.append(f"{skill.name}: {e}")
            meta = {}
        hard, soft = validate_skill(skill, meta)
        report.warnings.extend(hard)
        report.soft_warnings.extend(soft)
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
            if child.name[: -len(".zip")] in skipped:
                # Excluded skills: never pack, never touch.
                continue
            child.unlink()
            report.removed.append(child.name)
            report.lines.append(f"removed orphan {child.name}")
    return report


def emit_soft_warnings(report: Report, skills_dir: Path) -> None:
    """GitHub Actions ::warning annotations; never fail the run."""
    for w in report.soft_warnings:
        folder = w.split(":", 1)[0]
        rel = (skills_dir / folder / "SKILL.md").as_posix()
        print(f"::warning file={rel}::{w}", file=sys.stderr)
        print(f"WARN: {w}", file=sys.stderr)


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
        help="Exit 1 when a skill fails Claude import limits (zips are still written; "
        "description-over-200 never fails)",
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
    emit_soft_warnings(report, skills_dir)
    if report.errors:
        print(f"\n{len(report.errors)} error(s):", file=sys.stderr)
        for e in report.errors:
            print(f"ERROR: {e}", file=sys.stderr)
    if report.warnings:
        print(
            f"\n{len(report.warnings)} validation warning(s) (skill content not modified):",
            file=sys.stderr,
        )
        for w in report.warnings:
            print(f"WARN: {w}", file=sys.stderr)
    elif not report.packed and not report.removed and not report.errors:
        print("no skill folders with SKILL.md found")
    if report.errors:
        return 1
    if args.strict and report.warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
