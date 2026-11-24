# Contributing

**In scope:** installer and preflight, `workstation.lock.yaml`, `patches/`, the non-CAD skills
(`skills/`: safe-repo-preflight, backup-dryrun-apply, agent-handoff-pack,
wizard, iterative-cleaning, deploy-project-watcher,
session-start, repo-cleanup, git-checker, concise, pr-closeout,
coordinator-kit, state-closeout, state-init, deliverable-lock,
regression-restore, debug-root-cause, review-feedback),
`automations/` (routine texts, docs only), agent rules and instruction templates,
workstation helper scripts, the plugin manifests in `.claude-plugin/` and
`.cursor-plugin/` (no `version` field; skills stay in `skills/`), and the
plugin hooks under `hooks/`.

**Never:** CAD code or models (they belong to the CAD repo), part files, binaries, archives,
secrets, personal paths or data, batch git shortcuts (scripts that pull/push/merge many repos),
project-specific notes.

**Process:** branch -> PR -> owner's yes. No edits on `main`, no force-push.

**Follow each repo's own rules:** read and follow the repo's `AGENTS.md`, decisions,
`CONTRIBUTING.md`, hooks, and CI. Their rules and decisions still bind. Never bypass a hook or
gate (no `--no-verify`, no direct pushes of generated or bot-owned files) without the owner's
explicit yes. If an older agent doc's layout differs from the workstation-core template, that
layout is migrated into the template, keeping every rule. A layout difference is not a blocker
or a reason to stop.

**Upstream tools:** an entry in `workstation.lock.yaml` with version and sha256. Small upstream
edits are files in `patches/`, never forks.

**INVENTORY.md** is generated - edit the lock, then run `scripts/gen-inventory.py`.
