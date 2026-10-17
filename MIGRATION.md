# Memory migration (for Grok Bot on the new PC)

Goal: find every old memory on this PC, for EVERY Windows account, and merge what is missing
into the ONE shared store that `install.ps1` (workstation setup) set up:

    <Projects>\_claude\Claude Projects\Working Memory\memory\

(`<Projects>` = the `-ProjectsRoot` used for install.ps1, default `%USERPROFILE%\Projects`.)
Notes from other accounts also go into this store unless Dan says otherwise.

Hard rules
- Back up first (step a). Nothing else changes before the backup is verified.
- Never overwrite a note. Never delete an original until Dan says OK.
- Every note and index line you add is signed: `-- Grok Bot (from <source>), yyyy-MM-dd`.
- Follow pointers one step only.
- Never copy, print or move secrets (keys, credentials, `.env`, anything that looks like an API key).
  If a note contains one, leave that part out and tell Dan where it is.
- Memory stays local. Never commit memory or pointer files to git.
- Skip `node_modules`, `_workstation`, `_bridge` (old name of `_workstation`), `extensions`, `plugins` folders everywhere.

## 0. Start from the preflight report

The `memory` lines of `preflight-report-*.txt` already list extra memory stores, real folders under
`~\.claude\projects\*\memory`, a `working-memory` link that points elsewhere, broken links, and Cursor skills or
rules that hard-code memory paths. Include every one of them in the backup and the plan below.

## 0b. List the accounts

    Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | Select-Object LocalPath, LastUseTime

For each account below, `~` = that account's `LocalPath`. Reading another account's folders
needs admin. If access is denied, give Dan a ready-to-paste command for an admin PowerShell
(read and copy only, into the backup folder) and wait for him.

## a. Back up every working-memory folder (memory folders only, not rule files)

Target: `<Projects>\_scratch\memory-backup-<yyyy-MM-dd>\<account>\<source-label>\`

Back up, for each account, every one of these that exists:
- `~\.claude\projects\*\memory\` (skip a junction; back up its target once instead)
- the folder named by `autoMemoryDirectory` in `~\.claude\settings.json` and any `settings.json.bak-*`, if it is somewhere else
- the shared store `<Projects>\_claude\Claude Projects\Working Memory\memory\` (if it already has notes)
- `<Projects>\_claude\Cursor Copy of Claude Memory\cursor-notes\` and `claude-chat-summaries\`
- Claude app data, in both `%APPDATA%\Claude\` and `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`:
  `spaces\*\memory\` and `local-agent-mode-sessions\*\*\memory\`

Use `robocopy <src> <dst> /E /XJ /R:1 /W:1` (copies, never moves). Then verify for each pair that the
file count and total size match:

    (Get-ChildItem -LiteralPath <src> -Recurse -File -Force | Measure-Object Length -Sum)
    (Get-ChildItem -LiteralPath <dst> -Recurse -File -Force | Measure-Object Length -Sum)

Write `BACKUP-LIST.md` in the backup folder (source -> backup, counts). Show Dan the totals.
Stop if any count does not match.

## b. Scan (read only)

For each account, look at:

| Where | What to look for |
|---|---|
| `~\.claude\projects\*\memory\` | memory notes (`MEMORY.md` + topic files) |
| `~\.claude\projects\*\*.jsonl` | Claude Code transcripts: decisions, facts, "remember this" |
| Claude app `claude-code-sessions\` | Claude desktop Code sessions |
| Claude app `local-agent-mode-sessions\*\*\local_*.json` | Cowork session records (title, folder, summary) |
| Claude app `spaces\*\memory\` | Claude app per-space memory |
| `%APPDATA%\Cursor\User\globalStorage\state.vscdb` | Cursor memories / chat data (SQLite) |
| `%APPDATA%\Cursor\User\workspaceStorage\*\state.vscdb` | per-workspace Cursor chats; `workspace.json` next to it names the folder |
| `~\.cursor\projects\*\agent-transcripts\` | Cursor agent transcripts |
| `~\.cursor\chats\`, `~\.cursor\plans\` | Cursor CLI chats and plans |
| every `AGENTS.md` and `CLAUDE.md` under `<Projects>` | project facts that belong in memory (copy facts only; the files stay as they are) |

Tips
- `.vscdb` files are SQLite and may be locked: copy the file (plus `-wal`/`-shm`) to a temp folder
  under the backup folder and read the copy (Python `sqlite3`). Look in `ItemTable` / `cursorDiskKV`
  for keys that mention memory, composer or chat. Read only.
- Map every old path to a current `active\` project: the transcript folder name is the old path with
  every non-letter/digit as `-`; `workspace.json` holds a `file:///` folder URI. A project that moved
  or was renamed during REORGANIZE.md maps to its new `active\` name. Unknown -> `_unassigned`.

## c. Show Dan the plan

One table per target project folder: note -> source -> target file -> new / already there / conflict.
Say which notes you will skip as duplicates or stale. Wait for Dan's OK.

## d. Merge (after approval only)

- Only notes that are missing. Same fact already there = skip.
- Put each note in the right project folder (`<store>\<slug>\`, `_archive\<slug>\` or `_unassigned\`),
  add one line to that folder's `INDEX.md` and (for a new project folder) one line under
  `## Projects` in `MEMORY.md`.
