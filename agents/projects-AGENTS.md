# Shared rules for every agent working under this projects folder

Claude, Cursor, Grok Bot and any other agent read this file. A repo's `AGENTS.md`, decisions, `CONTRIBUTING.md`, hooks, and CI add to it. Their rules and decisions still bind. Only an older agent doc's layout yields to the workstation-core template.

## 0. Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md`), (2) its binding rules / decisions file if it has one, (3) the project's live state in
the shared store, `<Projects>\_claude\Claude Projects\Working Memory\memory\<project>\`: `STATE.md`
and this branch's `STATE-<slug>.md` (WSL: that same folder under the Windows Projects root), (4) that
folder's `INDEX.md` (preference and fact notes). If a rule or note already answers a question, act on
it and cite it - never ask the maintainer something the rules already answer. Claude desktop online
Memory is a separate account-level list and is not this store.

## 0b. Where things live
- **Repo (git):** the router `AGENTS.md`, SPEC, DECISIONS, rules and data.
- **Store project folder:** live state (`STATE.md`, `STATE-<slug>.md`, `BACKLOG.md`, `archives\`) plus the preference and fact notes listed in `INDEX.md`. Never committed.
- **`TASK.md`:** the branch checklist at the worktree root, git-ignored.
- **At 80% context:** run the `state-closeout` skill (closeout mode). On-demand handoff: `state-closeout handoff`. Handoffs never go in the repo or a `handoffs\` folder.
- **Store unreachable** (PC offline, cloud session): work from committed docs only.

## 1. Follow each repo's own rules
Before changing anything in any repo, read and follow that repo's `AGENTS.md`, decisions,
`CONTRIBUTING.md`, hooks (`.pre-commit-config.yaml`, `core.hooksPath`, `.git/hooks`), and CI
workflows (`.github/workflows`). Their rules and decisions still bind. Never bypass a hook or
gate without the owner's explicit yes: no `--no-verify`, no skipping CI, and no direct pushes of
generated or bot-owned files (let the workflow that owns a file regenerate it). If a planned step
would bypass one, stop and ask.

If an older agent doc's layout differs from the workstation-core template (`AGENTS.md` as the
router, state-init profiles, store STATE), that layout is migrated into the template by
session-start, state-init, or repo-cleanup, keeping every rule. A layout difference is not a
blocker or a reason to stop.

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

## 5. Fusion
Fusion work uses Autodesk's official Fusion MCP servers (exact links and config line coming later).

## 5b. harness.design lock (one agent drives the harness.design desktop app at a time)
One lock per PC: `%LOCALAPPDATA%\Workstation\harness-design.lock` (outside every repo); log `harness-design-lock.log` beside it.
Script, with `-Name harness-design`: `<Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1` (call it with `powershell -NoProfile -ExecutionPolicy Bypass -File`).
Desktop app only: an agent clicking the app (computer-use) or Dan driving it by hand. The harness.design MCP cloud tools do not need this lock. An agent delete is the exception: it goes through the desktop app and needs the lock.
harness.design autosaves to the cloud, so unsaved work cannot be detected. `check` clears a lock only when the last check-in was 15+ minutes ago AND `harness.design.exe` (`%LOCALAPPDATA%\Programs\harness-design-desktop\harness.design.exe`) has no open editor. Window titles are conservative: any visible title other than the app name counts as an open editor, because the Windows title text was not confirmed (macOS lists windows by harness name). Otherwise it says ask the owner. Never delete the lock file by hand, and never clear a lock on time alone.
`-Files` is harness document ids or titles (PowerShell passes `rBjB,QjYZ` as two values).
- Acquire before using the desktop app (one line): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1 acquire -Name harness-design -Holder <your name> -Kind claude-code|cursor|remote -Repo <repo path> -Files rBjB,QjYZ`
- Check in at least every 10 min while working (one line): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1 checkin -Name harness-design -Holder <your name>`
- Release when done (one line): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\fusion-lock\fusion-lock.ps1 release -Name harness-design -Holder <your name>`
- Claude Code / Cursor may add `-StartPinger` on acquire (a hidden pinger checks in every 5 min). Remote agents run the check-in line themselves.
- To confirm the harness.design lock is installed for every account on this PC (read-only, PASS/FAIL, nonzero if anything fails): `powershell -NoProfile -ExecutionPolicy Bypass -File <Projects>\active\workstation\workstation\health\workstation-status.ps1 -Locks`
