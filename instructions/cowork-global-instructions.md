## Memory
Two stores, different jobs. Local Working Memory on each PC holds preference and fact notes (Claude Code, Cowork and Cursor); live project state lives in each repo. Account Memory (Settings > Your Claude > Memory) is allowed for general facts about me. Duplicates are OK. Never sync the two. Never treat account Memory as the project source of truth.
Tiers: the repo (git) holds the router AGENTS.md, SPEC, DECISIONS, rules, data and live state (STATE.md, STATE-<slug>.md committed on its branch, BACKLOG.md, archives/ at the repo root). The local store's project folder holds notes only (preferences, machine facts, gotchas), listed in INDEX.md. TASK.md is the branch checklist at the worktree root, git-ignored. Never put project state in account Memory or the local store.
At 80% context, run the state-closeout skill (closeout mode). On-demand handoff: state-closeout handoff. No HANDOFF or handoffs/ files; STATE-<slug>.md is the handoff. Store unreachable (PC offline, cloud session): live state is still in the repo; only notes are missing.
Do not look for a `~\.claude\working-memory` link. The local store's path is in that PC's Projects folder (`_claude\Claude Projects\Working Memory\memory`).

## Git and project folders
- In a git repo, commit often, keep local and remote in sync, and stay on one feature branch unless I say otherwise. Check comments on commits and PRs, and resolve the valid ones.
- Some project folders aren't git repos. Never run git init in them or commit anything there.
- Pulls are fast-forward only, and never force-push.
- Don't start or stop the workstation workers. I run those myself.

## Extra end-of-turn lines when working in a repo
- 🌿 Branch checked out
- 🔀 PRs opened or merged
- 📝 Uncommitted, untracked, or stashed changes
- 📋 Tasks finished, and the name of the plan or doc they came from
- 📊 Context used, if you can tell

## Repos
- Follow each repo's AGENTS.md, decisions, CONTRIBUTING.md, hooks, and CI before changing anything. Their rules and decisions still bind. If an older agent doc's layout differs from the workstation-core template, that layout is migrated into the template, keeping every rule; a layout difference is not a blocker or a reason to stop.
- Never bypass a hook or gate without my explicit yes: no `--no-verify`, no skipping CI, no direct pushes of generated or bot-owned files.
- Branch + PR, never force-push, one repo at a time (no batch pull/push), `git pull --ff-only`.

## harness.design
- Before driving the harness.design desktop app (clicking or computer-use, including Dan by hand), hold the per-PC harness.design lock: follow section 5b "harness.design lock" in the workstation repo `instructions/projects-AGENTS.md`. Acquire before use, check in at least every 10 min, and release when done. Never delete the lock file by hand. MCP cloud tools do not need the lock. An agent delete goes through the desktop app under the lock.
