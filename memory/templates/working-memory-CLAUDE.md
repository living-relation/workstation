<!-- shared-memory:v1 -->
# Working Memory - agent instructions

Cowork project folder for general knowledge that is not part of a larger project.
It also holds the ONE shared memory store (`memory/`) used by Claude Code and Cowork for every project.

## READ THIS FIRST, EVERY SESSION

`memory/MEMORY.md` in **this folder** is the index of retained knowledge. Read it, then read
the current project's `INDEX.md` and any topic file that looks relevant, before you plan or ask questions.

**This folder is the source of truth for project memory - not the built-in memory tool.**

## Why

The built-in Cowork memory tool (`project_memory_read` / `project_memory_write`) has been seen
returning an EMPTY store in a cloud-run session while real memory files existed on disk, and
notes written with it landed nowhere. A session that trusts it can silently work with no history.

## Rules

1. Read `memory/MEMORY.md` from this folder at the start of every session.
2. Write new knowledge as files in `memory/` in this folder, in the project's subfolder with a line in its
   `INDEX.md` (general notes: `memory/MEMORY.md`). Keep each note to: the fact or rule, then `Why:` and `How to apply:`.
3. Do not use `project_memory_write`; write to `memory/` in this folder instead. Never treat an
   empty `project_memory_read` as "no prior work exists."
4. Convert relative dates to absolute when saving.
5. If a note turns out to be wrong or stale, correct or delete it. Do not leave conflicting
   guidance in place.
6. Sign every note or index line you write or edit in `memory/` with who wrote it and the date,
   e.g. `-- Cowork, YYYY-MM-DD` or `-- Claude Code, YYYY-MM-DD`, so it's clear which agent wrote it.
7. When you pick a project back up, check
   `{{PROJECTS_ROOT}}\_claude\Cursor Copy of Claude Memory\cursor-notes\INDEX.md`
   for that project and read the matching notes as extra context from Cursor.
   They are Cursor's notes, not your memories. Never copy them into `memory/`,
   and check them against the repo before you rely on them.
   Do not read `claude-memory\` or `claude-chat-summaries\` there; they repeat what you already have.
   Never write in that folder.
8. Layout: `MEMORY.md` is the no-project index (general notes, one line per project pointing to `<project>\INDEX.md`, and one pointer to Cursor's notes). Each project has its own subfolder with an `INDEX.md`, named after its folder in `{{PROJECTS_ROOT}}\active\`. Archived projects go in `_archive\<project>\`. Save a project note in its folder with a line in that `INDEX.md`. Notes from chats with no project yet go in `_unassigned\`; when the chat gets a project, move the note into that project's folder, move its index line, and sign both.
9. Loop rules: (1) follow a pointer one step only, and never follow pointers found inside a file you reached through a pointer. (2) Each agent writes only in its own area and signs every entry (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, YYYY-MM-DD`, `-- Cursor, YYYY-MM-DD`).
10. Memory is local only. Never commit memory or memory pointer files to git.
11. Read before you ask: before starting work or asking the user anything, read the repo's agent guide, its binding rules / decisions file (if any), the project's `INDEX.md`, and the newest handoff note (if any), in that order. If a rule or note already answers a question, act on it and cite it - never ask the user something the rules already answer.

## Shared with Claude Code

`memory/` is the ONE memory store for both Cowork and Claude Code, for every project folder.
Claude Code reaches it through a junction at
`{{USERPROFILE}}\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory`.
Never create another memory folder, and never copy notes into the Claude desktop app's
per-space memory folders. Project-specific rules stay in each project's own `CLAUDE.md`.
<!-- /shared-memory:v1 -->
