"""Read-only collectors for the local project dashboard.

Runtime output stays in memory. This module does not write secrets or project
snapshots into the repo.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import struct
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

PORT = int(os.environ.get("DASHBOARD_PORT") or 8791)
WORKER_HEALTH = "http://127.0.0.1:8787/readyz"
SKIP_WALK = {
    ".git",
    "node_modules",
    ".venv",
    "venv",
    "dist",
    "build",
    "__pycache__",
    ".claude",
    "worktrees",
    ".tools",
}
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
SECRET_NAME = re.compile(
    r"(^|[/\\])(\.env|credentials|secrets?|id_rsa|id_ed25519)(\.|$)",
    re.IGNORECASE,
)
SECRET_KEY = re.compile(
    r"token|secret|password|authorization|cookie|email|apikey|api_key|encryption",
    re.IGNORECASE,
)
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def state_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    path = Path(root) / "Workstation" / "dashboard"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_roots() -> dict:
    """Same projects root paths.ps1 uses, plus the shortcut link folder."""
    local = os.environ.get("LOCALAPPDATA") or ""
    cfg_path = Path(local) / "Workstation" / "workstation.json" if local else None
    projects = None
    toolkit = None
    if cfg_path and cfg_path.is_file():
        try:
            data = json.loads(cfg_path.read_text(encoding="utf-8"))
            projects = data.get("projectsRoot") or None
            toolkit = data.get("toolkit") or None
        except (OSError, json.JSONDecodeError):
            projects = None
    here = Path(__file__).resolve().parent
    toolkit_dir = here.parent
    if not projects:
        repo = toolkit_dir.parent
        if repo.parent.name.lower() == "active":
            projects = str(repo.parent.parent)
        else:
            projects = str(repo.parent)
    projects_path = Path(str(projects))
    active = projects_path / "active"
    if toolkit:
        shortcuts = Path(str(toolkit)).parent / "shortcuts"
    else:
        shortcuts = toolkit_dir.parent / "shortcuts"
    return {
        "projectsRoot": str(projects_path),
        "active": str(active),
        "shortcuts": str(shortcuts),
        "toolkit": str(toolkit or toolkit_dir),
    }


def _run(args: list[str], cwd: str | None = None, timeout: float = 12) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, "", str(exc)


def _clip(text: str, limit: int = 280) -> str:
    text = re.sub(r"\s+", " ", (text or "").strip())
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _split_row(line: str) -> list[str]:
    parts = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return parts


def _col(header: list[str], *names: str) -> int | None:
    lowered = [h.strip().lower() for h in header]
    for name in names:
        for index, cell in enumerate(lowered):
            if cell == name or name in cell:
                return index
    return None


def _cell(row: list[str], index: int | None) -> str:
    if index is None or index >= len(row):
        return ""
    return row[index].strip()


FULL_LIMIT = 4000  # cap on an item's full text so one huge row can't bloat the snapshot


def _item(text: str, line: int, limit: int, ident: str = "") -> dict:
    """One tracker row: a clipped preview, the full text, its 1-based line, and its table ID if any."""
    full = _clip(text, FULL_LIMIT)
    item = {"text": _clip(full, limit), "textFull": full, "line": line}
    if ident:
        item["id"] = ident
    return item


def parse_tracker(text: str) -> dict:
    """Pull tasks, blockers, warnings, prompts, and completed rows from a tracker.

    Each item is a dict: text (preview), textFull, line (1-based in the file), id (table rows only).
    """
    tasks: list[dict] = []
    blockers: list[dict] = []
    completed: list[dict] = []
    warnings: list[dict] = []
    prompts: list[dict] = []
    section = "body"
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    index = 0
    while index < len(lines):
        raw = lines[index]
        heading = re.match(r"^\s{0,3}(#{1,6})\s+(.*?)\s*$", raw)
        if heading:
            title = heading.group(2).strip().lower()
            if re.search(r"histor|completed|landed|what landed", title):
                section = "done"
            elif re.search(r"parked|out of scope", title):
                section = "parked"
            elif "warn" in title:
                section = "warn"
            elif "block" in title:
                section = "block"
            elif re.search(r"need|permission|approval|decision", title):
                section = "prompt"
            else:
                section = "body"
            index += 1
            continue
        if (
            raw.strip().startswith("|")
            and index + 1 < len(lines)
            and re.match(r"^\s*\|?\s*:?-{3,}", lines[index + 1])
        ):
            header = _split_row(raw)
            index += 2
            rows: list[tuple[int, list[str]]] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append((index + 1, _split_row(lines[index])))
                index += 1
            _consume_table(header, rows, section, tasks, blockers, completed, warnings, prompts)
            continue
        line_no = index + 1
        box = re.match(r"^\s*[-*]\s+\[([ xX])\]\s+(.*)$", raw)
        if box:
            item = _item(box.group(2), line_no, 300)
            done = box.group(1).lower() == "x" or section == "done"
            _bucket(item, done, section, tasks, blockers, completed, warnings, prompts)
            index += 1
            continue
        bullet = re.match(r"^\s*[-*]\s+(.*)$", raw)
        number = re.match(r"^\s*\d+\.\s+(.*)$", raw)
        if section == "done" and bullet:
            completed.append(_item(bullet.group(1), line_no, 300))
        elif section == "block" and (bullet or number):
            blockers.append(_item((bullet or number).group(1), line_no, 300))
        elif section == "warn" and bullet:
            warnings.append(_item(bullet.group(1), line_no, 300))
        elif section == "prompt" and bullet:
            prompts.append(_item(bullet.group(1), line_no, 300))
        index += 1
    return {
        "tasks": _uniq(tasks)[:12],
        "blockers": _uniq(blockers)[:12],
        "completed": _uniq(completed)[:12],
        "warnings": _uniq(warnings)[:12],
        "prompts": _uniq(prompts)[:12],
    }


def _bucket(
    item: dict,
    done: bool,
    section: str,
    tasks: list[dict],
    blockers: list[dict],
    completed: list[dict],
    warnings: list[dict],
    prompts: list[dict],
) -> None:
    if not item["text"] or section == "parked":
        return
    if done:
        completed.append(item)
    elif section == "block":
        blockers.append(item)
    elif section == "warn":
        warnings.append(item)
    elif section == "prompt":
        prompts.append(item)
    else:
        tasks.append(item)


def _consume_table(
    header: list[str],
    rows: list[tuple[int, list[str]]],
    section: str,
    tasks: list[dict],
    blockers: list[dict],
    completed: list[dict],
    warnings: list[dict],
    prompts: list[dict],
) -> None:
    status_i = _col(header, "status")
    question_i = _col(header, "question")
    item_i = _col(header, "item", "topic", "task")
    id_i = _col(header, "#", "id")
    if status_i is None and question_i is None:
        names = {h.strip().lower() for h in header}
        if "open" in names or "bucket" in names:
            return
    for line_no, row in rows:
        ident = _cell(row, id_i)
        text = _cell(row, item_i if item_i is not None else 0)
        if ident and text and ident.lower() not in text.lower():
            text = f"{ident}: {text}"
        if question_i is not None and status_i is None:
            question = _cell(row, question_i)
            if text and question:
                # Preview keeps the old split (300 for the item, 240 for the question); full text keeps both whole.
                item = _item(f"{text} — {question}", line_no, FULL_LIMIT, ident)
                item["text"] = f"{_clip(text, 300)} — {_clip(question, 240)}"
            else:
                item = _item(question or text, line_no, 300 if text else 240, ident)
            if item["text"]:
                prompts.append(item)
            continue
        item = _item(text, line_no, 300, ident)
        status = _cell(row, status_i).lower()
        done = section == "done" or bool(re.search(r"\b(done|closed|merged|landed)\b", status))
        if re.search(r"\b(blocked|blocking|on hold)\b", status) or re.search(r"\bblock\b", status):
            blockers.append(item)
        elif "warn" in status or (section == "warn" and item["text"]):
            warnings.append(item)
        else:
            _bucket(item, done, section, tasks, blockers, completed, warnings, prompts)


def _uniq(items: list[dict]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for item in items:
        key = item["text"].strip()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def tracker_github_url(slug: str | None, rel: str, line: int | None, branch: str | None, ahead: int | None) -> str | None:
    """Link to a tracker row on GitHub main. The #L anchor is added only when the local checkout is
    main with nothing unpushed; otherwise the local line number may not match main's copy."""
    if not slug or not rel:
        return None
    url = f"https://github.com/{slug}/blob/main/{rel}"
    if line and branch == "main" and not ahead:
        url += f"#L{line}"
    return url


