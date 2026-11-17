#!/usr/bin/env python3
"""Check the Cursor plugin manifests. Stdlib only.

Official rules this encodes (no version field, by the approved plan):
- Claude plugin.json: `name` is the only required field. `repository` is optional
  and is not validated. `version` is optional. A missing version, description, or
  author is a warning, and `--strict` turns that warning into a failure.
  https://code.claude.com/docs/en/plugins-reference
- Cursor plugin manifest: `name` is the only required field. `skills` is optional.
  https://cursor.com/docs/reference/plugins
  Schema: https://github.com/cursor/plugins/blob/main/schemas/plugin.schema.json
- Marketplace `source` is a string of length >= 1 (a path or a remote URL).
  "." is a legal path. Schema required fields are `name` and `plugins`; `owner`
  is allowed and the docs page also asks for it.
  https://github.com/cursor/plugins/blob/main/schemas/marketplace.schema.json
  https://cursor.com/docs/reference/plugins
- Resolution looks for `<source>/.cursor-plugin/plugin.json`, using
  path.resolve(root, source). "." resolves to the repo root.
  https://github.com/cursor/plugins/blob/main/scripts/validate-plugins.mjs
- Cursor plugin `hooks` is a path or an inline object. A set path replaces
  default discovery of `hooks/hooks.json`.
  https://cursor.com/docs/reference/plugins
- Cursor hook events and `"version": 1` live in that hooks file, not in
  plugin.json. https://cursor.com/docs/hooks
- Claude Code loads `hooks/hooks.json` (different shape: SessionStart /
  PreToolUse / Stop, `${CLAUDE_PLUGIN_ROOT}`).
  https://code.claude.com/docs/en/plugins-reference
  The two files stay separate so neither host parses the other's event names.
- `agents-md-only-warn.ps1` is Claude SessionStart only. No Cursor variant
  until decision C1.

`skills` is `./skills/`, so every `skills/<name>/SKILL.md` is included.
This does not run Cursor's importer. A passing check is not a live import.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CLAUDE_PLUGIN = {
    "name": "workstation-core",
    "repository": "https://github.com/living-relation/workstation",
}
CURSOR_PLUGIN = {
    "name": "workstation-core",
    "skills": "./skills/",
    "hooks": "./hooks/cursor-hooks.json",
}
CURSOR_MARKETPLACE = {
    "name": "workstation-core",
    "owner": {"name": "living-relation"},
    "plugins": [{"name": "workstation-core", "source": "."}],
}


def _load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        raise ValueError(f"{path}: {e}") from e


def _version_keys(obj, where):
    found = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "version":
                found.append(where + ".version")
            found.extend(_version_keys(v, where + "." + k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            found.extend(_version_keys(v, f"{where}[{i}]"))
    return found


def resolve_source(root: Path, source: str) -> Path:
    """Same resolution as path.resolve(root, source). Rejects absolute paths and '..'."""
    if not isinstance(source, str) or not source:
        raise ValueError(f"source must be a non-empty string, got {source!r}")
    parts = Path(source).parts
    if source.startswith(("/", "\\")) or (len(source) > 1 and source[1] == ":"):
        raise ValueError(f"source is absolute: {source}")
    if ".." in parts:
        raise ValueError(f'source contains "..": {source}')
    return (root / source).resolve()


def check(root: Path):
    errors = []
    files = {
        ".claude-plugin/plugin.json": CLAUDE_PLUGIN,
        ".cursor-plugin/plugin.json": CURSOR_PLUGIN,
        ".cursor-plugin/marketplace.json": CURSOR_MARKETPLACE,
    }
    loaded = {}
    for rel, expected in files.items():
        path = root / rel
        try:
            data = _load(path)
        except ValueError as e:
            errors.append(str(e))
            continue
        loaded[rel] = data
        if data != expected:
            errors.append(
                f"{rel}: expected {json.dumps(expected, sort_keys=True)}, "
                f"got {json.dumps(data, sort_keys=True)}"
            )
        for hit in _version_keys(data, rel):
            errors.append(f"{hit}: version field is not allowed")
    market = loaded.get(".cursor-plugin/marketplace.json")
    if isinstance(market, dict):
        for entry in market.get("plugins") or []:
            source = entry.get("source") if isinstance(entry, dict) else None
            try:
                plugin_dir = resolve_source(root, source)
            except ValueError as e:
                errors.append(str(e))
                continue
            manifest = plugin_dir / ".cursor-plugin" / "plugin.json"
            if not manifest.is_file():
                errors.append(
                    f"source {source!r} resolves to {plugin_dir} but {manifest} is missing"
                )
            elif source == "." and plugin_dir != root.resolve():
                errors.append(f'source "." resolved to {plugin_dir}, not the repo root')
    skills = root / "skills"
    if not skills.is_dir() or not any(skills.glob("*/SKILL.md")):
        errors.append("skills/*/SKILL.md is missing; plugin skills stay in skills/<name>/SKILL.md")
    for banned in ("bin",):
        if (root / banned).exists():
            errors.append(f"{banned}/ is present; the plugin must not ship a bin folder")
    for banned in ("mcp.json", ".mcp.json"):
        if (root / banned).exists():
            errors.append(f"{banned} is present; the plugin must not ship an MCP server")
    cursor = loaded.get(".cursor-plugin/plugin.json")
    if isinstance(cursor, dict):
        errors.extend(_check_cursor_hooks(root, cursor.get("hooks")))
    errors.extend(_check_claude_hooks(root))
    return errors


def _check_cursor_hooks(root: Path, hooks_field):
    """Cursor hooks are a separate file. plugin.json `hooks` replaces hooks/hooks.json."""
    errors = []
    if not isinstance(hooks_field, str) or not hooks_field:
        errors.append("cursor plugin hooks must be a path to the Cursor hooks file")
        return errors
    path = (root / hooks_field).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        errors.append(f"cursor hooks path escapes the repo: {hooks_field}")
        return errors
    if not path.is_file():
        errors.append(f"cursor hooks path {hooks_field} is missing")
        return errors
    try:
        data = _load(path)
    except ValueError as e:
        errors.append(str(e))
        return errors
    if data.get("version") != 1:
        errors.append(f"{hooks_field}: Cursor hooks file must set version 1")
    events = data.get("hooks") if isinstance(data.get("hooks"), dict) else {}
    if "preToolUse" not in events or "stop" not in events:
        errors.append(f"{hooks_field}: needs preToolUse and stop")
    if "PreToolUse" in events or "Stop" in events:
        errors.append(f"{hooks_field}: Claude event names belong in hooks/hooks.json")
    text = path.read_text(encoding="utf-8")
    if "${CURSOR_PLUGIN_ROOT}" not in text:
        errors.append(f"{hooks_field}: commands must use ${{CURSOR_PLUGIN_ROOT}}")
    for script in ("projects-root-guard.ps1", "projects-root-report.ps1"):
        if script not in text:
            errors.append(f"{hooks_field}: missing {script}")
        elif not (root / "hooks" / script).is_file():
            errors.append(f"hooks/{script} is missing")
    if "agents-md-only-warn.ps1" in text:
        errors.append(
            f"{hooks_field}: agents-md-only-warn is Claude-only until decision C1"
        )
    return errors


def _check_claude_hooks(root: Path):
    """Claude Code's default hooks file. Do not put Cursor event names here."""
    errors = []
    path = root / "hooks" / "hooks.json"
    if not path.is_file():
        errors.append("hooks/hooks.json is missing; Claude plugin hooks live there")
        return errors
    try:
        data = _load(path)
    except ValueError as e:
        errors.append(str(e))
        return errors
    events = data.get("hooks") if isinstance(data.get("hooks"), dict) else {}
    if "PreToolUse" not in events or "Stop" not in events:
        errors.append("hooks/hooks.json: needs PreToolUse and Stop")
    if "SessionStart" not in events:
        errors.append("hooks/hooks.json: needs SessionStart")
    if "preToolUse" in events or "stop" in events:
        errors.append("hooks/hooks.json: Cursor event names belong in the Cursor hooks file")
    text = path.read_text(encoding="utf-8")
    if "${CLAUDE_PLUGIN_ROOT}" not in text:
        errors.append("hooks/hooks.json: commands must use ${CLAUDE_PLUGIN_ROOT}")
    pre = events.get("PreToolUse") or []
    matchers = []
    for entry in pre:
        if isinstance(entry, dict) and entry.get("matcher"):
            matchers.append(entry["matcher"])
    joined = " ".join(matchers)
    for name in ("Write", "Edit", "NotebookEdit", "Bash", "PowerShell"):
        if name not in joined:
            errors.append(f"hooks/hooks.json: PreToolUse matcher is missing {name}")
    for script in (
        "projects-root-guard.ps1",
        "projects-root-report.ps1",
        "agents-md-only-warn.ps1",
    ):
        if script not in text:
            errors.append(f"hooks/hooks.json: missing {script}")
        elif not (root / "hooks" / script).is_file():
            errors.append(f"hooks/{script} is missing")
    wired = False
    for entry in events.get("SessionStart") or []:
        hooks = entry.get("hooks") if isinstance(entry, dict) else None
        for hook in hooks or []:
            cmd = hook.get("command") if isinstance(hook, dict) else ""
            if (
                "agents-md-only-warn.ps1" in cmd
                and "${CLAUDE_PLUGIN_ROOT}" in cmd
            ):
                wired = True
    if not wired:
        errors.append(
            "hooks/hooks.json: SessionStart must run agents-md-only-warn.ps1 "
            "with ${CLAUDE_PLUGIN_ROOT}"
        )
    return errors


def main(argv):
    root = Path(argv[1]).resolve() if len(argv) > 1 else ROOT
    errors = check(root)
    if errors:
        for e in errors:
            print("plugin-check:", e)
        return 1
    print('cursor plugin JSON ok; source "." resolves to .cursor-plugin/plugin.json')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
