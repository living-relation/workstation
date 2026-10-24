# Memory Index

**This is the ONE shared memory store for Claude Code AND Cowork, for every project folder.**
Real path: `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\`
Claude Code reaches it through `~\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory`,
which is a junction (a folder shortcut) to this folder, so both apps read and write the same files.
Never create a second memory folder or copy notes elsewhere. Project rules stay in each project's
own `CLAUDE.md`; only memory lives here. Memory is local only: never commit it to git.

Read this index at the start of a session, then open the current project's `INDEX.md`.
This file holds general (no-project) notes and one line per project.

## Layout and loop rules

- Each project has a subfolder here with its own `INDEX.md`, named after its folder in
  `{{PROJECTS_ROOT}}\active\` (lowercase, non-letters/digits become `-`). Archived projects
  go in `_archive\<project>\`. Notes from chats with no project yet go in `_unassigned\`.
  When a chat gets a project, move its note into that project's folder and move its index line too.
- A pointer is followed ONE step only. Pointers found inside a file reached through a pointer
  are never followed.
- Each agent writes only in its own area and signs every entry
  (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, YYYY-MM-DD`, `-- Cursor, YYYY-MM-DD`).

## Projects

- [Unassigned](_unassigned/INDEX.md) - notes from chats with no project yet.

## Cursor's notes

- Cursor's notes (read-only for Claude; extra context, not memory): `{{PROJECTS_ROOT}}\_claude\Cursor Notes\INDEX.md`

## General notes

(No notes yet.)

---

*Store created {{DATE}} by the workstation setup install.ps1.*
