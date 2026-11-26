# Projects root - agent guide

**Root:** `{{PROJECTS_ROOT}}`

This is the one guide for the Projects root, for Claude Code, Cursor and any other agent that reads `AGENTS.md`. There is no root `CLAUDE.md`: Claude Code (2.1.281 or newer) reads this file, and a `CLAUDE.md` or `CLAUDE.local.md` could hide it. If any `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` is found in a repo, fold its content into that repo's `AGENTS.md` (keep every rule, drop exact duplicates), then delete the CLAUDE file, in the same PR. That fold-and-delete is pre-approved by the user.

All durable work for this PC lives under this root. Prefer paths here over Downloads, Desktop or ad-hoc temp folders.

## Layout

```
Projects/
  AGENTS.md          this file (orientation + rules for Claude, Cursor and other agents)
  active/            all live projects, including finished ones (the workstation repo clone too: its
                     workstation/ folder is the Workstation toolkit, run straight from the clone)
  _archive/          obsolete projects only, in dated subfolders (do not treat as active)
  _scratch/          throwaway experiments; OK to clean
  _claude/           shared Claude memory
  _refs/             optional: reference material, specs, vendor docs, third-party clones
```

### `active/`
Every live project, whether in progress or finished. If `active/README.md` exists, it lists the projects and their git/remote status.

### `_archive/`
Obsolete projects only: superseded, abandoned or no longer relevant, in dated subfolders (`_archive\<yyyy-MM-dd>\<project>`). Completed work stays in `active/`. Do not resume work here without moving the folder back to `active/`.

### `_scratch/`
Ephemeral. Fine to delete when stale. Never commit anything from it.

### `_refs/` (optional)
Read-only-ish references (datasheets, clones used as examples, design notes). Do not put new product work here.

## Layout rules

If this root also has `.cursor\rules\projects-structure.mdc`, keep the same rules there. If you change one, change both.

