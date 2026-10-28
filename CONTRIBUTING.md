# Contributing

**In scope:** installer and preflight, `workstation.lock.yaml`, `patches/`, the non-CAD skills
(`skills/`: safe-repo-preflight, backup-dryrun-apply, agent-handoff-pack,
wizard, iterative-cleaning, harness-design, deploy-project-watcher,
session-start, repo-cleanup, git-checker, concise), their generated
`skills/<name>.zip` Claude import packages (the pack-skill-zips Action rebuilds them
on the PR; local `scripts/pack-skill-zips.ps1` / `.sh` is optional; do not edit by hand),
`automations/` (routine texts, docs only), agent rules and instruction templates,
workstation helper scripts.

**Never:** CAD code or models (they belong to the CAD repo), part files, binaries, archives
(except the generated Claude-importable `skills/<name>.zip` files owned by pack-skill-zips),
secrets, personal paths or data, batch git shortcuts (scripts that pull/push/merge many repos),
project-specific notes.

**Process:** branch -> PR -> owner's yes. No edits on `main`, no force-push.
The pack-skill-zips Action commits `skills/*.zip` onto the PR branch (same-repo PRs
only). It never pushes to main. If zips on main are stale, it opens or updates a PR.

**Follow each repo's own rules:** read `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, any decisions
log, hooks and CI gates first. Never bypass a hook or gate (no `--no-verify`, no direct pushes of
generated or bot-owned files) without the owner's explicit yes.

**Upstream tools:** an entry in `workstation.lock.yaml` with version and sha256. Small upstream
edits are files in `patches/`, never forks.

**INVENTORY.md** is generated - edit the lock, then run `scripts/gen-inventory.py`.
