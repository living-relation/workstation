#!/usr/bin/env python3
"""Numbered PC-setup phases. setup_guide.py prints them. setup_verify.py checks them.

SETUP-PROMPT.txt is only a pointer to the guide. The text here is the setup.
"""
import json
import os
from pathlib import Path

# Stable ids. setup_verify.py fails if any of these is missing from the phase log.
PHASES = (
    {
        "n": "0",
        "title": "Find the package",
        "body": (
            "The package is the workstation repo clone, normally <Projects>\\active\\workstation "
            "(clone it there if it is missing; ask for the URL). The Workstation toolkit runs straight "
            "from this clone, so it must stay on main. Find it (ask if you cannot). Work on this PC, as "
            "the signed-in Windows user. Do not use an elevated (admin) shell; the owner runs the one "
            "admin command."
        ),
    },
    {
        "n": "1",
        "title": "Read the PC notes and the docs",
        "body": (
            "FIRST: if REVIEW-NOTES.md exists in the package folder, read all of it before anything else. "
            "It holds notes for one specific PC (for example a different Projects folder, extra clean-up "
            "steps, and a suggested order). If it is for this PC, its notes override the defaults below, "
            "and every extra required step it lists is part of this setup. If you are not sure it is for "
            "this PC, ask.\n"
            "Then read README.md, REORGANIZE.md, MIGRATION.md and instructions\\README.md in that folder."
        ),
    },
    {
        "n": "2",
        "title": "Preflight",
        "body": (
            "In a normal PowerShell, from the package folder, run\n"
            "powershell -NoProfile -ExecutionPolicy Bypass -File .\\preflight.ps1\n"
            "It changes nothing and writes preflight-report-<time>.txt. Show the report as a short list: "
            "every CONFLICT and WARN with what it means, then the counts. For each CONFLICT, propose how "
            "to resolve it and wait for a decision. Change nothing yourself unless told. Re-run preflight "
            "until it shows no CONFLICT, or until told to accept a conflict.\n"
            "If the Projects folder is not %USERPROFILE%\\Projects (REVIEW-NOTES.md may say), ask and use "
            "-ProjectsRoot for every script."
        ),
    },
    {
        "n": "3",
        "title": "Dry run",
        "body": (
            "powershell -NoProfile -ExecutionPolicy Bypass -File .\\install.ps1 -WhatIf\n"
            "(it runs preflight again first). Show what it would create, change, and any warnings. "
            "Change nothing yet. A dry run does not run the claude commands and does not paste instructions."
        ),
    },
    {
        "n": "4",
        "title": "Back up memories",
        "body": (
            "Back up memories BEFORE anything else changes: do MIGRATION.md step a (every Windows account "
            "on this PC, memory folders only). Verify the file counts and show the totals."
        ),
    },
    {
        "n": "5",
        "title": "Reorganize",
        "body": (
            "Show the plan from REORGANIZE.md step 1 (inventory -> proposed moves). Move nothing until it "
            "is approved. Then do the moves that were approved and the rest of REORGANIZE.md (steps 2 to 5). "
            "Step 5: if the Projects root has a CLAUDE.md, fold it into AGENTS.md (the root is not a git "
            "repo; check first, back up first, keep every rule, drop exact duplicates, then delete the root "
            "CLAUDE.md). Do not create a CLAUDE.md or CLAUDE.local.md in a repo or at the Projects root. "
            "The one-line project memory pointer goes in that project's AGENTS.md. If REORGANIZE.md or "
            "MIGRATION.md says to put that pointer in CLAUDE.md or CLAUDE.local.md, use AGENTS.md instead. "
            "Then list every CLAUDE.md, .claude\\CLAUDE.md, and CLAUDE.local.md in active\\ projects and "
            "repos as a table. The workstation-core template is the target: fold each into that project's "
            "AGENTS.md (keep every rule, drop exact duplicates), then delete the CLAUDE file. That fold is "
            "pre-approved. Every rule is kept. A layout difference is not a blocker and not a reason to "
            "stop. The rules and decisions in those files still bind. Show the plan before you write over "
            "an AGENTS.md. In a git repo, the owner makes the commit, and nothing is pushed. Leave "
            "%USERPROFILE%\\.claude\\CLAUDE.md alone."
        ),
    },
    {
        "n": "6",
        "title": "Install",
        "body": (
            "Run install.ps1 for real (same parameters as the dry run). install.cmd runs that same script. "
            "Add -AcceptConflicts only if the remaining conflicts in phase 2 were accepted. It copies no "
            "toolkit files (the toolkit runs from the clone's workstation\\ folder); it writes "
            "%LOCALAPPDATA%\\Workstation\\workstation.json (the Projects root), creates the manual Desktop "
            "Commander shortcuts (Start, Stop, status) and the orphan tool in the package's shortcuts\\ "
            "folder, installs no hooks (the workstation-core plugin carries them), merges Claude Code MCP "
            "connectors into ~\\.claude.json and installs official-marketplace plugins from "
            "claude\\plugins.json, and does not copy skills into ~\\.claude\\skills (the workstation-core "
            "plugin delivers them). On a real run it opens https://claude.ai/customize/plugins and prints "
            "the clicks for Claude desktop and Cowork: Customize, Plugins, Add, Add marketplace, Add from "
            "a repository, paste living-relation/workstation, turn Sync automatically on, turn on "
            "workstation-core. Updates later arrive automatically after merges to main.\n"
            "On a real run it also runs exactly these two commands for Claude Code, in this order:\n"
            "claude plugin marketplace add living-relation/workstation\n"
            "claude plugin install workstation-core@workstation-plugins\n"
            "If the claude CLI is missing, it skips those two and continues. It never uninstalls or "
            "disables anything. Refresh and update stay manual (INSTALL.md, Claude Code section).\n"
            "The Cursor copy still updates by running the installer again and reloading Cursor. It also "
            "copies this repo to %USERPROFILE%\\.cursor\\plugins\\local\\workstation-core. Reload Cursor "
            "after that. A dry run opens nothing, copies nothing, and does not run the claude commands. "
            "Stop and wait until the plugin is confirmed on. It adds no autostart (nothing starts at "
            "sign-in). For github it reads GITHUB_PERSONAL_ACCESS_TOKEN (or GITHUB_TOKEN) from env, or "
            "prompts; empty skips that server. Show the summary and any warnings.\n"
            "At the end, install.ps1 runs Health check (-NoPause) and prints its FAIL / WARN counts. "
            "Then, unless -Quiet, it runs the paste helper (phase 9). FAIL or WARN lines are expected at "
            "this point; the phases below clear them. Exit code 0 is expected. Exit code 1 (error) or 2 "
            "(preflight conflict) is not: show what went wrong."
        ),
    },
    {
        "n": "7",
        "title": "Old local setup",
        "body": (
            "Manual, by the owner, only if this PC had the previous toolkit: give cleanup-legacy.ps1 "
            "-WhatIf first. The owner reviews it. Then the owner runs it. The firewall step needs an admin "
            "window; if the script says it skipped that rule, the owner runs that one step. Wait for "
            "\"done\". Skip this phase on a PC that never had the old setup. There is no memory sync task "
            "(Cursor edits the live memory store)."
        ),
    },
    {
        "n": "8",
        "title": "Memory migration",
        "body": (
            "Do MIGRATION.md steps b to e. Show the plan and wait for an OK before merging anything. "
            "Give the transcript-only findings for review."
        ),
    },
    {
        "n": "9",
        "title": "Paste instructions",
        "body": (
            "install.ps1 does this at the end unless it was started with -Quiet. One file at a time it "
            "copies the text to the clipboard, opens the file in Sublime Text "
            "(C:\\Program Files\\Sublime Text\\subl.exe, or notepad if that program is missing), prints "
            "where to paste, and waits for Enter.\n"
            "instructions\\instructions-for-claude.md -> Claude Desktop > Settings > General > "
            "Instructions for Claude\n"
            "instructions\\cowork-global-instructions.md -> Cowork Global instructions, only if that box "
            "exists. It no longer points at a local memory folder. Do not re-run preflight to look for a "
            "working-memory line. Preflight does not check it.\n"
            "instructions\\cursor-user-rules.md -> Cursor Settings > Rules > User Rules\n"
            "If install was started with -Quiet, run scripts\\paste-instructions.ps1 yourself. Never edit "
            "these instruction texts or Claude's files. Wait until each paste is done."
        ),
    },
    {
        "n": "10",
        "title": "Stranded desktop memory",
        "body": (
            "Manual, by the owner: Cowork / Chat no longer write local memory files (personal account "
            "verified 2026-11-03, Store app 4.4212.0.0, Unified Claude; work account unverified). Tell "
            "the owner that old local Cowork notes can be copied into the Claude Code store or brought in "
            "with the app's Import memory button. A leftover %USERPROFILE%\\.claude\\working-memory "
            "junction is harmless; do not delete it. Old per-project Cowork memory lines are obsolete; "
            "the owner may remove them. Do not point a Cowork files location at the store. Wait for "
            "\"done\"."
        ),
    },
    {
        "n": "11",
        "title": "Prerequisites and sign-ins",
        "body": (
            "Manual, by the owner: using the install results and Health check, say what is missing and "
            "give the exact steps for each, then wait for \"done\":\n"
            "- git, and the GitHub sign-in (per-repo pull/push needs git);\n"
            "- the Cursor agent sign-in (\"agent login\");\n"
            "- Claude Code sign-in (\"claude\") and the Claude desktop app sign-in;\n"
            "- Python 3, if install skipped the Cursor 80% handoff hook because Python was missing "
            "(then re-run install.ps1 so the hook is installed)."
        ),
    },
    {
        "n": "12",
        "title": "PC-specific notes",
        "body": (
            "Any other required step that REVIEW-NOTES.md lists for this PC and that is not done yet "
            "(for example removing old automations): do it as REVIEW-NOTES.md says, with approval where "
            "it asks for it."
        ),
    },
    {
        "n": "13",
        "title": "Health check",
        "body": (
            "LAST check: run\n"
            "powershell -NoProfile -ExecutionPolicy Bypass -File "
            "\"<package folder>\\workstation\\health\\workstation-status.ps1\" -NoPause\n"
            "(-NoPause only reports; it never prompts or changes anything). Count the [FAIL] and [WARN] "
            "lines. Setup is finished ONLY when there are 0 [FAIL] and 0 [WARN]. For each one left, say "
            "what it means and how to fix it, fix it with an OK (or say what the owner must do), and run "
            "the check again."
        ),
    },
    {
        "n": "14",
        "title": "Report",
        "body": (
            "Finish with a short report: each numbered phase with done / not done, the final Health check "
            "counts (must be 0 FAIL, 0 WARN), what is left for the owner, and any warnings. Do not call "
            "setup finished while any phase is not done. Then run scripts/setup_verify.py. It fails if "
            "any phase was not recorded."
        ),
    },
)