- Never overwrite: if a file name exists, pick a new name.
- Sign every new note and index line: `-- Grok Bot (from <source>), yyyy-MM-dd`.
- Keep all originals where they are until Dan OKs cleanup.
- If `~\.claude\projects\<key>\memory` was a real folder (install.ps1 warned about it): after its notes are
  merged and Dan agrees, rename it to `memory.pre-migration-<yyyy-MM-dd>` (do not delete), then re-run
  `install.ps1` to create the junction and wire the guard hook.
- Add a pointer line to each `active\` project (template: `memory\templates\project-pointer-line.txt`,
  `{{PROJECT_SLUG}}` = the project's slug; the `%USERPROFILE%\.claude\working-memory\` part stays as written):
  - git repo: put it in `CLAUDE.local.md` and add `CLAUDE.local.md` to `.git\info\exclude` (not `.gitignore`);
  - not a git repo: add it to the project's `CLAUDE.md`.
  Skip a project that already has the line.

## e. Transcript-only findings

List facts found ONLY in transcripts or chat databases (not in any memory file), grouped by project,
with the source. Do not save them until Dan picks which ones to keep.

## f. Claude instructions: two texts, pasted by hand

The package folder `instructions\` holds two texts (see `instructions\README.md`). Dan pastes them; you never edit
them or Claude's files. Walk him through ONE step at a time and wait for his OK after each:
1. Check the junction resolves first: `Get-ChildItem $env:USERPROFILE\.claude\working-memory\*\INDEX.md`.
2. `instructions\instructions-for-claude.md` (as is): Claude desktop > Settings > **Instructions for Claude**.
   Account-level; applies to regular chats and Cowork. Not checkable on disk, so ask Dan to confirm it is saved.
3. `instructions\cowork-global-instructions.md` (as is): Claude desktop > Cowork settings > **Global instructions**.
   Cowork only. Its `## Working memory` paragraph is Cowork's ONE memory rule for all its projects. Afterwards re-run
   `preflight.ps1`: the `instructions` line for the Cowork file should say ALREADY-INSTALLED.
4. Tell Dan to remove any old per-project Cowork memory lines from his Cowork projects' instructions (they
   pointed at `...\.claude\working-memory\<slug>\INDEX.md` or a full Projects path); the global text replaces them.
5. If Cowork's **Cowork files** location is not `<Projects>\_claude\Claude Projects` (the store's parent), tell
   Dan to change it to that.

Both texts follow Dan's account to every PC, so they hold no PC paths or user names. The working-memory
paragraph points at `%USERPROFILE%\.claude\working-memory` (the `.claude\working-memory` folder in the user's home
folder). install.ps1 creates that folder as a junction to the memory store on each PC, and the guard hook recreates
it if it goes missing. install.ps1 only checks the Cowork text on disk and prints a TODO if it is missing. Claude Code
projects keep their per-project pointer line from step d.

## Done

Tell Dan: what was backed up (and where), what was merged, what was skipped, transcript-only
findings waiting for him, and which originals can be cleaned up once he OKs it.
