# Contributing

**In scope:** installer and preflight, `workstation.lock.yaml`, `patches/`, the non-CAD skills
(`skills/`: safe-repo-preflight, backup-dryrun-apply, agent-handoff-pack,
wizard, iterative-cleaning, harness-design, deploy-project-watcher,
session-start, repo-cleanup, git-checker, concise), their generated
`skills/<name>.zip` Claude import packages (rebuild: `scripts/pack-skill-zips.ps1` /
`scripts/pack-skill-zips.sh`; do not edit by hand),
`automations/` (routine texts, docs only), agent rules and instruction templates,
workstation helper scripts.

**Never:** CAD code or models (they belong to the CAD repo), part files, binaries, archives
(except the generated Claude-importable `skills/<name>.zip` files owned by pack-skill-zips),
secrets, personal paths or data, batch git shortcuts (scripts that pull/push/merge many repos),
project-specific notes.

**Process:** branch -> PR -> owner's yes. No edits on `main`, no force-push.
Exception: the pack-skill-zips GitHub Action may commit only `skills/*.zip` on main
(no protection bypass; if main later requires a PR, switch that Action to open a PR).

**Follow each repo's own rules:** read `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, any decisions
log, hooks and CI gates first. Never bypass a hook or gate (no `--no-verify`, no direct pushes of
generated or bot-owned files) without the owner's explicit yes.

**Upstream tools:** an entry in `workstation.lock.yaml` with version and sha256. Small upstream
edits are files in `patches/`, never forks.

**INVENTORY.md** is generated - edit the lock, then run `scripts/gen-inventory.py`.
