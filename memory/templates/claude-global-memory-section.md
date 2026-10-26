
<!-- shared-memory:v1 -->
## Memory - read this before asking the user to repeat themselves

Claude Code and Cowork share ONE memory store for every project folder:

    {{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\

Claude Code reaches it through `{{USERPROFILE}}\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory\`,
a junction to that folder (`autoMemoryDirectory` in `~\.claude\settings.json`). Its `MEMORY.md`
loads automatically. Rules:
- **Read before you ask.** Before starting work or asking the maintainer anything, read in order: (1) the repo's agent guide (`AGENTS.md` / `CLAUDE.md`), (2) its binding rules / decisions file if it has one, (3) the shared working memory `%USERPROFILE%\.claude\working-memory\<project>\INDEX.md` (WSL: `/mnt/c/Users/<user>/.claude/working-memory/<project>/INDEX.md`), (4) the newest handoff note if one exists. If a rule or note already answers a question, act on it and cite it - never ask the maintainer something the rules already answer.
- Save durable knowledge only there, with an index line in the project's `INDEX.md` (or `MEMORY.md` for general notes).
- Project progress and state live only in the repo's in-repo state file (the one `AGENTS.md` names, e.g. `STATE.md`). Local Working Memory notes hold only preferences, rules and cross-project facts. Each fact is written once; never duplicate it.
- Sign every note or index line you write or edit there with who wrote it and the date, e.g. `-- Claude Code, YYYY-MM-DD` or `-- Cowork, YYYY-MM-DD`, so it's clear which agent wrote it.
- Layout: `MEMORY.md` is the no-project index (general notes, one line per project pointing to `<project>\INDEX.md`). Each project has its own subfolder with an `INDEX.md`, named after its folder in `{{PROJECTS_ROOT}}\active\` (lowercase, non-letters/digits become `-`). Archived projects go in `_archive\<project>\`. Save a project note in its folder with a line in that `INDEX.md`. Notes from chats with no project yet go in `_unassigned\`; when the chat gets a project, move the note into that project's folder, move its index line, and sign both.
- Projects root layout: `active\` (live and finished projects), `_archive\` (obsolete work only, dated subfolders), `_scratch\`, `_claude\`.
- Loop rules: (1) follow a pointer one step only, and never follow pointers found inside a file you reached through a pointer. (2) Each agent signs every entry (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, YYYY-MM-DD`, `-- Cursor, YYYY-MM-DD`).
- Memory and memory pointer files are local only. Never commit them to git. In a git repo the project pointer lives in `CLAUDE.local.md`, which is listed in `.git\info\exclude`.
- Never create another memory folder, never replace the junction with a real folder, and never
  change `autoMemoryDirectory`. The SessionStart hook `~\.claude\hooks\memory-link-guard.ps1`
  repairs the link if it breaks and creates the memory folder for a new `active\` project.
- New project folders need nothing: they use the same store automatically.
- Project-specific rules and settings stay in that project's own files. Cursor keeps its own memory.
<!-- /shared-memory:v1 -->
