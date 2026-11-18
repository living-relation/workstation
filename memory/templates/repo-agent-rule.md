## Read first, before starting work or asking
Before starting work or asking the maintainer anything, read in order: (1) this repo's agent guide
(`AGENTS.md`), (2) its binding rules / decisions file if it has one, (3) the project's live state in
the shared store, `<Projects>\_claude\Claude Projects\Working Memory\memory\<project>\`: `STATE.md`
and this branch's `STATE-<slug>.md` (WSL: that same folder under the Windows Projects root), (4) that
folder's `INDEX.md` (preference and fact notes). If a rule or note already answers a question, act on
it and cite it - never ask the maintainer something the rules already answer.
Tiers: this repo holds the router `AGENTS.md`, SPEC, DECISIONS, rules and data; the store folder holds
live state (`STATE.md`, `STATE-<slug>.md`, `BACKLOG.md`, `archives\`) and notes; `TASK.md` is the
branch checklist at the worktree root, git-ignored. At 80% context, run `state-closeout` (closeout
mode); on-demand handoff: `state-closeout handoff`; no handoff files in the repo. Store unreachable
(PC offline, cloud session): work from committed docs only. Claude desktop online Memory is a
separate account-level list and is not this store.