def _git(path: Path, *args: str, timeout: float = 12) -> tuple[int, str]:
    code, out, err = _run(["git", "-C", str(path), *args], timeout=timeout)
    return code, (out or err).strip()


def _github_slug(path: Path) -> str | None:
    code, url = _git(path, "remote", "get-url", "origin")
    if code != 0 or not url:
        return None
    match = re.search(r"github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?$", url.strip())
    if not match:
        return None
    return f"{match.group(1)}/{match.group(2)}"


def _check_conclusions(rollup: object) -> list[str]:
    found: list[str] = []
    if not isinstance(rollup, list):
        return found
    for item in rollup:
        if not isinstance(item, dict):
            continue
        value = item.get("conclusion") or item.get("state") or ""
        if value:
            found.append(str(value).upper())
        nested = item.get("statusCheckRollup")
        if isinstance(nested, list):
            found.extend(_check_conclusions(nested))
    return found


def _ci_state(conclusions: list[str]) -> str:
    if not conclusions:
        return "none"
    failed = {"FAILURE", "CANCELLED", "TIMED_OUT", "STARTUP_FAILURE", "ERROR"}
    pending = {"PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "EXPECTED"}
    if any(item in failed for item in conclusions):
        return "failure"
    if any(item in pending for item in conclusions):
        return "pending"
    return "passing"


_GH_LOCK = threading.Lock()
_GH_CACHE: dict[tuple[str, str, int], tuple[float, list[dict]]] = {}
_GH_STATE = {"ok": None, "detail": None}


def _gh_json(slug: str, state: str, limit: int) -> list[dict]:
    key = (slug, state, limit)
    now = time.time()
    with _GH_LOCK:
        hit = _GH_CACHE.get(key)
        if hit and now - hit[0] < 45:
            return hit[1]
    code, out, err = _run(
        [
            "gh",
            "pr",
            "list",
            "--repo",
            slug,
            "--state",
            state,
            "--limit",
            str(limit),
            "--json",
            "number,title,url,updatedAt,mergedAt,statusCheckRollup",
        ],
        timeout=25,
    )
    if code != 0 or not out.strip():
        detail = ((err or out) or "gh failed").strip().splitlines()
        with _GH_LOCK:
            _GH_CACHE[key] = (time.time(), [])
            if _GH_STATE["ok"] is not True:
                _GH_STATE["ok"] = False
                _GH_STATE["detail"] = (detail[0] if detail else "gh failed")[:180]
        return []
    with _GH_LOCK:
        _GH_STATE["ok"] = True
        _GH_STATE["detail"] = None
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        data = []
    rows = data if isinstance(data, list) else []
    with _GH_LOCK:
        _GH_CACHE[key] = (time.time(), rows)
    return rows


def project_git(path: Path) -> dict:
    info: dict = {
        "git": False,
        "branch": None,
        "dirty": False,
        "ahead": None,
        "behind": None,
        "lastCommit": None,
        "slug": None,
        "rebasing": False,
        "merging": False,
    }
    if not (path / ".git").exists():
        return info
    info["git"] = True
    code, branch = _git(path, "rev-parse", "--abbrev-ref", "HEAD")
    info["branch"] = branch if code == 0 and branch else None
    code, porcelain = _git(path, "status", "--porcelain")
    info["dirty"] = code == 0 and bool(porcelain.strip())
    code, counts = _git(path, "rev-list", "--left-right", "--count", "@{u}...HEAD")
    if code == 0 and counts:
        parts = counts.split()
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            info["behind"] = int(parts[0])
            info["ahead"] = int(parts[1])
    code, subject = _git(path, "log", "-1", "--format=%s%x09%cI")
    if code == 0 and subject:
        title, _, when = subject.partition("\t")
        info["lastCommit"] = {"subject": _clip(title, 180), "at": when or None}
    info["slug"] = _github_slug(path)
    info["merging"] = _git_path_exists(path, "MERGE_HEAD")
    info["rebasing"] = _git_path_exists(path, "rebase-merge") or _git_path_exists(path, "rebase-apply")
    return info


def _git_path_exists(path: Path, name: str) -> bool:
    code, rel = _git(path, "rev-parse", "--git-path", name)
    if code != 0 or not rel:
        return False
    candidate = Path(rel)
    if not candidate.is_absolute():
        candidate = path / rel
    return candidate.exists()


def _read_text(path: Path, limit: int) -> str:
    try:
        data = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    if len(data) <= limit:
        return data
    return data[:limit]


def usable_picture(width: int, height: int, size: int, name: str) -> bool:
    """True for a document or photo. False for icons, sprites, and tiny files."""
    if re.search(r"favicon|sprite|cursor|apple-touch-icon", name, re.IGNORECASE):
        return False
    if width < 96 or height < 96 or size < 6_000:
        return False
    short = min(width, height)
    long = max(width, height)
    if short >= 280 and long >= 360:
        return True
    if short >= 200 and long >= 640 and size >= 20_000:
        return True
    return False


def image_size(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as handle:
            head = handle.read(32)
    except OSError:
        return None
    if head.startswith(b"\x89PNG\r\n\x1a\n") and len(head) >= 24:
        width, height = struct.unpack(">II", head[16:24])
        if width and height:
            return int(width), int(height)
        return None
    if head[:3] == b"\xff\xd8\xff":
        return _jpeg_size(path)
    if len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return _webp_size(path)
    return None


def _jpeg_size(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as handle:
            if handle.read(2) != b"\xff\xd8":
                return None
            while True:
                marker = handle.read(1)
                if not marker:
                    return None
                while marker != b"\xff":
                    marker = handle.read(1)
                    if not marker:
                        return None
                kind = handle.read(1)
                if not kind:
                    return None
                code = kind[0]
                if code in (0xD8, 0xD9, 0x01) or 0xD0 <= code <= 0xD7:
                    continue
                length_bytes = handle.read(2)
                if len(length_bytes) < 2:
                    return None
                length = struct.unpack(">H", length_bytes)[0]
                if code in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    data = handle.read(5)
                    if len(data) < 5:
                        return None
                    height, width = struct.unpack(">HH", data[1:5])
                    if width and height:
                        return int(width), int(height)
                    return None
                handle.seek(max(0, length - 2), os.SEEK_CUR)
    except OSError:
        return None


def _webp_size(path: Path) -> tuple[int, int] | None:
    try:
        data = path.read_bytes()[:40]
    except OSError:
        return None
    if len(data) < 30 or data[12:16] not in (b"VP8X", b"VP8 ", b"VP8L"):
        return None
    chunk = data[12:16]
    if chunk == b"VP8X":
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
    elif chunk == b"VP8 ":
        width = int.from_bytes(data[26:28], "little") & 0x3FFF
        height = int.from_bytes(data[28:30], "little") & 0x3FFF
    else:
        bits = int.from_bytes(data[21:25], "little")
        width = (bits & 0x3FFF) + 1
        height = ((bits >> 14) & 0x3FFF) + 1
    if width and height:
        return int(width), int(height)
    return None


def _preview_score(rel: str) -> int:
    low = rel.lower()
    score = 0
    for hint in ("/docs/", "/doc/", "/draw", "/figure", "/image", "/photo", "/picture", "/media/", "/scans/"):
        if hint in f"/{low}":
            score += 40
    if low.endswith("readme.md"):
        score += 20
    return score


def _previews(path: Path) -> list[dict]:
    pictures: list[tuple[int, dict]] = []
    pdfs: list[tuple[int, dict]] = []
    markdowns: list[dict] = []
    seen = 0

    def consider(child: Path) -> None:
        nonlocal seen
        if not is_allowed_file(path, child):
            return
        rel = child.relative_to(path).as_posix()
        suffix = child.suffix.lower()
        try:
            size = child.stat().st_size
        except OSError:
            return
        if suffix == ".pdf":
            if size < 1_000 or size > 40_000_000:
                return
            pdfs.append((_preview_score(rel), {"kind": "pdf", "rel": rel, "title": child.name}))
            return
        if suffix not in {".png", ".jpg", ".jpeg", ".webp"}:
            return
        if size > 12_000_000:
            return
        dims = image_size(child)
        if not dims or not usable_picture(dims[0], dims[1], size, child.name):
            return
        pictures.append(
            (
                _preview_score(rel) + min(dims[0], dims[1]) // 40,
                {
                    "kind": "image",
                    "rel": rel,
                    "title": child.name,
                    "width": dims[0],
                    "height": dims[1],
                },
            )
        )

    def walk(directory: Path, depth: int) -> None:
        nonlocal seen
        if depth > 4 or seen > 500 or len(pictures) + len(pdfs) > 40:
            return
        try:
            children = sorted(directory.iterdir(), key=lambda item: item.name.lower())
        except OSError:
            return
        for child in children:
            if seen > 500:
                return
            name = child.name
            if name in SKIP_WALK or name.startswith(".") or name.lower() in {"icons", "favicon"}:
                continue
            if child.is_dir():
                walk(child, depth + 1)
                continue
            seen += 1
            if child.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".pdf"}:
                consider(child)

    walk(path, 0)
    for rel in ("README.md", "docs/README.md"):
        file = path / rel
        if file.is_file() and is_allowed_file(path, file):
            excerpt = _clip(_read_text(file, 4_000), 1_400)
            if len(excerpt) > 80:
                markdowns.append({"kind": "markdown", "rel": rel, "title": "README.md", "excerpt": excerpt})
            break
    docs = path / "docs"
    if docs.is_dir():
        try:
            files = sorted(docs.glob("*.md"), key=lambda item: item.name.lower())
        except OSError:
            files = []
        for file in files:
            if len(markdowns) >= 2:
                break
            if file.name.lower() in {"open-items.md", "readme.md"}:
                continue
            if not is_allowed_file(path, file):
                continue
            excerpt = _clip(_read_text(file, 4_000), 1_400)
            if len(excerpt) < 80:
                continue
            markdowns.append(
                {"kind": "markdown", "rel": file.relative_to(path).as_posix(), "title": file.name, "excerpt": excerpt}
            )
    pictures.sort(key=lambda item: item[0], reverse=True)
    pdfs.sort(key=lambda item: item[0], reverse=True)
    chosen = [item for _, item in pdfs[:3]] + [item for _, item in pictures[:6]] + markdowns[:2]
    return chosen[:8]


def render_pdf_png(project_name: str, rel: str) -> bytes | None:
    """Rasterize the first PDF page. Returns nothing when the page cannot be drawn."""
    file = project_file(project_name, rel)
    if file is None or file.suffix.lower() != ".pdf":
        return None
    vendor = state_dir() / "py"
    if vendor.is_dir() and str(vendor) not in sys.path:
        sys.path.insert(0, str(vendor))
    try:
        import fitz
    except ImportError:
        return None
    try:
        stamp = file.stat().st_mtime_ns
    except OSError:
        return None
    cache = state_dir() / "preview-cache"
    cache.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(f"{file}|{stamp}".encode("utf-8", "replace")).hexdigest()[:24]
    dest = cache / f"{key}.png"
    if dest.is_file() and dest.stat().st_size > 1_000:
        try:
            return dest.read_bytes()
        except OSError:
            return None
    try:
        document = fitz.open(file)
        if document.page_count < 1:
            document.close()
            return None
        page = document[0]
        pixmap = page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False)
        document.close()
        if pixmap.width < 400 or pixmap.height < 400:
            return None
        png = pixmap.tobytes("png")
    except Exception:
        return None
    try:
        dest.write_bytes(png)
    except OSError:
        pass
    return png


def is_allowed_file(project: Path, candidate: Path) -> bool:
    try:
        project_resolved = project.resolve()
        resolved = candidate.resolve()
    except OSError:
        return False
    if not resolved.is_file():
        return False
    try:
        rel = resolved.relative_to(project_resolved)
    except ValueError:
        return False
    parts = {part.lower() for part in rel.parts}
    if parts & {".git", "node_modules", ".venv", "venv"}:
        return False
    if SECRET_NAME.search(resolved.name) or SECRET_NAME.search(rel.as_posix()):
        return False
    return True


def _tracker_for(path: Path) -> tuple[str, dict | None]:
    for rel in ("docs/OPEN-ITEMS.md", "OPEN-ITEMS.md"):
        file = path / rel
        if file.is_file() and is_allowed_file(path, file):
            return rel, parse_tracker(_read_text(file, 200_000))
    return "", None


def _readme_for(path: Path) -> str:
    for name in ("README.md", "README.rst", "README.txt", "README"):
        file = path / name
        if file.is_file() and is_allowed_file(path, file):
            return _clip(_read_text(file, 5000), 3500)
    return ""


def collect_project(entry: Path, lite: bool) -> dict:
    git_info = project_git(entry) if entry.is_dir() else {"git": False}
    tracker_rel, tracker = ("", None)
    readme = ""
    previews: list[dict] = []
    if entry.is_dir():
        tracker_rel, tracker = _tracker_for(entry)
        if not lite:
            previews = _previews(entry)
    prs: list[dict] = []
    merged = None
    ci_failures: list[dict] = []
    slug = git_info.get("slug") if isinstance(git_info, dict) else None
    if slug:
        for row in _gh_json(slug, "open", 20):
            conclusions = _check_conclusions(row.get("statusCheckRollup"))
            state = _ci_state(conclusions)
            item = {
                "number": row.get("number"),
                "title": _clip(str(row.get("title") or ""), 160),
                "url": row.get("url"),
                "ci": state,
            }
            prs.append(item)
            if state == "failure":
                ci_failures.append(
                    {
                        "project": entry.name,
                        "number": item["number"],
                        "title": item["title"],
                        "url": item["url"],
                    }
                )
        merged_rows = _gh_json(slug, "merged", 1)
        if merged_rows:
            row = merged_rows[0]
            merged = {
                "number": row.get("number"),
                "title": _clip(str(row.get("title") or ""), 160),
                "url": row.get("url"),
                "at": row.get("mergedAt"),
            }
    tracker = tracker or {
        "tasks": [],
        "blockers": [],
        "completed": [],
        "warnings": [],
        "prompts": [],
    }
    branch, ahead = git_info.get("branch"), git_info.get("ahead")
    for bucket in ("tasks", "blockers", "completed", "warnings", "prompts"):
        for item in tracker[bucket]:
            url = tracker_github_url(slug, tracker_rel, item.get("line"), branch, ahead)
            if url:
                item["githubUrl"] = url
    return {
        "name": entry.name,
        "kind": "dir" if entry.is_dir() else "file",
        "branch": git_info.get("branch"),
        "dirty": bool(git_info.get("dirty")),
        "ahead": git_info.get("ahead"),
        "behind": git_info.get("behind"),
        "lastCommit": git_info.get("lastCommit"),
        "git": bool(git_info.get("git")),
        "rebasing": bool(git_info.get("rebasing")),
        "merging": bool(git_info.get("merging")),
        "tracker": tracker_rel or None,
        "tasks": tracker["tasks"],
        "blockers": tracker["blockers"],
        "completed": tracker["completed"],
        "warnings": tracker["warnings"],
        "prompts": tracker["prompts"],
        "readme": readme,
        "previews": previews,
        "prs": prs,
        "ciFailures": ci_failures,
        "merged": merged,
        "openPrs": len(prs),
        "openTasks": len(tracker["tasks"]) + len(tracker["blockers"]) + len(tracker["prompts"]),
    }


def _message_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict) and block.get("type") in {"text", "output_text"}:
                parts.append(str(block.get("text") or ""))
        return "\n".join(parts)
    if isinstance(content, dict):
        return str(content.get("text") or "")
    return ""


