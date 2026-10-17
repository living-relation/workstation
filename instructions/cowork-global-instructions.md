## Working memory
Working memory lives in %USERPROFILE%\.claude\working-memory. Never create another memory store. Each project has its own folder there, named after the project folder in lowercase with dashes (for example my-project), with an INDEX.md. At the start of a task, read that project's INDEX.md. For work with no project, use _unassigned. Save new notes there, signed with your agent name. Follow any pointer one step only. Never write in cursor-notes or claude-memory, and never commit memory to git.

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
