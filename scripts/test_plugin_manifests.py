"""Plugin manifests: no version field, and Cursor source "." resolves to the repo root."""
import json
import os
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
    (root / ".claude-plugin" / "marketplace.json").write_text(
        json.dumps(chk.CLAUDE_MARKETPLACE) + "\n", encoding="utf-8"
    )
    (root / ".cursor-plugin" / "plugin.json").write_text(
        json.dumps(chk.CURSOR_PLUGIN) + "\n", encoding="utf-8"
    )
    (root / ".cursor-plugin" / "marketplace.json").write_text(
        json.dumps(chk.CURSOR_MARKETPLACE) + "\n", encoding="utf-8"
    )
    _write_hooks(root)
    _write_rules(root)


GOOD_RULE = "---\ndescription: demo\nalwaysApply: true\n---\n\n# Rule\n"


def _write_rules(root: Path, text: str = GOOD_RULE):
    rules = root / "rules"
    rules.mkdir(exist_ok=True)
    (rules / "sot-permission.mdc").write_text(text, encoding="utf-8")


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


def test_missing_always_on_rule_fails(tmp_path):
    _write_good(tmp_path)
    (tmp_path / "rules" / "sot-permission.mdc").unlink()
    errors = chk.check(tmp_path)
    assert any("sot-permission.mdc is missing" in e for e in errors)


def test_rule_without_always_apply_fails(tmp_path):
    _write_good(tmp_path)
    _write_rules(tmp_path, GOOD_RULE.replace("alwaysApply: true", "alwaysApply: false"))
    errors = chk.check(tmp_path)
    assert any("alwaysApply: true" in e for e in errors)


def test_manifest_without_rules_path_fails(tmp_path):
    _write_good(tmp_path)
    plugin = dict(chk.CURSOR_PLUGIN)
    plugin.pop("rules")
    (tmp_path / ".cursor-plugin" / "plugin.json").write_text(json.dumps(plugin) + "\n")
    errors = chk.check(tmp_path)
    assert any("rules" in e for e in errors)


def test_repo_sot_rule_asks_for_the_owners_yes():
    text = (ROOT / "rules" / "sot-permission.mdc").read_text(encoding="utf-8")
    assert "explicit yes" in text
    assert "report every changed value" in text


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
    assert "debug-root-cause" in folders
    assert "review-feedback" in folders
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert f"all {len(folders)} are his" in readme
    assert "| debug-root-cause |" in readme
    assert "| review-feedback |" in readme
    contributing = (ROOT / "CONTRIBUTING.md").read_text(encoding="utf-8")
    assert "debug-root-cause" in contributing
    assert "review-feedback" in contributing
    cursor = json.loads((ROOT / ".cursor-plugin" / "plugin.json").read_text(encoding="utf-8"))
    assert cursor["skills"] == "./skills/"
    excluded = set()
    for line in (ROOT / "skills" / "EXCLUDE.txt").read_text(encoding="utf-8").splitlines():
        name = line.split("#", 1)[0].strip()
        if name:
            excluded.add(name)
    assert "coordinator-kit" not in excluded


def test_claude_marketplace_is_the_only_catalog():
    market = json.loads(
        (ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8")
    )
    assert market == chk.CLAUDE_MARKETPLACE
    assert market["name"] == "workstation-plugins"
    assert [entry["name"] for entry in market["plugins"]] == ["workstation-core"]
    assert market["plugins"][0]["source"] == "./"
    cursor = json.loads(
        (ROOT / ".cursor-plugin" / "marketplace.json").read_text(encoding="utf-8")
    )
    assert cursor["plugins"] == [{"name": "workstation-core", "source": "."}]
    assert all(isinstance(entry["source"], str) for entry in cursor["plugins"])
    names = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".venv", "node_modules"}]
        if "marketplace.json" in filenames:
            names.append(Path(dirpath, "marketplace.json").relative_to(ROOT).as_posix())
    assert sorted(names) == sorted(chk.MARKETPLACE_FILES)


def test_extra_marketplace_file_fails(tmp_path):
    _write_good(tmp_path)
    extra = tmp_path / "other" / "marketplace.json"
    extra.parent.mkdir()
    extra.write_text("{}\n", encoding="utf-8")
    errors = chk.check(tmp_path)
    assert any("extra marketplace catalog" in e for e in errors)


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
    assert ".claude-plugin/marketplace.json" in agents
    assert ".cursor-plugin/marketplace.json" in agents
    contributing = (ROOT / "CONTRIBUTING.md").read_text(encoding="utf-8")
    assert ".claude-plugin/" in contributing
    assert ".cursor-plugin/" in contributing