def _usage_from(obj: dict) -> dict | None:
    message = obj.get("message") if isinstance(obj.get("message"), dict) else {}
    usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else None
    if usage is None and isinstance(message, dict):
        usage = message.get("usage") if isinstance(message.get("usage"), dict) else None
    if not isinstance(usage, dict):
        return None
    input_tokens = int(usage.get("input_tokens") or 0)
    cache_read = int(usage.get("cache_read_input_tokens") or usage.get("cache_read") or 0)
    cache_write = int(usage.get("cache_creation_input_tokens") or 0)
    output_tokens = int(usage.get("output_tokens") or 0)
    window = usage.get("context_window") or obj.get("context_window")
    size = None
    if isinstance(window, dict):
        size = window.get("context_window_size") or window.get("size")
    elif isinstance(window, int):
        size = window
    used = input_tokens + cache_read + cache_write
    percent = None
    if size:
        try:
            percent = round(used / float(size) * 100, 1)
        except (TypeError, ValueError, ZeroDivisionError):
            percent = None
    return {
        "inputTokens": used,
        "outputTokens": output_tokens,
        "window": size,
        "percent": percent,
    }


def _tail_records(path: Path, max_bytes: int = 160_000) -> list[dict]:
    try:
        size = path.stat().st_size
    except OSError:
        return []
    try:
        with path.open("rb") as handle:
            handle.seek(max(0, size - max_bytes))
            raw = handle.read().decode("utf-8", "replace")
    except OSError:
        return []
    records: list[dict] = []
    for line in raw.splitlines():
        start = line.find("{")
        if start < 0:
            continue
        try:
            obj = json.loads(line[start:])
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            records.append(obj)
    return records


