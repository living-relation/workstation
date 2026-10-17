---
name: safe-repo-preflight
description: >-
  Use before changing, committing or pushing in any of Daniel's repos: read the
  repo's own rules, hooks and CI first, work on a branch in your own clone or
  worktree, run the required checks, open a PR, never bypass hooks or gates,
  never force-push, and pull ff-only only after a merge you made.
---
# Safe repo preflight

Run before every change, commit or push on Daniel's machines or WSL checkouts.

## Steps
1. **Read the repo's rules first.** Before anything else, read its rules files (AGENTS.md, CLAUDE.md, CONTRIBUTING, DECISIONS), its hooks (`.pre-commit-config.yaml`, `git config core.hooksPath`, `.git/hooks`) and its CI workflows. Follow them. If a planned step would bypass any of them, stop and ask Daniel. The repo's rules win over this skill.
2. **Your own copy.** Work in your own scratch clone, or your own git worktree on a branch. Never write into another bot's or Daniel's working copy, unless the repo's own rules say otherwise (step 1 wins). The only other exception is the ff-only pull in step 10.
3. **Status first.** `git status` and current branch. If the tree is dirty with unrelated work, stop and report; don't pile on. If git shows changes you didn't make, check `git diff --ignore-cr-at-eol`. If it's only line endings, the fix is a repo `.gitattributes` (preferred) or a repo-local `core.autocrlf` on the WSL side, done through a PR.
4. **Branch, never main.** All repo work goes through a PR: make a branch, push it, open a PR. Never edit on `main`/`master`, not even uncommitted, since a fast-forward can wipe it.
5. **Run the checks.** After every edit and before every commit, run the repo's required check scripts and report pass/fail. Never call work done while a check is red.
6. **Scope the commit.** Stage only the files for this task. Don't mix in personal files or unrelated changes.
7. **Never skip a hook.** No `--no-verify` or other skip, not even to push a fix. If a hook or gate fails on a generated or bot-owned file (for example, a generated docs page that a CI workflow publishes), don't touch it: leave it to the repo's workflow, say so in the PR, and ask Daniel.
8. **No secrets, no force-push.** Never print tokens or secrets. Run the repo's secret scanner if it has one (gitleaks or a pre-commit hook), else scan the diff for tokens, passwords and home paths. Never force-push.
9. **Push, PR, merge.** Who may merge follows the repo's rules. Pushing or merging needs Daniel's OK unless a standing rule covers it. After a push, confirm the branch on origin matches what you intended (log/SHA).
10. **After the merge.** The bot that merged pulls, once a PR it opened or merged lands: every local copy (Windows and WSL), fast-forward only. Never overwrite uncommitted changes; if a copy is dirty or has diverged, stop and report. Then clean up only your own branch and worktree, and get Daniel's OK before deleting anything.
11. **If you committed to main by mistake.** Stop pushing. Report. Offer a PR or revert path; don't paper over it.

## Never
- **No surprise pulls.** Nothing scheduled, hooked or run as a routine pulls or overwrites local work.
- **Batch git shortcuts** (pull all, push all, commit all): don't add new ones without Daniel's OK. His existing `ma` helper stays as is.
- **Frozen dependencies.** Some projects freeze specific dependencies; check that project's own rules (AGENTS.md) and never change them.
