
<!-- shared-memory:v1 -->
## Memory - read this before asking the user to repeat themselves

Claude Code, Cowork and Cursor share ONE local memory store for notes, for every project folder. Live project state lives in each repo (the project source of truth).
Claude account Memory (claude.ai) is a separate, allowed store for general / non-project prefs. Duplicates with the local folder are OK; never sync both ways; never treat it as the project source of truth.

    {{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\

Claude Code reaches it through `{{USERPROFILE}}\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory\`,
a junction to that folder (`autoMemoryDirectory` in `~\.claude\settings.json`). Its `MEMORY.md`
loads automatically. A leftover `~\.claude\working-memory` junction is harmless and is not this path. Install does not create or check it.
Rules:
- **Read before you ask.** Before starting work or asking the maintainer anything, read in order: (1) the repo's agent guide (`AGENTS.md`), (2) its binding rules / decisions file if it has one, (3) the project's live state in the repo: `STATE.md` and this branch's `STATE-<slug>.md` at the repo root, (4) the notes in `{{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\<project>\INDEX.md`. If a rule or note already answers a question, act on it and cite it - never ask the maintainer something the rules already answer.
- Tiers (decision 2026-11-22): the repo (git) holds the router `AGENTS.md`, SPEC, DECISIONS, rules, data and live state: `STATE.md` (trunk; the coordinator's), `STATE-<slug>.md` (one per branch, committed on that branch), `BACKLOG.md` and `archives/`, all at the repo root. The store's project folder holds notes only (preferences, machine facts, gotchas) listed in its `INDEX.md` (general notes: `MEMORY.md`): no project status, rebuildable. `TASK.md` is the branch checklist at the worktree root, git-ignored. Each fact is written once.
- At 80% context, run the `state-closeout` skill (closeout mode). On-demand handoff: `state-closeout handoff`. No `HANDOFF` or `handoffs/` files; `STATE-<slug>.md` is the handoff. A PR's last commit archives the state file (`state_manager.py archive-branch`).
- Store unreachable (PC offline, cloud session): live state is still in the repo; only notes are missing.
- Don't use `project_memory_read` / `project_memory_write` for project memory.
- Sign every note or index line you write or edit there with who wrote it and the date, e.g. `-- Claude Code, YYYY-MM-DD` or `-- Cowork, YYYY-MM-DD`, so it's clear which agent wrote it.
- Layout: `MEMORY.md` is the no-project index (general notes, one line per project pointing to `<project>\INDEX.md`). Each project has its own subfolder with an `INDEX.md`, named after its folder in `{{PROJECTS_ROOT}}\active\` (lowercase, non-letters/digits become `-`). Archived projects go in `_archive\<project>\`. Save a project note in its folder with a line in that `INDEX.md`. Notes from chats with no project yet go in `_unassigned\`; when the chat gets a project, move the note into that project's folder, move its index line, and sign both.
- Projects root layout: `active\` (live and finished projects), `_archive\` (obsolete work only, dated subfolders), `_scratch\`, `_claude\`.
- Loop rules: (1) follow a pointer one step only, and never follow pointers found inside a file you reached through a pointer. (2) Each agent signs every entry (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, YYYY-MM-DD`, `-- Cursor, YYYY-MM-DD`).
- Memory store files are local only. Never commit them to git (live state is committed in the repo, not the store). The one-line project pointer lives in the project's `AGENTS.md`. Do not create a `CLAUDE.md` or `CLAUDE.local.md` for it.
- Never create another memory folder, never replace the junction with a real folder, and never
  change `autoMemoryDirectory`. The SessionStart hook `memory-link-guard.ps1` (workstation-core plugin)
  repairs the link if it breaks and creates the memory folder for a new `active\` project.
- New project folders need nothing: they use the same store automatically.
- Project-specific rules and settings stay in that project's own files. Cursor keeps its own memory.
<!-- /shared-memory:v1 -->
