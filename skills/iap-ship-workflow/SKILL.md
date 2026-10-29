---
name: iap-ship-workflow
description: >-
  Use for any code change in Spark-Robotic/internal-apps-platform (SparkPDM, SOP Creator, ECR, Inventory): branch off dev, green checks, merge to dev, prune, deploy staging, hand over the test link.
---

# IAP ship workflow

Repo: `Spark-Robotic/internal-apps-platform`
Local clone (Windows): `<Projects>\active\internal-app-platform`
Staging: `10.0.10.6` = `https://internal-dev.sparkrobotic.app/<app>/`

## When to use
The standard ship loop for the Spark Robotic internal-apps-platform repo (SparkPDM, SOP Creator,
ECR, Inventory, and the rest). Feature branch off `dev`, green checks, merge to `dev`, prune,
deploy `dev` to staging over SSH, verify, hand over the test link.

Use this for **any** code change, bug fix, or feature in `internal-apps-platform` /
`internal-app-platform`, whenever work is about to start, commit, push, merge, deploy, or
"refresh staging", and before ending a session with merged work. Use it even if the user only
says "fix this", "ship it", "push it", or "I want to test it".

## Hard rules

- `dev` = staging = where everything is tested. `main` = production.
- Never push or PR to `main`. Only `dev` -> `main` promotions get full review, and only when the
  user asks.
- Every merge to `dev` is followed by a staging deploy. Never skip it, never ask first.
- Always prune the feature branch after merging (remote + local), unless there are uncommitted
  changes or the user's answer is pending.
- Never run `scripts/staging_refresh.sh` (wipes everyone's staging data) unless the user asks.
- Repo docs (`CLAUDE.md`, `AGENTS.md`, `docs/STAGING.md`) win if they define a different flow.

## The loop

1. **Branch.** Sync, then branch off `origin/dev`:
   `git fetch origin` -> `git switch -C dev origin/dev` -> `git switch -c feat/<who>/<topic>`
   One branch per session or task.
2. **Work.** Commit often. Use `git commit -F <msgfile>` (PowerShell mangles multi-line `-m`).
3. **Checks green.** `pnpm typecheck`, `pnpm lint`, `pnpm test` (plus SQL/deno suites if touched).
4. **PR + merge.** Push branch, `gh pr create --base dev`, wait for CI green,
   `gh pr merge --squash --delete-branch`.
5. **Sync + prune.** `git switch -C dev origin/dev` after fetch; `git branch -D feat/...`; `git fetch --prune`.
6. **Deploy to staging** (Git Bash, from the clone):
   - New migrations: probe the box for the last applied number first (the script does not track state;
     others push to dev too), then `SPARK_ENV=dev scripts/apply_migrations.sh --from <n>`.
   - Changed edge functions: `SPARK_ENV=dev scripts/deploy_functions.sh <fn>`.
   - Apps: `./scripts/deploy_all.sh dev` (guards: on dev, clean tree, HEAD == origin/dev).
   - `SPARK_ENV=dev scripts/verify_deploy.sh` must print **VERIFY: PASS**.
7. **Hand over.** Give the user the link(s) for every app the change touched, plus the dev SHA.
   Update `docs/SESSION_STATE.md` (local-only, never committed).

## Windows traps

- Launch Git Bash directly: `& "C:\Program Files\Git\bin\bash.exe" -lc '<script> > <log> 2>&1'`.
  Put multi-step commands in a `.sh` under `_tmp_x/` (gitignored via `.git/info/exclude`).
- Put `_tmp_x/bin` first on PATH (rsync shim, real python3).
- `unset NODE_ENV` and set `npm_config_confirm_modules_purge=false` before pnpm.
- Never run `git status` from a Linux device shell on this clone (leaves `.git/index.lock`).
- Migrations are append-only; never edit an applied one.
