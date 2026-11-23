# Memory Index

**Local Working Memory (this folder) is the shared notes store for Claude Code, Cowork and Cursor. Live project state lives in each repo.**
Real path: `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\`
Claude Code reaches it through `~\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory`,
which is a junction (a folder shortcut) to this folder, so those apps read and write the same files.
It holds preference and fact notes only (no project status), each fact once. It is rebuildable.
Claude account Memory (claude.ai / Your Claude → Memory) is a separate, allowed store for general / non-project prefs. Duplicates are OK; never sync either way; never treat either store as the project source of truth: that is the repo.
Never create a second local memory folder or replace the junction. Do not use `project_memory_read` / `project_memory_write` for project memory. Project-specific rules stay in each repo's own `AGENTS.md`.
Tiers (decision 2026-11-22): the repo (git) holds the router `AGENTS.md`, SPEC, DECISIONS, rules, data and live state: `STATE.md` (trunk; the coordinator's), `STATE-<slug>.md` (one per branch, committed on that branch), `BACKLOG.md` and `archives/`, all at the repo root. Each project folder here holds notes only (preferences, machine facts, gotchas) listed in its `INDEX.md`: no project status, rebuildable. `TASK.md` is the branch checklist at the worktree root, git-ignored.
At 80% context, run the `state-closeout` skill (closeout mode). On-demand handoff: `state-closeout handoff`. No `HANDOFF` or `handoffs/` files; `STATE-<slug>.md` is the handoff. A PR's last commit archives the state file (`state_manager.py archive-branch`).
Store unreachable (PC offline, cloud session): live state is still in the repo; only notes are missing.
A leftover `~\.claude\working-memory` junction is harmless and is not this path. Install does not create or check it.
Memory is local only: never commit it to git.

Read this index at the start of a session, then the repo's `STATE.md` and this branch's `STATE-<slug>.md`, then the project's `INDEX.md` here.
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