ALWAYS = """\
Notes:
- App startup switches belong to the owner: never turn one on or off. Report them only. Desktop Commander must not start at sign-in.
- Say which active projects have no git remote (pull/push is one repo at a time, by hand).

Always:
- Never commit memory store files to git. The one-line project memory pointer goes in the project's AGENTS.md. Do not create a CLAUDE.md or CLAUDE.local.md for it.
- Never run git init on a plain project folder unless asked.
- Never force-push.
- Never copy, ship, or print secrets (keys, credentials, .env files, anything that looks like an API key).
- Never delete, overwrite, or move anything without approval. Back up before you change a settings file.
- Nothing is scheduled. No startup task.
"""


def phase_ids():
    return tuple(item["n"] for item in PHASES)


def default_log_path():
    """Per-PC log. Not a repo file (a PC path must not be committed)."""
    local = os.environ.get("LOCALAPPDATA")
    if local:
        return Path(local) / "Workstation" / "setup-phases.json"
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg) if xdg else Path.home() / ".local" / "share"
    return base / "workstation" / "setup-phases.json"


def load_log(path):
    path = Path(path)
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    phases = data.get("phases") if isinstance(data, dict) else None
    if not isinstance(phases, dict):
        return {}
    return {str(key): str(value) for key, value in phases.items()}


def save_log(path, phases):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps({"phases": phases}, indent=2, sort_keys=True) + "\n"
    path.write_text(text, encoding="utf-8")


def missing(done):
    have = set(done)
    return [item for item in phase_ids() if item not in have]
