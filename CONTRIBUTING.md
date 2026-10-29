# Contributing

**In scope:** installer and preflight, `workstation.lock.yaml`, `patches/`, the non-CAD skills
(`skills/`: safe-repo-preflight, backup-dryrun-apply, agent-handoff-pack,
wizard, iterative-cleaning, harness-design, deploy-project-watcher,
session-start, repo-cleanup, git-checker, concise, pr-closeout,
iap-ship-workflow), their generated
`skills/<name>.zip` Claude import packages (the skill-zips CI bot rebuilds them
on the PR; local `scripts/pack-skill-zips.ps1` / `.sh` is optional; do not edit by hand),
`automations/` (routine texts, docs only), agent rules and instruction templates,
workstation helper scripts.

**Never:** CAD code or models (they belong to the CAD repo), part files, binaries, archives
(except the generated Claude-importable `skills/<name>.zip` files owned by pack-skill-zips),
secrets, personal paths or data, batch git shortcuts (scripts that pull/push/merge many repos),
project-specific notes.

**Process:** branch -> PR -> owner's yes. No edits on `main`, no force-push
(except the skill-zips CI bot may `git push --force-with-lease` the
`chore/skill-zips` bot branch only).
The skill-zips CI bot commits `skills/*.zip` onto the PR branch (same-repo PRs
only, and never when the PR head is main). It never pushes to main. If zips on
main are stale, it resets `chore/skill-zips` to `origin/main` and opens or updates
that one PR.

Owner settings this Action needs (GitHub repo, not in git):
- Actions → General → **Allow GitHub Actions to create and approve pull requests**
  (`GITHUB_TOKEN` PRs otherwise get no checks; the Action also runs `gh workflow run`
  on the new commit).
- A ruleset on `main` that blocks direct pushes (this Action still refuses to push
  if a PR head is main).

**Follow each repo's own rules:** read `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, any decisions
log, hooks and CI gates first. Never bypass a hook or gate (no `--no-verify`, no direct pushes of
generated or bot-owned files) without the owner's explicit yes.

**Upstream tools:** an entry in `workstation.lock.yaml` with version and sha256. Small upstream
edits are files in `patches/`, never forks.

**INVENTORY.md** is generated - edit the lock, then run `scripts/gen-inventory.py`.
