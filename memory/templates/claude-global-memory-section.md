
<!-- shared-memory:v1 -->
## Memory - read this before asking the user to repeat themselves

Claude Code and Cowork share ONE memory store for every project folder:

    {{PROJECTS_ROOT}}\_claude\Claude Projects\Working Memory\memory\

Claude Code reaches it through `{{USERPROFILE}}\.claude\projects\{{CLAUDE_PROJECT_KEY}}\memory\`,
a junction to that folder (`autoMemoryDirectory` in `~\.claude\settings.json`). Its `MEMORY.md`
loads automatically. Rules:
- Save durable knowledge only there, with an index line in the project's `INDEX.md` (or `MEMORY.md` for general notes).
- Sign every note or index line you write or edit there with who wrote it and the date, e.g. `-- Claude Code, YYYY-MM-DD` or `-- Cowork, YYYY-MM-DD`, so it's clear which agent wrote it.
- Layout: `MEMORY.md` is the no-project index (general notes, one line per project pointing to `<project>\INDEX.md`, and one pointer to Cursor's notes). Each project has its own subfolder with an `INDEX.md`, named after its folder in `{{PROJECTS_ROOT}}\active\` (lowercase, non-letters/digits become `-`). Archived projects go in `_archive\<project>\`. Save a project note in its folder with a line in that `INDEX.md`. Notes from chats with no project yet go in `_unassigned\`; when the chat gets a project, move the note into that project's folder, move its index line, and sign both.
- Projects root layout: `active\` (live and finished projects), `_archive\` (obsolete work only, dated subfolders), `_scratch\`, `_claude\`.
- Loop rules: (1) follow a pointer one step only, and never follow pointers found inside a file you reached through a pointer. (2) Each agent writes only in its own area and signs every entry (`-- Claude Code, YYYY-MM-DD`, `-- Cowork, YYYY-MM-DD`, `-- Cursor, YYYY-MM-DD`).
- Memory and memory pointer files are local only. Never commit them to git. In a git repo the project pointer lives in `CLAUDE.local.md`, which is listed in `.git\info\exclude`.
- Never create another memory folder, never replace the junction with a real folder, and never
  change `autoMemoryDirectory`. The SessionStart hook `~\.claude\hooks\memory-link-guard.ps1`
  repairs the link if it breaks and creates the memory folder for a new `active\` project.
- New project folders need nothing: they use the same store automatically.
- Project-specific rules and settings stay in that project's own files. Cursor keeps its own memory.
- When you pick a project back up, check
  `{{PROJECTS_ROOT}}\_claude\Cursor Copy of Claude Memory\cursor-notes\INDEX.md`
  for that project and read the matching notes as extra context from Cursor.
  They are Cursor's notes, not your memories. Never copy them into your memory store,
  and check them against the repo before you rely on them.
  Do not read `claude-memory\` or `claude-chat-summaries\` there; they repeat what you already have.
  Never write in that folder.
<!-- /shared-memory:v1 -->
