# Contributing

**In scope:** installer and preflight, `workstation.lock.yaml`, `patches/`, the non-CAD skills
(`skills/`: safe-repo-preflight, backup-dryrun-apply, agent-handoff-pack,
wizard, iterative-cleaning, harness-design, deploy-project-watcher,
session-start, repo-cleanup, git-checker, concise),
`automations/` (routine texts, docs only), agent rules and instruction templates,
workstation helper scripts.

**Never:** CAD code or models (they belong to the CAD repo), part files, binaries, archives,
secrets, personal paths or data, batch git shortcuts (scripts that pull/push/merge many repos),
project-specific notes.

**Process:** branch -> PR -> owner's yes. No edits on `main`, no force-push.

**Follow each repo's own rules:** read `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, any decisions
log, hooks and CI gates first. Never bypass a hook or gate (no `--no-verify`, no direct pushes of
generated or bot-owned files) without the owner's explicit yes.

**Upstream tools:** an entry in `workstation.lock.yaml` with version and sha256. Small upstream
edits are files in `patches/`, never forks.

**INVENTORY.md** is generated - edit the lock, then run `scripts/gen-inventory.py`.