1. **Live projects go in `active\<project>\`.** No project folders directly under `Projects\`. The only things allowed at the root are `active\`, `_archive\`, `_scratch\`, `_claude\`, the optional `_refs\`, `AGENTS.md` and `.cursor\`.
2. **`_archive\` is only for obsolete work** (superseded, abandoned or no longer relevant). Finished or completed projects stay in `active\`. Ask the user before moving anything into `_archive\`, and never keep the same project in both `active\` and `_archive\`.
3. **Throwaway work goes in `_scratch\`** (or the project's own `_scratch\`). Do not create new root folders, `*_tmp` folders or loose files at the root.
4. **Third-party clones and vendor docs go in `_refs\`** or a clearly named folder inside the project that uses them.
5. **Keep `active\README.md` current if you use one.** When you add, rename, move or archive a project, update it in the same change.
6. **Do not recreate missing paths.** If a path under `Projects\` no longer exists (for example from Cursor's recent list or an old note), find where the project lives now under `active\` instead of creating an empty folder there.
7. **Git:** not every project is a git repo. Plain folders are fine and stay local-only. Never turn a project into a git repo unless the user asks. Pull and push one repo at a time, by hand or through the agent that owns it (no batch pull/push scripts); pulls are fast-forward only; never force-push.
8. **Do not delete project files** unless the user explicitly asks.
9. **Follow each repo's own rules.** Before changing anything in a project, read and follow its `AGENTS.md`, decisions, `CONTRIBUTING.md`, hooks (`.pre-commit-config.yaml`, `core.hooksPath`, `.git/hooks`), and CI workflows. Their rules and decisions still bind. Never bypass a hook or gate without the user's explicit yes: no `--no-verify`, and no direct pushes of generated or bot-owned files. If an older agent doc's layout differs from the workstation-core template, that layout is migrated into the template, keeping every rule. A layout difference is not a blocker or a reason to stop. These root rules only cover where things live.

<!-- shared-memory:v1 -->
## Memory (`_claude\`)

Two stores, different jobs. Local Working Memory at `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\` is the shared notes store for Claude Code, Cowork and Cursor. It holds preference and fact notes only (no project status); live project state lives in each repo. Claude account Memory (claude.ai / Your Claude → Memory) is a separate, allowed store for general / non-project prefs. Duplicates are OK; never sync either way; never treat either store as the project source of truth: that is the repo.

Claude Code reaches the local store through the junction `{{USERPROFILE}}\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory\`. Never create a second local memory folder or replace the junction. A leftover `~\.claude\working-memory` junction is harmless and is not used. Do not use `project_memory_read` / `project_memory_write` for project memory. **Read before you ask:** before starting work or asking the maintainer anything, read in order (1) the repo's agent guide, (2) its binding rules / decisions file if it has one, (3) the project's live state in the repo: `STATE.md` and this branch's `STATE-<slug>.md` at the repo root, (4) the notes in `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\<project>\INDEX.md`; if a rule or note already answers a question, act on it and cite it. Every entry an agent writes there is signed. Cursor edits the live store, signs every entry, and updates the matching `MEMORY.md` / project `INDEX.md`. **Tiers (decision 2026-11-22):** the repo (git) holds the router `AGENTS.md`, SPEC, DECISIONS, rules, data and live state: `STATE.md` (trunk; the coordinator's), `STATE-<slug>.md` (one per branch, committed on that branch), `BACKLOG.md` and `archives/`, all at the repo root. The store's project folder holds notes only (preferences, machine facts, gotchas) listed in its `INDEX.md`: no project status, rebuildable. `TASK.md` is the branch checklist at the worktree root, git-ignored. Each fact is written once. At 80% context, run the `state-closeout` skill (closeout mode). On-demand handoff: `state-closeout handoff`. No `HANDOFF` or `handoffs/` files; `STATE-<slug>.md` is the handoff. A PR's last commit archives the state file (`state_manager.py archive-branch`). Store unreachable (PC offline, cloud session): live state is still in the repo; only notes are missing.

Inside the store, `MEMORY.md` is the no-project index (general notes, one line per project). Each project has a subfolder with an `INDEX.md`, named after its `active\` folder (`_archive\<project>\` for archived ones, `_unassigned\` for chats with no project yet; move a note to its project folder when the chat gets one). Follow a pointer one step only, never a pointer inside a file reached through a pointer. Each agent signs every entry (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, ...`, `-- Cursor, ...`). Each `active\<project>\` has a one-line pointer to its memory folder in that project's `AGENTS.md`. Do not create a `CLAUDE.md` or `CLAUDE.local.md` for the pointer. Memory store files are never committed.

## Workstation toolkit (`{{TOOLKIT_PATH}}\`)

Operator scripts for this PC. **Git is the primary bridge** (commit + push remotely, then `git pull --ff-only` in that one repo on this PC). The scripts run straight from the workstation repo clone (keep that clone on `main`); there is no installed copy under the Projects root. Health check: `{{TOOLKIT_PATH}}\health\workstation-status.ps1`. Desktop Commander is manual only (one phone remote per PC, no sign-in item): Start, Stop, and status links in the clone's `shortcuts\` folder. Runtime files live in `%LOCALAPPDATA%\Workstation\`, never in the clone. Nothing auto-starts. See `{{TOOLKIT_PATH}}\README.md`.

```powershell
powershell -File "{{TOOLKIT_PATH}}\{{TOOLKIT_STATUS}}"
# pull/push: one repo at a time, e.g. git -C <repo> pull --ff-only
```

- **Cursor web / Claude Code cloud:** commit + push to GitHub (branch + PR), then `git pull --ff-only` in that repo on this PC.
- **Local Cursor / Claude desktop:** edit under `active\` directly; push that repo's branch by hand and open a PR when remotes should see it.
<!-- /shared-memory:v1 -->
