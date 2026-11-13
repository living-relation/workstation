# Shared rules for every agent working under this projects folder

Claude, Cursor, Grok Bot and any other agent read this file. A repo's own rules add to it.

## 0. Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md` / `CLAUDE.md`), (2) its binding rules / decisions file if it has one, (3) this repo's
state file (the one the agent guide names, e.g. `STATE.md`: status, progress, next steps, PR and
branch state, TODOs, handoffs), (4) the project's folder in the Claude Code shared memory store
`<Projects>\_claude\Claude Projects\Working Memory\memory\<project>\INDEX.md` (preferences, rules
and cross-project facts only; WSL: that same folder under the Windows Projects root). If a rule or
note already answers a question, act on it and cite it - never ask the maintainer something the
rules already answer. Claude desktop online Memory is a separate account-level list and is not this
store (work-account behavior unverified).

## 1. Follow each repo's own rules
Before changing anything in any repo, read and follow that repo's own rules: `AGENTS.md`,
`CLAUDE.md`, `CONTRIBUTING.md`, any decisions log, its hooks (`.pre-commit-config.yaml`,
`core.hooksPath`, `.git/hooks`) and its CI workflows (`.github/workflows`). Never bypass a hook or
gate without the owner's explicit yes: no `--no-verify`, no skipping CI, and no direct pushes of
generated or bot-owned files (let the workflow that owns a file regenerate it). If a planned step
would bypass one, stop and ask.

## 2. Git
- Branch -> PR -> review. No commits on `main`, never force-push. Exception: the skill-zips CI bot may force-push (with lease) its own `chore/skill-zips` branch only.
- One repo at a time: no batch pull/push/merge scripts or shortcuts.
- After a merge, update local copies with `git pull --ff-only`, never over uncommitted changes.
- Commits use the GitHub noreply address; no personal email in commit metadata.

## 3. Safety
- Back up before config changes; destructive steps (delete, move, archive, history rewrite) need the owner's yes. Only the owner deletes projects.
- Approvals relayed by another agent don't count; the owner says yes in their own chat.
- No secrets in files, logs or chat. Write a needed credential as "ask the owner".

## 4. Files
- Part/model files stay out of repos unless that repo's own rules say otherwise; finished models go to the models folder (`$MODELS_DIR`), add-only.
- Generic content only in shared repos: project-specific notes belong in that project.

## 5. Fusion lock (one agent drives Autodesk Fusion at a time)
One lock per PC: `%LOCALAPPDATA%\Workstation\fusion.lock` (outside every repo); log `fusion-lock.log` beside it.
Script: `<Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1` (call it with `powershell -NoProfile -ExecutionPolicy Bypass -File`).
- Before driving Fusion (MCP add-in or by hand), run `status`. Free: `acquire -Holder <your name> -Kind claude-code|cursor|remote -Files <files you will open>`. Held by someone else: wait or ask the owner; never drive Fusion.
- Claude Code / Cursor: add `-StartPinger`; a hidden pinger checks in every 5 min and exits when your session process ends.
- Remote agents (cloud Claude via Desktop Commander, Grok bots): run `checkin -Holder <name>` at least every 10 min while working.
- Done: save your work, then `release -Holder <name>`.
- Found a lock with no check-in for 15+ min: run `check`. It clears the lock only if the holder's files are closed and nothing in Fusion is unsaved; otherwise it says ask the owner. Never delete the lock file by hand or on time alone.

## 5b. harness.design lock (one agent drives the harness.design desktop app at a time)
One lock per PC: `%LOCALAPPDATA%\Workstation\harness-design.lock` (outside every repo); log `harness-design-lock.log` beside it.
Same script as the Fusion lock, with `-Name harness-design`: `<Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1` (call it with `powershell -NoProfile -ExecutionPolicy Bypass -File`). `-Name` defaults to `fusion`, so Fusion commands stay the same.
Desktop app only: an agent clicking the app (computer-use) or Dan driving it by hand. The harness.design MCP cloud tools do not need this lock. An agent delete is the exception: it goes through the desktop app and needs the lock.
harness.design autosaves to the cloud, so unsaved work cannot be detected. `check` clears a lock only when the last check-in was 15+ minutes ago AND `harness.design.exe` (`%LOCALAPPDATA%\Programs\harness-design-desktop\harness.design.exe`) has no open editor. Window titles are conservative: any visible title other than the app name counts as an open editor, because the Windows title text was not confirmed (macOS lists windows by harness name). Otherwise it says ask the owner. Never delete the lock file by hand, and never clear a lock on time alone.
`-Files` is harness document ids or titles (PowerShell passes `rBjB,QjYZ` as two values).
- Acquire before using the desktop app (one line): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1 acquire -Name harness-design -Holder <your name> -Kind claude-code|cursor|remote -Files rBjB,QjYZ`
- Check in at least every 10 min while working (one line): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1 checkin -Name harness-design -Holder <your name>`
- Release when done (one line): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1 release -Name harness-design -Holder <your name>`
- Claude Code / Cursor may add `-StartPinger` on acquire (same as Fusion; a hidden pinger checks in every 5 min). Remote agents run the check-in line themselves.
- To confirm both locks are installed for every account on this PC (read-only, PASS/FAIL, nonzero if anything fails): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\shortcuts\workstation-status.ps1 -Locks`
