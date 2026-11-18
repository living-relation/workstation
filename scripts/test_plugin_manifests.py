"""Plugin manifests: no version field, and Cursor source "." resolves to the repo root."""
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import check_cursor_plugin as chk  # noqa: E402


def _write_hooks(root: Path):
    hooks = root / "hooks"
    hooks.mkdir()
    (hooks / "projects-root-guard.ps1").write_text("# guard\n", encoding="utf-8")
    (hooks / "projects-root-report.ps1").write_text("# report\n", encoding="utf-8")
    (hooks / "agents-md-only-warn.ps1").write_text("# warn\n", encoding="utf-8")
    (hooks / "hooks.json").write_text(
        json.dumps(
            {
                "hooks": {
                    "PreToolUse": [
                        {
                            "matcher": "Write|Edit|NotebookEdit|Bash|PowerShell",
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": 'powershell -File "${CLAUDE_PLUGIN_ROOT}/hooks/projects-root-guard.ps1"',
                                }
                            ],
                        }
                    ],
                    "Stop": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": 'powershell -File "${CLAUDE_PLUGIN_ROOT}/hooks/projects-root-report.ps1"',
                                }
                            ]
                        }
                    ],
                    "SessionStart": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": 'powershell -File "${CLAUDE_PLUGIN_ROOT}/hooks/agents-md-only-warn.ps1"',
                                }
                            ]
                        }
                    ],
                }
            }
        )
        + "\n",
        encoding="utf-8",
    )
    (hooks / "cursor-hooks.json").write_text(
        json.dumps(
            {
                "version": 1,
                "hooks": {
                    "preToolUse": [
                        {
                            "command": 'powershell -File "${CURSOR_PLUGIN_ROOT}/hooks/projects-root-guard.ps1"',
                            "matcher": "Write|Edit|NotebookEdit|Bash|PowerShell|Shell",
                        }
                    ],
                    "stop": [
                        {
                            "command": 'powershell -File "${CURSOR_PLUGIN_ROOT}/hooks/projects-root-report.ps1"',
                            "loop_limit": 1,
                        }
                    ],
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )


def _write_good(root: Path):
    (root / ".claude-plugin").mkdir()
    (root / ".cursor-plugin").mkdir()
    skill = root / "skills" / "demo"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("demo\n", encoding="utf-8")
    (root / ".claude-plugin" / "plugin.json").write_text(
        json.dumps(chk.CLAUDE_PLUGIN) + "\n", encoding="utf-8"
    )
    (root / ".cursor-plugin" / "plugin.json").write_text(
        json.dumps(chk.CURSOR_PLUGIN) + "\n", encoding="utf-8"
    )
    (root / ".cursor-plugin" / "marketplace.json").write_text(
        json.dumps(chk.CURSOR_MARKETPLACE) + "\n", encoding="utf-8"
    )
    _write_hooks(root)


def test_repo_manifests_pass():
    assert chk.check(ROOT) == []


def test_source_dot_resolves_to_root_manifest(tmp_path):
    _write_good(tmp_path)
    assert chk.resolve_source(tmp_path, ".") == tmp_path.resolve()
    manifest = tmp_path / ".cursor-plugin" / "plugin.json"
    assert manifest.is_file()
    assert chk.check(tmp_path) == []


def test_missing_source_directory_fails(tmp_path):
    _write_good(tmp_path)
    market = json.loads((tmp_path / ".cursor-plugin" / "marketplace.json").read_text())
    market["plugins"][0]["source"] = "not-a-plugin"
    (tmp_path / ".cursor-plugin" / "marketplace.json").write_text(json.dumps(market) + "\n")
    errors = chk.check(tmp_path)
    assert any("not-a-plugin" in e for e in errors)


def test_version_field_fails(tmp_path):
    _write_good(tmp_path)
    plugin = json.loads((tmp_path / ".claude-plugin" / "plugin.json").read_text())
    plugin["version"] = "1.0.0"
    (tmp_path / ".claude-plugin" / "plugin.json").write_text(json.dumps(plugin) + "\n")
    errors = chk.check(tmp_path)
    assert any("version" in e for e in errors)


def test_parent_source_is_rejected(tmp_path):
    with pytest.raises(ValueError):
        chk.resolve_source(tmp_path, "..")


def test_coordinator_kit_is_picked_up_with_the_other_skills():
    folders = sorted(
        p.name
        for p in (ROOT / "skills").iterdir()
        if p.is_dir() and (p / "SKILL.md").is_file()
    )
    assert "coordinator-kit" in folders
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert f"all {len(folders)} are his" in readme
    cursor = json.loads((ROOT / ".cursor-plugin" / "plugin.json").read_text(encoding="utf-8"))
    assert cursor["skills"] == "./skills/"
    excluded = set()
    for line in (ROOT / "skills" / "EXCLUDE.txt").read_text(encoding="utf-8").splitlines():
        name = line.split("#", 1)[0].strip()
        if name:
            excluded.add(name)
    assert "coordinator-kit" not in excluded
    packer = (ROOT / "scripts" / "pack-skill-zips.py").read_text(encoding="utf-8")
    assert "SKILL.md" in packer and "EXCLUDE.txt" in packer


def test_workflow_runs_validate_without_strict():
    yml = (ROOT / ".github" / "workflows" / "plugin-validate.yml").read_text(encoding="utf-8")
    code = [line.strip() for line in yml.splitlines() if not line.strip().startswith("#")]
    assert "claude plugin validate ." in code
    assert not any("--strict" in line for line in code)
    auto = (ROOT / "automation.yml").read_text(encoding="utf-8")
    assert "id: plugin-validate" in auto
    assert ".github/workflows/plugin-validate.yml" in auto
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    assert ".claude-plugin/plugin.json" in agents
    assert ".cursor-plugin/marketplace.json" in agents
    contributing = (ROOT / "CONTRIBUTING.md").read_text(encoding="utf-8")
    assert ".claude-plugin/" in contributing
    assert ".cursor-plugin/" in contributing
