# Agent guide for this repo

## Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md` / `CLAUDE.md`), (2) its binding rules / decisions file if it has one, (3) this repo's
state file (the one the agent guide names; here `STATE.md`: status, progress, next steps, PR and
branch state, TODOs, handoffs), (4) the project's folder in the Claude Code shared memory store
`<Projects>\_claude\Claude Projects\Working Memory\memory\<project>\INDEX.md` (preferences, rules
and cross-project facts only; WSL: that same folder under the Windows Projects root). If a rule or
note already answers a question, act on it and cite it - never ask the maintainer something the
rules already answer. Claude desktop online Memory is a separate account-level list and is not this
store (work-account behavior unverified).

Read `agents/projects-AGENTS.md` (shared rules) and `CONTRIBUTING.md` first; follow the hooks in
`.githooks/`. Current status and open items live only in `STATE.md` (the one state file); every
script and hook is listed in `automation.yml`. Before driving Autodesk Fusion, follow the Fusion lock rule in `agents/projects-AGENTS.md` section 5. Before driving the harness.design desktop app, follow section 5b: acquire before use, check in at least every 10 min, and release when done. This repo is public but still generic: no machine-specific, project-specific or
personal content, no secrets, no CAD code or models.
