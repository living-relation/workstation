# Upstream

This skill is Dan's copy of [claude-wizard](https://github.com/vlad-ko/claude-wizard) `skill/`, based on `43756e1` (full `43756e1fe74672f35694ff2312847fc9aa037e04`).

This repo is the source of truth. Skills get in only by installing the workstation-core plugin (see `INSTALL.md`). No zip upload.

## Dan's changes

From pull request 57. Every other file under this folder matches that upstream commit.

- **Shorter description.** Upstream's description is one long paragraph. This copy uses a short "Use when..." description.
- **"When to use" section.** Upstream goes straight from the title into the architect paragraph. This copy puts the same ideas in a short "When to use" section first.
- **AGENTS.md is the only agent instruction file.** Follow-lists and "put the always-on rule here" lines that named `CLAUDE.md` now name `AGENTS.md`. Measured token notes in `reference/context-economics.md` still say `CLAUDE.md` because they describe an upstream measurement.

The `metadata` block (`upstream`, `upstream-path`, `upstream-base`) is how `workstation/check-upstream.ps1` finds this skill. Upstream does not have that block.

## agents/ folder

Upstream has 12 agent files in `agents/`, next to `skill/`, not inside it:

- `accountability-lead.md`
- `architect.md`
- `backend-expert.md`
- `backlog-manager.md`
- `doc-librarian.md`
- `frontend-expert.md`
- `issue-maintainer.md`
- `pr-checkin.md`
- `pr-manager.md`
- `qa-engineer.md`
- `report-maker.md`
- `resource-manager.md`

The skill tells Claude to dispatch those names. Upstream's `install.sh` copies them into the project's `.claude/agents/`. They are not part of the skill folder. Installing the skill does not install `.claude/agents/`. This copy does not vendor them. The skill text already points at the upstream `agents/` tree.
