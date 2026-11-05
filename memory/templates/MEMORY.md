# Memory Index

**Local Working Memory (this folder) is the shared project source of truth for Claude Code, Cowork and Cursor.**
Real path: `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\`
Also `~\.claude\working-memory`. Claude Code reaches it through `~\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory`,
which is a junction (a folder shortcut) to this folder, so those apps read and write the same files.
It holds preferences, rules and cross-project facts. Claude account Memory (claude.ai / Your Claude → Memory) is a separate, allowed store for general / non-project prefs. Duplicates are OK; never sync either way; never treat account Memory as the project source of truth.
Never create a second local memory folder or replace the junction. Do not use `project_memory_read` / `project_memory_write` for project memory. Project-specific rules stay in each repo's own `AGENTS.md`. Memory is local only: never commit it to git.

Read this index at the start of a session, then open the current project's `INDEX.md`.
This file holds general (no-project) notes and one line per project.

## Layout and loop rules

- Each project has a subfolder here with its own `INDEX.md`, named after its folder in
  `{{PROJECTS_ROOT}}\active\` (lowercase, non-letters/digits become `-`). Archived projects
  go in `_archive\<project>\`. Notes from chats with no project yet go in `_unassigned\`.
  When a chat gets a project, move its note into that project's folder and move its index line too.
- A pointer is followed ONE step only. Pointers found inside a file reached through a pointer
  are never followed.
- Each agent signs every entry
  (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, YYYY-MM-DD`, `-- Cursor, YYYY-MM-DD`).

## Projects

- [Unassigned](_unassigned/INDEX.md) - notes from chats with no project yet.

## General notes

(No notes yet.)

---

*Store created {{DATE}} by the workstation setup install.ps1.*
