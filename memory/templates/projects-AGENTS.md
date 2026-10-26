# Projects root - agent guide

**Root:** `{{PROJECTS_ROOT}}`

This is the one guide for the Projects root, for Claude Code, Cursor and any other agent that reads `AGENTS.md`. There is no root `CLAUDE.md`: Claude Code reads this file because Project instructions is set to `claude-md-and-agents-md` in `~\.claude\settings.json`.

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
9. **Follow each repo's own rules.** Before changing anything in a project, read and follow its own `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, decisions log, hooks (`.pre-commit-config.yaml`, `core.hooksPath`, `.git/hooks`) and CI workflows. Never bypass a hook or gate without the user's explicit yes: no `--no-verify`, and no direct pushes of generated or bot-owned files. These root rules only cover where things live.

<!-- shared-memory:v1 -->
## Memory (`_claude\`)

`{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\` is the **ONE** memory store shared by Claude Code and Cowork.

Claude Code reaches it through the junction `{{USERPROFILE}}\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory\`. Never create another memory store. **Read before you ask:** before starting work or asking the maintainer anything, read in order (1) the repo's agent guide, (2) its binding rules / decisions file if it has one, (3) `%USERPROFILE%\.claude\working-memory\<project>\INDEX.md` (WSL: `/mnt/c/Users/<user>/.claude/working-memory/<project>/INDEX.md`), (4) the newest handoff note if one exists; if a rule or note already answers a question, act on it and cite it. Every entry an agent writes there is signed. Cursor edits the live store, signs every entry, and updates the matching `MEMORY.md` / project `INDEX.md`. Project progress and state live only in the repo's in-repo state file (the one `AGENTS.md` names, e.g. `STATE.md`). Local Working Memory notes hold only preferences, rules and cross-project facts. Each fact is written once; never duplicate it.

Inside the store, `MEMORY.md` is the no-project index (general notes, one line per project). Each project has a subfolder with an `INDEX.md`, named after its `active\` folder (`_archive\<project>\` for archived ones, `_unassigned\` for chats with no project yet; move a note to its project folder when the chat gets one). Follow a pointer one step only, never a pointer inside a file reached through a pointer. Each agent signs every entry (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, ...`, `-- Cursor, ...`). Each `active\<project>\` has a one-line pointer to its memory folder: in a git repo, put the pointer in `CLAUDE.local.md` (excluded via `.git/info/exclude`), never in tracked files; memory is never committed. Outside git, it goes in the project's `CLAUDE.md`.

## Workstation toolkit (`{{TOOLKIT_PATH}}\`)

Operator scripts for syncing remote Claude/Cursor sessions into local `active\` trees. **Git is the primary bridge** (commit + push remotely, then `git pull --ff-only` in that one repo on this PC). The scripts run straight from the workstation repo clone (keep that clone on `main`); there is no installed copy under the Projects root. Shortcuts in the workstation repo's `shortcuts\` folder: **Workers Start**, **Workers Stop**, **Workstation Status** (scripts in `{{TOOLKIT_PATH}}\shortcuts\`). Runtime files (stop flag, worker logs) live in `%LOCALAPPDATA%\Workstation\`, never in the clone. There are no batch pull/push shortcuts. Nothing auto-starts bridge pieces. See `{{TOOLKIT_PATH}}\README.md`.

```powershell
powershell -File "{{TOOLKIT_PATH}}\{{TOOLKIT_STATUS}}"
# pull/push: one repo at a time, e.g. git -C <repo> pull --ff-only
```

- **Cursor web / Claude Code cloud:** commit + push to GitHub (branch + PR), then `git pull --ff-only` in that repo on this PC.
- **Local Cursor / Claude desktop:** edit under `active\` directly; push that repo's branch by hand and open a PR when remotes should see it.
<!-- /shared-memory:v1 -->
