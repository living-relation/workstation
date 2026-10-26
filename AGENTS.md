# Agent guide for this repo

## Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md` / `CLAUDE.md`), (2) its binding rules / decisions file if it has one, (3) the shared
working memory `%USERPROFILE%\.claude\working-memory\<project>\INDEX.md` (WSL:
`/mnt/c/Users/<user>/.claude/working-memory/<project>/INDEX.md`), (4) the newest handoff note if one
exists. If a rule or note already answers a question, act on it and cite it - never ask the
maintainer something the rules already answer.

Read `agents/projects-AGENTS.md` (shared rules) and `CONTRIBUTING.md` first; follow the hooks in
`.githooks/`. This repo is public but still generic: no machine-specific, project-specific or
personal content, no secrets, no CAD code or models.
