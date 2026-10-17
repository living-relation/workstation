# Reorganize the Projects folder (for Grok Bot on the new PC)

Goal: make the Projects root match this layout. Projects root = the `-ProjectsRoot` given to
`install.ps1` (default `%USERPROFILE%\Projects`).

    active\     live AND finished projects (anything Dan may still use or look at), including the
                workstation repo clone: the Workstation toolkit runs straight from it
    _archive\   layout folder only (this cleanup adds nothing to it)
    _scratch\   temporary files (stays empty after setup, except retire records like bridge-retired-*)
    _claude\    shared memory, Cursor's copy, sync scripts
    _refs\      optional: reference material, vendor docs, third-party clones (only if Dan wants it)
    .cursor\    Cursor project settings at the Projects root (if present)
    AGENTS.md   the one root guide (a root CLAUDE.md is merged into it: step 5)

Hard rules: move only after Dan approves; never overwrite (if a target name already exists in
`active\` or elsewhere, stop and ask; do not merge blindly); never touch an old toolkit copy (`_workstation\`, `_bridge\`) during
moves; never open, print or move secret files (keys, credentials, `.env` files) beyond moving the
folder they are in; never commit memory to git; never run `git init`.

The package organizes active projects into `active\`. A project with anything recent in it is
active and is proposed for `active\`. Everything that is not an active project is listed and left
for Dan to choose. Deletion of projects is totally manual. The agent never deletes a project, a
repo, or the files inside one.

Nothing from this cleanup goes into `_archive`. Do not move old folders or leftover projects into
`_archive`. Projects Dan may still use move into `active\` only after he approves that row.
`_archive` stays as a layout folder so the root can match, but this cleanup adds nothing to it.

Old organizational folders: a top-level folder that holds projects and is not one of `active`,
`_archive`, `_scratch`, `_claude`, `_refs`, or a dotfolder should not remain. The
shortcuts only look in `active\`. This rule only covers folders that hold projects (a second
projects folder sitting beside `active\`). Layout folders stay and are never removed by this
cleanup: `active`, `_archive`, `_claude`, `_refs`, `_scratch`, `.cursor`.
`_bridge` and `_workstation` (old installed toolkit copies) are retired only by their own step below (toolkit
folders, not projects).

Once an old organizational folder directly inside the Projects root is empty, delete that empty
folder. Do not ask again for an empty folder. Do not delete it if it still contains anything. Do
not delete projects.

End state of the Projects root must be exactly: `active\`, `_archive\`, `_claude\`, `_refs\`,
`_scratch\`, `.cursor\`, `AGENTS.md`. No other top-level folders, and no root `CLAUDE.md` (step 5).
`shipping`, `_shipping`, `docs`, `inbox`, and a live `_bridge` or `_workstation` must not remain.

Git warning (show in the approval table, not as a prelude to deletion): if a folder still holds a
git repo with uncommitted changes or unpushed commits, flag that row. The agent still never
deletes a project or repo; Dan decides.

## Step 1 (ALWAYS first): inventory and plan. Move nothing.

1. List every top-level item in the Projects root, and other places projects may live
   (the user profile root, Desktop via `[Environment]::GetFolderPath('Desktop')`, Documents, `source\repos`).
2. For each item note: name, size, last change date, is it a git repo (`.git`), remote URL,
   uncommitted changes or unpushed commits (`git status -sb`), open in Cursor / Claude recently.
3. Sort each into one of:
   - **active** - live, finished, or anything with recent work. Propose `active\<name>`. When
     unsure, choose active.
   - **list for Dan** - everything that is not an active project. Show it in the table and leave
     it for him to choose. The agent never deletes it.
   - **_scratch** - loose temp files. Never put a project here.
   - **_refs** (optional) - reference material or third-party clones, only if Dan wants that folder.
   - **leave as is** - layout folders (`active`, `_archive`, `_scratch`, `_claude`,
     `_refs`), root `AGENTS.md` (and a root `CLAUDE.md` until step 5 merges it), `.cursor\`, other dotfolders.
   - **old organizational folder** - a top-level folder that holds projects beside `active\` (not
     in the leave-as-is list), including names like `shipping`, `_shipping`, `docs`, `inbox`. Plan
     to move projects Dan may still use into `active\` (each as its own approval row). Leftovers
     stay listed for him. When the folder is empty, delete that empty folder (no second ask).
4. Show Dan a table: current path -> proposed path, and why. Flag repos with uncommitted or
   unpushed work, open editors, and running processes that could lock files. If a proposed
   `active\` name already exists, stop and ask; do not merge blindly. Every project that sits
   inside an old organizational folder (for example a repair-manual folder inside `shipping`) is
   one row with a proposed destination (`active\` if he may still use it). It is not a permanent
   exception that leaves the old organizational folder behind.
5. Wait for Dan's approval. Apply his changes to the plan. Do nothing until he says go.

## Step 2: move (after approval only)

1. Close or ask Dan to close editors/terminals using the folders.
2. Move one approved project at a time into `active\` with `Move-Item -LiteralPath`. Check the
   target does not exist first.
3. After each move, check the folder opens. For a project that is a git repo, also check
   `git -C <path> status` still works (many projects are plain folders; never turn one into a repo).
4. If anything fails, stop and tell Dan. Do not retry with force.
5. Once an old organizational folder directly inside the Projects root is empty, delete that empty
   folder. Do not ask again. Do not delete it if it still contains anything. Do not delete
   projects. Never remove layout folders (`active`, `_archive`, `_claude`, `_refs`, `_scratch`,
   `.cursor`) under this step.

## Step 3: retire `_bridge` and `_workstation` (old toolkit copies, not projects)

Do this only after old automations are off and Workers Start works from the workstation repo clone
(`active\workstation\shortcuts\`). For `_workstation`, first run Workers Stop so no worker runs from it, and
re-point anything that still names it (Workstation Status and preflight list what is left). The steps below use
`_bridge`; for `_workstation` move it to `_archive\<yyyy-MM-dd>\_workstation` instead (Dan's yes first).

1. Copy the live `_bridge` folder to `_scratch\bridge-retired-<yyyyMMdd>` as a record only.
2. Then delete the live `_bridge` folder.
3. If a Workstation shortcut fails afterward, do NOT restore `_bridge`, do NOT copy that scratch
   folder back, and do NOT point shortcuts at it. Fix the new setup and report what failed.

## Step 4: update memory names and other pointers to match

Memory folder names follow the `active\` folder names: lowercase, every run of characters that
are not a letter or digit becomes `-` (for example `My Project.v2` -> `my-project-v2`).

1. In the store `<Projects>\_claude\Claude Projects\Working Memory\memory\`:
   - a renamed or moved project: rename its memory folder to the new slug, and fix its line in `MEMORY.md`.
   Sign each change: `-- Grok Bot, yyyy-MM-dd`.
2. Fix project pointer lines (`CLAUDE.local.md` in git repos, else `CLAUDE.md`) so the path in
   `Project memory: ...\INDEX.md` matches the new slug. See `memory\templates\project-pointer-line.txt`.
3. After a project moves, also update:
   - `active\README.md` (any line that still names the old path);
   - any `CLAUDE.local.md` or `CLAUDE.md` memory pointer that still uses the old path;
   - any scheduled task whose action still points at the old path.
   List each path you changed.
4. Old paths inside Cursor or Claude settings (recent folders, workspaces) may break; list them for Dan.
5. Tell Dan what moved, which empty organizational folders were removed, that `_bridge` was
   retired to `_scratch\bridge-retired-<yyyyMMdd>`, and anything left for him to choose.
   Confirm the Projects root matches the end-state list above.

## Step 5: one AGENTS.md (CLAUDE.md merged into it)

Every agent uses `AGENTS.md`. Wherever a `CLAUDE.md`, an `AGENTS.md`, or both exist, they become one
`AGENTS.md`. Claude Code (2.1.281 or newer) reads it next to any `CLAUDE.local.md` only because install.ps1
sets Project instructions to `claude-md-and-agents-md` in `%USERPROFILE%\.claude\settings.json`
(preflight shows it). Without that, a `CLAUDE.md` or `CLAUDE.local.md` hides `AGENTS.md`.

1. Projects root (do this yourself, no approval needed, because the root is not a git repo):
   - First check that the root is not a git repo (`git -C <Projects> rev-parse --is-inside-work-tree`
     fails). If it IS a repo, change nothing and tell Dan.
   - Back up the root `CLAUDE.md` and `AGENTS.md` to `<Projects>\_scratch\agents-md-merge-<yyyyMMdd-HHmm>\`.
   - Merge both into `AGENTS.md`. Keep every rule once, with no duplicate text. Copy the
     `<!-- shared-memory:v1 -->` ... `<!-- /shared-memory:v1 -->` block unchanged (exactly one copy).
     If there is only a `CLAUDE.md`, its content becomes `AGENTS.md`.
   - Change the root-file wording: the root holds `AGENTS.md`, not "CLAUDE.md and AGENTS.md". Make the same
     change in `.cursor\rules\projects-structure.mdc`, if it exists (back it up first).
   - Verify: every line of the old files is in the new `AGENTS.md` (except the reworded root-file lines),
     and the marker block is there once. Only then delete the root `CLAUDE.md`.
2. Projects in `active\` (and repos nested inside them): change nothing yet. List every `CLAUDE.md`,
   `.claude\CLAUDE.md` and `AGENTS.md` with:
   - its folder;
   - whether it is in a git repo;
   - whether the file is tracked;
   - whether both files exist.

   Dan says yes or no per file. In a repo, the merge is a commit Dan makes himself, and nothing is pushed.
3. Never touch `CLAUDE.local.md` (the memory pointer stays there) or `%USERPROFILE%\.claude\CLAUDE.md`.