def _head_text(path: Path, max_bytes: int = 2500) -> str:
    try:
        with path.open("rb") as handle:
            return handle.read(max_bytes).decode("utf-8", "replace")
    except OSError:
        return ""


def _claude_sessions(limit: int = 30) -> list[dict]:
    root = Path.home() / ".claude" / "projects"
    if not root.is_dir():
        return []
    files: list[tuple[float, Path]] = []
    try:
        projects = list(root.iterdir())
    except OSError:
        return []
    cutoff = time.time() - 21 * 24 * 3600
    for project in projects:
        if not project.is_dir():
            continue
        try:
            children = list(project.glob("*.jsonl"))
        except OSError:
            continue
        for child in children:
            try:
                modified = child.stat().st_mtime
            except OSError:
                continue
            if modified >= cutoff:
                files.append((modified, child))
    files.sort(key=lambda item: item[0], reverse=True)
    sessions: list[dict] = []
    for modified, path in files[:limit]:
        session_id = path.stem
        if not UUID_RE.match(session_id):
            continue
        head = _head_text(path)
        dispatch = "bridge-session" in head or "bridgeSessionId" in head
        records = _tail_records(path)
        snippet = ""
        usage = None
        permission = None
        title = None
        for record in records:
            if record.get("type") in {"permission-mode", "permission_request"} or record.get("permission"):
                permission = _clip(_message_text(record.get("message") or record.get("description") or ""), 200)
            text = _message_text(
                (record.get("message") or {}).get("content")
                if isinstance(record.get("message"), dict)
                else record.get("content")
            )
            if text and record.get("type") in {"user", "assistant", None}:
                snippet = _clip(text, 240)
            found = _usage_from(record)
            if found:
                usage = found
            if not title and isinstance(record.get("name"), str):
                title = record.get("name")
        sessions.append(
            {
                "app": "dispatch" if dispatch else "claude",
                "id": session_id,
                "shortId": session_id[:8],
                "title": title or session_id[:8],
                "state": "stored",
                "snippet": snippet,
                "permission": permission,
                "context": usage,
                "updatedAt": datetime.fromtimestamp(modified, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "canSend": True,
                "sendNote": "claude --resume <id> -p",
                "webUrl": None,
                "cwd": None,
            }
        )
    return sessions


def _agent_rows() -> list[dict]:
    code, out, _err = _run(["claude", "agents", "--json", "--all"], timeout=20)
    if code != 0 or not out.strip():
        return []
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, list):
        return []
    rows = []
    for item in data:
        if isinstance(item, dict):
            rows.append(item)
    return rows


