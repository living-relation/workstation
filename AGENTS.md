# Agent guide for this repo

## Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md`), (2) its binding rules / decisions file if it has one, (3) live state,
by the tier rule: the project's folder in the shared memory store,
`<Projects>\_claude\Claude Projects\Working Memory\memory\<project>\` (WSL: that same folder under the
Windows Projects root), holds `STATE.md`, this branch's `STATE-<slug>.md`, `BACKLOG.md` and `archives\`;
until this repo's state moves there, its root `STATE.md` is the root STATE. Decisions go to DECISIONS,
via `state-closeout` (its `handoff` mode replaces handoff files). (4) That folder's `INDEX.md`
(preferences, rules and cross-project facts only). If a rule or
note already answers a question, act on it and cite it - never ask the maintainer something the
rules already answer. Claude desktop online Memory is a separate account-level list and is not this
store (work-account behavior unverified).

Read `agents/projects-AGENTS.md` (shared rules) and `CONTRIBUTING.md` first; follow the hooks in
`.githooks/`. Current status and open items live only in the root STATE named above; every
script and hook is listed in `automation.yml`. Before driving Autodesk Fusion, follow the Fusion lock rule in `agents/projects-AGENTS.md` section 5. Before driving the harness.design desktop app, follow section 5b: acquire before use, check in at least every 10 min, and release when done. Fusion add-in clones update from `workstation/fusion-addins/update-fusion-addins.ps1` (junctions in the AddIns folder, fast-forward only, skip a dirty tree, a non-default branch, or a branch with no upstream). That script does not restart Fusion and does not drive Fusion, so it does not take the Fusion lock. It is manual only (the Update Fusion add-ins shortcut): no scheduled task. `install.ps1` and `uninstall.ps1` remove the old task `Workstation-UpdateFusionAddins` if present. See `workstation/fusion-addins/README.md`. This repo is public but still generic: no machine-specific, project-specific or
personal content, no secrets, no CAD code or models.

Plugin manifests may be committed: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
`.cursor-plugin/plugin.json`, and `.cursor-plugin/marketplace.json`. They have no `version` field.
The only plugin catalog is `.claude-plugin/marketplace.json` (`workstation-plugins`:
`workstation-core` at `./`). On Claude, turn that plugin on at claude.ai (Customize, Plugins;
paste catalog `living-relation/workstation`, and turn Sync automatically on so updates arrive after merges to main). On Cursor, copy this repo to
`~/.cursor/plugins/local/workstation-core`.
`.cursor-plugin/marketplace.json` lists only this repo's plugin (`source` `.`).
Skills stay in `skills/<name>/SKILL.md`. The plugin ships Claude hooks in `hooks/hooks.json` and Cursor hooks in `hooks/cursor-hooks.json` (the Cursor manifest `hooks` path). No MCP server and no `bin/`.
