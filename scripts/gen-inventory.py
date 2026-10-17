"""Generate INVENTORY.md from workstation.lock.yaml (run from the repo root)."""
from pathlib import Path

import yaml

root = Path(__file__).resolve().parent.parent
lock = yaml.safe_load((root / "workstation.lock.yaml").read_text(encoding="utf-8"))
out = ["# Inventory (generated from workstation.lock.yaml - do not edit)", ""]
out += ["## Repos (cloned, never copied; commit `follow` = tracks its ref, pulled ff-only after merges)", "", "| Repo | URL | Ref | Commit | Setup |", "|---|---|---|---|---|"]
for name, r in (lock.get("repos") or {}).items():
    out.append(f"| {name} | {r.get('url')} | {r.get('ref')} | {r.get('commit')}{' (last checked ' + str(r['last_checked']) + ')' if r.get('last_checked') else ''} | {r.get('setup')} |")
out += ["", "## Upstream tools (pinned)", "", "| Tool | Version / pins |", "|---|---|"]
for name, t in (lock.get("upstream") or {}).items():
    if isinstance(t, dict) and "version" in t:
        v = t["version"]
    else:
        v = ", ".join(f"{k} {val}" for k, val in (t or {}).items()) if isinstance(t, dict) else t
    out.append(f"| {name} | {v} |")
out += ["", "## Outside dependencies (listed only; not installed or copied)", "", "| Item | Where | Version | How to enable |", "|---|---|---|---|"]
for name, d in (lock.get("outside_dependencies") or {}).items():
    where = d.get("url") or d.get("package") or d.get("source")
    ver = d.get("version") or (d.get("claude_desktop_extension") or {}).get("version", "-")
    out.append(f"| {name} | {where} | {ver} | {d.get('enable', '')} |")
out += ["", "## Skills sources", ""] + [f"- {s['from']}: `{s['dir']}/`" for s in lock.get("skills") or []]
out += ["", f"Models folder: `{lock.get('models_dir')}` (created by setup if missing, add-only).", ""]
out += ["CAD models included: none. Patches: " + (str(len(lock.get('patches') or [])) or "0") + ".", ""]
if lock.get("open_items"):
    out += ["## Open items", ""] + [f"- {i}" for i in lock["open_items"]] + [""]
(root / "INVENTORY.md").write_text("\n".join(out), encoding="utf-8", newline="\n")
print("wrote INVENTORY.md")