def _merge_agents(sessions: list[dict], agents: list[dict]) -> list[dict]:
    by_id = {row["id"]: row for row in sessions}
    by_short = {row["shortId"]: row for row in sessions}
    for agent in agents:
        session_id = str(agent.get("sessionId") or "")
        short = str(agent.get("id") or "")
        row = by_id.get(session_id) or by_short.get(short)
        state = str(agent.get("state") or "unknown")
        running = state in {"running", "working"}
        blocked = state == "blocked"
        note = "claude --resume <id> -p"
        can_send = True
        if running:
            can_send = False
            note = "Session is running. Resume would start a second copy, so the box will not send."
        elif blocked:
            can_send = False
            note = "Waiting on a permission prompt. No CLI command answers it."
        if row is None:
            if not UUID_RE.match(session_id):
                continue
            row = {
                "app": "claude",
                "id": session_id,
                "shortId": short or session_id[:8],
                "title": agent.get("name") or short or session_id[:8],
                "state": state,
                "snippet": "",
                "permission": "Permission prompt" if blocked else None,
                "context": None,
                "updatedAt": None,
                "canSend": can_send,
                "sendNote": note,
                "webUrl": None,
                "cwd": agent.get("cwd"),
            }
            sessions.append(row)
            continue
        row["state"] = state
        if agent.get("name"):
            row["title"] = agent.get("name")
        row["cwd"] = agent.get("cwd") or row.get("cwd")
        row["canSend"] = can_send
        row["sendNote"] = note
        if blocked and not row.get("permission"):
            row["permission"] = "Permission prompt"
        if str(agent.get("name") or "").lower().find("dispatch") >= 0 or "spare" in str(agent.get("cwd") or "").lower():
            row["app"] = "dispatch"
    return sessions


