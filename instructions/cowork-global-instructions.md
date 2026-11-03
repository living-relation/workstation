## Memory
Account Memory (Settings > Your Claude > Memory) is facts about me. It is not the project note store, and it does not sync with files on disk.
Project status, progress, next steps, PR and branch state, TODOs and handoffs go in that project's repo state file (the one its AGENTS.md names, for example STATE.md).
Do not write project progress into Memory. The Claude Code file store on each PC is a separate record of preferences, rules and cross-project facts. This chat does not maintain that store.

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
- Follow each repo's own rules: read its AGENTS.md, CLAUDE.md, CONTRIBUTING.md, decisions log, hooks and CI before changing anything.
- Never bypass a hook or gate without my explicit yes: no `--no-verify`, no skipping CI, no direct pushes of generated or bot-owned files.
- Branch + PR, never force-push, one repo at a time (no batch pull/push), `git pull --ff-only`.

## Fusion
- Before driving Autodesk Fusion, hold the per-PC Fusion lock: follow section 5 "Fusion lock" in the workstation repo `agents/projects-AGENTS.md`. Check in at least every 10 min; release when done.
