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
- Skip `node_modules`, `_workstation` and `_bridge` (old installed toolkit copies), `extensions`, `plugins` folders everywhere.

## 0. Start from the preflight report

The `memory` lines of `preflight-report-*.txt` already list extra memory stores and real folders under
`~\.claude\projects\*\memory`, plus Cursor skills or rules that hard-code memory paths. Include every one
of them in the backup and the plan below. A leftover `~\.claude\working-memory` junction is not a conflict
and is not repaired. If that path is a real folder with notes, back it up and include it (it may be stranded
Cowork notes).

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
- `<Projects>\_claude\Cursor Notes\` (legacy folder; and, on older installs, `<Projects>\_claude\Cursor Copy of Claude Memory\cursor-notes\` and `claude-chat-summaries\`)
- Claude desktop app data. Current personal-account location (verified 2026-11-03, Store app 4.4212.0.0,
  Unified Claude): `%LOCALAPPDATA%\Claude-Data\claude_*\`. Older copies may still be in `%APPDATA%\Claude\`
  and `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`. Look for `spaces\*\memory\` and
  `local-agent-mode-sessions\*\*\memory\`. Local Cowork memory had no writes after 2026-10-19 on the
  personal account. Those notes are stranded: merge anything worth keeping into the shared store, or use
  Claude desktop's **Import memory** button to pull them into account Memory. They are not synced with
  the file store. The work account is unverified; check it the same way before assuming it matches.
- `~\.claude\working-memory` only when it is a real folder with files (a junction is just a leftover link;
  do not follow it into a second copy of the store)

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
  `{{PROJECT_SLUG}}` = the project's slug). The line names the store
  `<Projects>\_claude\Claude Projects\Working Memory\memory\<slug>\INDEX.md`. It does not use
  `~\.claude\working-memory`.
  - git repo: put it in `CLAUDE.local.md` and add `CLAUDE.local.md` to `.git\info\exclude` (not `.gitignore`);
  - not a git repo: add it to the project's `CLAUDE.md`.
  Skip a project that already has the line. An old line that still says `~\.claude\working-memory\`
  keeps working only while a leftover junction is there. When you touch the line, point it at the store.
  Do not delete the leftover junction.

## e. Transcript-only findings

List facts found ONLY in transcripts or chat databases (not in any memory file), grouped by project,
with the source. Do not save them until Dan picks which ones to keep.

## f. Claude instructions (pasted by hand) and the memory split

The package folder `instructions\` holds the paste texts (see `instructions\README.md`). Dan pastes them; you never
edit them or Claude's files.

Memory split (personal account, verified 2026-11-03, Store app 4.4212.0.0, Unified Claude; **work account unverified**):
- The Claude Code file store `<Projects>\_claude\Claude Projects\Working Memory\memory\` is the record for
  preferences, rules and cross-project facts. Claude Code reaches it through the `autoMemoryDirectory` junction.
  The guard hook keeps that junction. Project progress stays in each repo's state file.
- Claude desktop online Memory (Settings > Your Claude > Memory) is account-level facts about the user.
  It is not synced with the file store. Cowork / Chat do not write local memory files.
- A leftover `~\.claude\working-memory` junction is harmless. install.ps1 does not create, check or remove it.
  uninstall.ps1 does not remove it either.
- Stranded local Cowork notes (step a) can be copied into the store or brought in with the app's Import memory button.

Walk Dan through ONE step at a time and wait for his OK after each:
1. `instructions\instructions-for-claude.md` (as is): Claude desktop > Settings > **Instructions for Claude**,
   if that box is still there. Account-level. Not checkable on disk, so ask Dan to confirm it is saved.
2. `instructions\cowork-global-instructions.md` only if a Global instructions box is still there. It no longer
   tells the app to use a local folder. Preflight does not check it.
3. Optional: old per-project Cowork lines that pointed at `~\.claude\working-memory\<slug>\INDEX.md` are obsolete.
   Dan can remove them. Do not point a Cowork files location at the store; the desktop app does not use that folder.

Claude Code projects keep their per-project pointer line from step d.

## Done

Tell Dan: what was backed up (and where), what was merged, what was skipped, transcript-only
findings waiting for him, and which originals can be cleaned up once he OKs it.
