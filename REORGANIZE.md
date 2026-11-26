# Reorganize the Projects folder (for Grok Bot on the new PC)

Goal: make the Projects root match this layout. Projects root = the `-ProjectsRoot` given to
`install.ps1` (default `%USERPROFILE%\Projects`).

    active\     live AND finished projects (anything the user may still use or look at), including the
                workstation repo clone: the Workstation toolkit runs straight from it
    _archive\   layout folder only (this cleanup adds nothing to it)
    _scratch\   temporary files (stays empty after setup, except retire records like bridge-retired-*)
    _claude\    shared memory, Cursor's copy, sync scripts
    _refs\      optional: reference material, vendor docs, third-party clones (only if the user wants it)
    .cursor\    Cursor project settings at the Projects root (if present)
    AGENTS.md   the one root guide (a root CLAUDE.md is merged into it: step 5)

Hard rules: move only after the user approves; never overwrite (if a target name already exists in
`active\` or elsewhere, stop and ask; do not merge blindly); never touch an old toolkit copy (`_workstation\`, `_bridge\`) during
moves; never open, print or move secret files (keys, credentials, `.env` files) beyond moving the
folder they are in; never commit memory to git; never run `git init`.

The package organizes active projects into `active\`. A project with anything recent in it is
active and is proposed for `active\`. Everything that is not an active project is listed and left
for the user to choose. Deletion of projects is totally manual. The agent never deletes a project, a
repo, or the files inside one.

Nothing from this cleanup goes into `_archive`. Do not move old folders or leftover projects into
`_archive`. Projects the user may still use move into `active\` only after they approve that row.
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
deletes a project or repo; the user decides.

## Step 1 (ALWAYS first): inventory and plan. Move nothing.

1. List every top-level item in the Projects root, and other places projects may live
   (the user profile root, Desktop via `[Environment]::GetFolderPath('Desktop')`, Documents, `source\repos`).
2. For each item note: name, size, last change date, is it a git repo (`.git`), remote URL,
   uncommitted changes or unpushed commits (`git status -sb`), open in Cursor / Claude recently.
3. Sort each into one of:
   - **active** - live, finished, or anything with recent work. Propose `active\<name>`. When
     unsure, choose active.
   - **list for the user** - everything that is not an active project. Show it in the table and leave
     it for them to choose. The agent never deletes it.
   - **_scratch** - loose temp files. Never put a project here.
   - **_refs** (optional) - reference material or third-party clones, only if the user wants that folder.
   - **leave as is** - layout folders (`active`, `_archive`, `_scratch`, `_claude`,
     `_refs`), root `AGENTS.md` (and a root `CLAUDE.md` until step 5 merges it), `.cursor\`, other dotfolders.
   - **old organizational folder** - a top-level folder that holds projects beside `active\` (not
     in the leave-as-is list), including names like `shipping`, `_shipping`, `docs`, `inbox`. Plan
     to move projects the user may still use into `active\` (each as its own approval row). Leftovers
     stay listed for them. When the folder is empty, delete that empty folder (no second ask).
4. Show the user a table: current path -> proposed path, and why. Flag repos with uncommitted or
   unpushed work, open editors, and running processes that could lock files. If a proposed
   `active\` name already exists, stop and ask; do not merge blindly. Every project that sits
   inside an old organizational folder (for example a repair-manual folder inside `shipping`) is
   one row with a proposed destination (`active\` if they may still use it). It is not a permanent
   exception that leaves the old organizational folder behind.
5. Wait for the user's approval. Apply their changes to the plan. Do nothing until they say go.

## Step 2: move (after approval only)

1. Close or ask the user to close editors/terminals using the folders.
2. Move one approved project at a time into `active\` with `Move-Item -LiteralPath`. Check the
   target does not exist first.
3. After each move, check the folder opens. For a project that is a git repo, also check
   `git -C <path> status` still works (many projects are plain folders; never turn one into a repo).
4. If anything fails, stop and tell the user. Do not retry with force.
5. Once an old organizational folder directly inside the Projects root is empty, delete that empty
   folder. Do not ask again. Do not delete it if it still contains anything. Do not delete
   projects. Never remove layout folders (`active`, `_archive`, `_claude`, `_refs`, `_scratch`,
   `.cursor`) under this step.

## Step 3: retire `_bridge` and `_workstation` (old toolkit copies, not projects)

Do this only after old automations are off and Start Cursor workers works from the workstation repo clone
(`active\workstation\shortcuts\`). For `_workstation`, first run Stop Cursor workers so no worker runs from it, and
re-point anything that still names it (Health check and preflight list what is left). The steps below use
`_bridge`; for `_workstation` move it to `_archive\<yyyy-MM-dd>\_workstation` instead (the user's yes first).

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
2. Fix project pointer lines in each project's `AGENTS.md` so the path in
   `Project memory: ...\INDEX.md` matches the new slug and names the store
   (`<Projects>\_claude\Claude Projects\Working Memory\memory\<slug>\INDEX.md`).
   See `memory\templates\project-pointer-line.txt`. Do not create or update a `CLAUDE.md` or
   `CLAUDE.local.md` for the pointer. An old line that still says
   `~\.claude\working-memory\` works only while a leftover junction is there. When you touch the line,
   point it at the store. Do not delete that leftover junction.
3. After a project moves, also update:
   - `active\README.md` (any line that still names the old path);
   - the pointer line in the project's `AGENTS.md` if it still uses the old path;
   - any scheduled task whose action still points at the old path.
   List each path you changed.
4. Old paths inside Cursor or Claude settings (recent folders, workspaces) may break; list them for the user.
5. Tell the user what moved, which empty organizational folders were removed, that `_bridge` was
   retired to `_scratch\bridge-retired-<yyyyMMdd>`, and anything left for them to choose.
   Confirm the Projects root matches the end-state list above.

## Step 5: one AGENTS.md (CLAUDE.md merged into it)

Every agent uses `AGENTS.md`. Wherever a `CLAUDE.md`, an `AGENTS.md`, or both exist, they become one
`AGENTS.md`. Claude Code (2.1.281 or newer) reads `AGENTS.md`; a leftover `CLAUDE.md` or `CLAUDE.local.md` can
hide it, which is why the CLAUDE files are folded in and deleted. install.ps1 does not change Claude Code's
Project instructions setting (D-2026-11-26-no-third-party-installs).

1. Projects root (do this yourself, no approval needed, because the root is not a git repo):
   - First check that the root is not a git repo (`git -C <Projects> rev-parse --is-inside-work-tree`
     fails). If it IS a repo, change nothing and tell the user.
   - Back up the root `CLAUDE.md` and `AGENTS.md` to `<Projects>\_scratch\agents-md-merge-<yyyyMMdd-HHmm>\`.
   - Merge both into `AGENTS.md`. Keep every rule once, with no duplicate text. Copy the
     `<!-- shared-memory:v1 -->` ... `<!-- /shared-memory:v1 -->` block unchanged (exactly one copy).
     If there is only a `CLAUDE.md`, its content becomes `AGENTS.md`.
   - Change the root-file wording: the root holds `AGENTS.md`, not "CLAUDE.md and AGENTS.md". Make the same
     change in `.cursor\rules\projects-structure.mdc`, if it exists (back it up first).
   - Verify: every line of the old files is in the new `AGENTS.md` (except the reworded root-file lines),
     and the marker block is there once. Only then delete the root `CLAUDE.md`.
2. Projects in `active\` (and repos nested inside them): the workstation-core template is the target.
   `AGENTS.md` is the only agent instruction file. List every `CLAUDE.md`, `.claude\CLAUDE.md`,
   `CLAUDE.local.md`, and `AGENTS.md` with its folder, whether it is in a git repo, and whether the
   file is tracked. Fold each CLAUDE file into that project's `AGENTS.md` (keep every rule, drop
   exact duplicates), then delete the CLAUDE file. That fold is pre-approved. Every rule is kept.
   A layout difference is not a blocker or a reason to stop. The rules and decisions in those
   files still bind. Show the merged text before writing over
   `AGENTS.md`. In a repo, the user makes the commit themselves, and nothing is pushed.
3. Do not create a `CLAUDE.md` or `CLAUDE.local.md` in a repo or at the Projects root. The memory pointer goes in the project's `AGENTS.md`. Leave `%USERPROFILE%\.claude\CLAUDE.md` alone.
