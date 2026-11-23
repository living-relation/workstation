# Agent guide for this repo

## Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md`), (2) `DECISIONS.md`, (3) live state, in this repo (decision D-2026-11-22-state-in-repo):
`STATE.md` at the repo root on main, this branch's `STATE-<slug>.md` (committed on the branch) on a
branch, `BACKLOG.md` and `archives/`. Decisions go to DECISIONS, via `state-closeout`. No HANDOFF/handoffs
files; STATE-<slug> is the handoff. Archive the state file as the PR's last commit (pr-closeout).
(4) Notes only (preferences, machine facts, gotchas; no status) in the memory store:
Project memory: <Projects>\_claude\Claude Projects\Working Memory\memory\workstation\INDEX.md
(WSL: that same folder under the Windows Projects root). If a rule or
note already answers a question, act on it and cite it - never ask the maintainer something the
rules already answer. Claude desktop online Memory is a separate account-level list and is not this
store (work-account behavior unverified).

Read `instructions/projects-AGENTS.md` (shared rules) and `CONTRIBUTING.md` first; follow the hooks in
`.githooks/`. Current status lives only in the root `STATE.md` and open items in `BACKLOG.md`; every
script and hook is listed in `automation.yml`. Before driving the harness.design desktop app, follow section 5b: acquire before use, check in at least every 10 min, and release when done. This repo is public but still generic: no machine-specific, project-specific or
personal content, no secrets, no CAD code or models.

Plugin manifests may be committed: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
`.cursor-plugin/plugin.json`, and `.cursor-plugin/marketplace.json`. They have no `version` field.
The only plugin catalog is `.claude-plugin/marketplace.json` (`workstation-plugins`:
`workstation-core` at `./`). On Claude, turn that plugin on at claude.ai (Customize, Plugins;
paste catalog `living-relation/workstation`, and turn Sync automatically on so updates arrive after merges to main). On Cursor, copy this repo to
`~/.cursor/plugins/local/workstation-core`.
`.cursor-plugin/marketplace.json` lists only this repo's plugin (`source` `.`).
Skills stay in `skills/<name>/SKILL.md`. The plugin ships Claude hooks in `hooks/hooks.json` and Cursor hooks in `hooks/cursor-hooks.json` (the Cursor manifest `hooks` path). No MCP server and no `bin/`.
