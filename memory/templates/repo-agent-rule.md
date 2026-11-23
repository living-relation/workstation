## Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md`), (2) its binding rules / decisions file if it has one, (3) the project's live state in
this repo: `STATE.md` and this branch's `STATE-<slug>.md` at the repo root, (4) the notes in the
shared store, `<Projects>\_claude\Claude Projects\Working Memory\memory\<project>\INDEX.md` (WSL:
that same folder under the Windows Projects root; preferences, machine facts, gotchas). If a rule or note already answers a question, act on
it and cite it - never ask the maintainer something the rules already answer.
Tiers (decision 2026-11-22): this repo holds the router `AGENTS.md`, SPEC, DECISIONS, rules, data and
live state (`STATE.md`, `STATE-<slug>.md` committed on its branch, `BACKLOG.md`, `archives/`); the
store folder holds notes only; `TASK.md` is the branch checklist at the worktree root, git-ignored.
At 80% context, run `state-closeout` (closeout mode); on-demand handoff: `state-closeout handoff`; no
`HANDOFF` or `handoffs/` files (`STATE-<slug>.md` is the handoff). A PR's last commit archives the
state file. Store unreachable (PC offline, cloud session): live state is still in the repo. Claude desktop online Memory is a
separate account-level list and is not this store.