def _cursor_sessions(limit: int = 20) -> list[dict]:
    root = Path.home() / ".cursor" / "chats"
    if not root.is_dir():
        return []
    found: list[tuple[float, Path]] = []
    try:
        buckets = list(root.iterdir())
    except OSError:
        return []
    for bucket in buckets:
        if not bucket.is_dir():
            continue
        try:
            chats = list(bucket.iterdir())
        except OSError:
            continue
        for chat in chats:
            meta = chat / "meta.json"
            if not meta.is_file():
                continue
            try:
                found.append((meta.stat().st_mtime, chat))
            except OSError:
                continue
    found.sort(key=lambda item: item[0], reverse=True)
    sessions: list[dict] = []
    for modified, chat in found[:limit]:
        meta: dict = {}
        try:
            loaded = json.loads((chat / "meta.json").read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                meta = {key: value for key, value in loaded.items() if not SECRET_KEY.search(key)}
        except (OSError, json.JSONDecodeError):
            meta = {}
        name = "Cursor chat"
        mode = None
        store = chat / "store.db"
        snippet = ""
        context = None
        if store.is_file():
            try:
                con = sqlite3.connect(f"file:{store.as_posix()}?mode=ro", uri=True)
                row = con.execute("select value from meta limit 1").fetchone()
                if row and isinstance(row[0], str):
                    try:
                        decoded = json.loads(row[0])
                    except json.JSONDecodeError:
                        decoded = None
                    if isinstance(decoded, dict):
                        name = str(decoded.get("name") or name)
                        mode = decoded.get("mode")
                blob_rows = con.execute(
                    "select data from blobs order by rowid desc limit 30"
                ).fetchall()
                con.close()
                for (data,) in blob_rows:
                    if not isinstance(data, (bytes, str)):
                        continue
                    text = data.decode("utf-8", "replace") if isinstance(data, bytes) else data
                    try:
                        obj = json.loads(text)
                    except json.JSONDecodeError:
                        continue
                    if not isinstance(obj, dict):
                        continue
                    found_usage = _usage_from(obj)
                    if found_usage and context is None:
                        context = found_usage
                    if obj.get("role") in {"user", "assistant"} and not snippet:
                        snippet = _clip(_message_text(obj.get("content")), 240)
            except sqlite3.Error:
                pass
        chat_id = chat.name
        sessions.append(
            {
                "app": "cursor",
                "id": chat_id,
                "shortId": chat_id[:8],
                "title": name,
                "state": str(mode or "local"),
                "snippet": snippet,
                "permission": None,
                "context": context,
                "updatedAt": datetime.fromtimestamp(modified, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "canSend": False,
                "sendNote": "Checked at send time against agent status.",
                "webUrl": f"https://cursor.com/agents/{chat_id}" if chat_id.startswith("bc-") else None,
                "cwd": meta.get("cwd"),
            }
        )
    return sessions


def _public_usage(obj: dict) -> dict:
    kept: dict = {}
    for key, value in obj.items():
        if SECRET_KEY.search(str(key)):
            continue
        if not re.search(r"limit|usage|quota|remaining|reset|window", str(key), re.IGNORECASE):
            continue
        if isinstance(value, (int, float, str)) and len(str(value)) < 80:
            kept[str(key)] = value
    return kept


def _usage_limits() -> dict:
    home = Path.home()
    files = [
        home / ".claude" / "daemon-auth-status.json",
        home / ".claude" / ".last-update-result.json",
    ]
    state = home / ".claude" / "state"
    if state.is_dir():
        try:
            for child in state.iterdir():
                if child.suffix.lower() == ".json" and child.stat().st_size < 200_000:
                    files.append(child)
        except OSError:
            pass
    claude: dict = {}
    for file in files:
        if not file.is_file() or "credential" in file.name.lower():
            continue
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict):
            claude.update(_public_usage(data))
    code, out, _err = _run(["agent", "status", "--format", "json"], timeout=15)
    cursor: dict = {"reported": False}
    if code == 0 and out.strip():
        try:
            status = json.loads(out)
        except json.JSONDecodeError:
            status = {}
        if isinstance(status, dict):
            cursor = {
                "reported": False,
                "authenticated": bool(status.get("isAuthenticated")),
            }
    return {
        "claude": {"reported": bool(claude), "fields": claude},
        "dispatch": {"reported": bool(claude), "fields": claude, "note": "Same Claude account as the CLI."},
        "cursor": cursor,
    }


def _worker() -> dict:
    code, out, err = _run(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            "try { (Invoke-WebRequest -Uri 'http://127.0.0.1:8787/readyz' -UseBasicParsing -TimeoutSec 3).StatusCode } catch { if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 } }",
        ],
        timeout=12,
    )
    text = (out or err).strip()
    status = int(text) if text.isdigit() else 0
    return {"up": status in {200, 503}, "status": status}


