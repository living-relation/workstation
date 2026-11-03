# Memory Index

**This is the Claude Code shared memory store for every project folder.**
Real path: `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\`
Claude Code reaches it through `~\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory`,
which is a junction (a folder shortcut) to this folder. Cursor edits these same files.
Claude desktop online Memory (Settings > Your Claude > Memory) is a separate account-level list
of facts about the user. It is not synced with this folder. Cowork / Chat no longer write here
(personal account verified 2026-11-03; work account unverified).
Never create a second memory folder or copy notes elsewhere. Project rules stay in each project's
own `CLAUDE.md`. This folder holds preferences, rules and cross-project facts only, each fact once.
Project progress (status, next steps, PR and branch state, TODOs, handoffs) stays in the repo's
state file. Memory is local only: never commit it to git.

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