def _claude_remote(agents: list[dict]) -> dict:
    live = [
        agent
        for agent in agents
        if "remote-control" in str(agent.get("name") or "").lower()
        and str(agent.get("state") or "") not in {"stopped", "done", "failed"}
    ]
    code, out, _err = _run(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            "$p = Get-CimInstance Win32_Process -Filter \"Name = 'claude.exe'\" | Where-Object { $_.CommandLine -match '--remote-control' }; @($p).Count",
        ],
        timeout=15,
    )
    procs = int(out.strip()) if out.strip().isdigit() else 0
    return {"up": bool(live) or procs > 0, "sessions": len(live), "processes": procs}


def _shortcuts(folder: Path) -> list[dict]:
    if not folder.is_dir():
        return []
    links = []
    try:
        children = sorted(folder.glob("*.lnk"), key=lambda item: item.name.lower())
    except OSError:
        return []
    for link in children:
        links.append({"name": link.stem, "file": link.name})
    return links


def _capabilities(cursor_auth: bool) -> dict:
    claude_ok = _run(["claude", "--version"], timeout=12)[0] == 0
    return {
        "claude": {
            "send": claude_ok,
            "command": "claude --resume <session-id> -p --output-format json",
            "note": "The CLI rejects an unknown session id, so the resume path is real. A running session is not resumed.",
        },
        "dispatch": {
            "send": claude_ok,
            "command": "claude --resume <session-id> -p --output-format json",
            "note": "Dispatch bridge sessions use the same Claude session id.",
        },
        "cursor": {
            "send": cursor_auth,
            "command": "agent --resume <chat-id> -p --mode ask --output-format json",
            "note": "Send runs only when agent status is authenticated."
            if cursor_auth
            else "agent status is not logged in, so a Cursor chat cannot receive a snippet from this page.",
        },
    }


def build_snapshot(lite: bool = False) -> dict:
    roots = load_roots()
    active = Path(roots["active"])
    entries: list[Path] = []
    if active.is_dir():
        try:
            entries = sorted(
                [child for child in active.iterdir() if not child.name.startswith(".")],
                key=lambda item: item.name.lower(),
            )
        except OSError:
            entries = []
    projects: list[dict] = []
    workers = min(6, max(1, len(entries)))
    if entries:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(collect_project, entry, lite): entry for entry in entries}
            for future in as_completed(futures):
                try:
                    projects.append(future.result())
                except Exception as exc:  # noqa: BLE001 — one repo must not blank the board
                    projects.append(
                        {
                            "name": futures[future].name,
                            "kind": "dir",
                            "error": str(exc),
                            "prs": [],
                            "ciFailures": [],
                            "tasks": [],
                            "blockers": [],
                            "completed": [],
                            "warnings": [],
                            "prompts": [],
                            "openPrs": 0,
                            "openTasks": 0,
                        }
                    )
    projects.sort(key=lambda item: item.get("name", "").lower())
    worker = _worker()
    remote = _claude_remote(_agent_rows())
    alerts: list[dict] = []
    if not worker["up"]:
        alerts.append({"level": "warning", "text": "Cursor worker is not answering on 127.0.0.1:8787."})
    if not remote["up"]:
        alerts.append({"level": "warning", "text": "Claude remote control is not running."})
    for project in projects:
        for failure in project.get("ciFailures") or []:
            alerts.append(
                {
                    "level": "failure",
                    "text": f"{failure.get('project')} PR #{failure.get('number')} CI failed",
                    "url": failure.get("url"),
                }
            )
        if project.get("rebasing") or project.get("merging"):
            alerts.append(
                {
                    "level": "warning",
                    "text": f"{project.get('name')} has a merge or rebase in progress.",
                }
            )
    return {
        "generatedAt": _now(),
        "github": {"ok": _GH_STATE["ok"], "detail": _GH_STATE["detail"]},
        "lite": lite,
        "alerts": alerts[:12],
        "shortcuts": _shortcuts(Path(roots["shortcuts"])),
        "projects": projects,
    }


def shortcut_path(name: str) -> Path | None:
    folder = Path(load_roots()["shortcuts"]).resolve()
    if not folder.is_dir():
        return None
    candidate = (folder / name).resolve() if name.lower().endswith(".lnk") else (folder / f"{name}.lnk").resolve()
    try:
        candidate.relative_to(folder)
    except ValueError:
        return None
    if candidate.suffix.lower() != ".lnk" or not candidate.is_file():
        return None
    return candidate


def project_file(project_name: str, rel: str) -> Path | None:
    if not project_name or not rel or rel.startswith(("/", "\\")) or ".." in Path(rel).parts:
        return None
    active = Path(load_roots()["active"]).resolve()
    project = (active / project_name).resolve()
    try:
        project.relative_to(active)
    except ValueError:
        return None
    if not project.is_dir():
        return None
    candidate = (project / rel).resolve()
    if not is_allowed_file(project, candidate):
        return None
    if candidate.suffix.lower() not in IMAGE_EXT | {".pdf", ".md", ".markdown", ".rst", ".txt"}:
        return None
    return candidate
