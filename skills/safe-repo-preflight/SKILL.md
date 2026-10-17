---
name: safe-repo-preflight
description: >-
  Use before committing or pushing on any of Daniel’s repos: check branch, dirty
  state, whether main is protected / needs a PR, and never force-push.
---
# Safe repo preflight

Run before every commit or push on Daniel’s machines or WSL checkouts.

## Steps
1. **Status first.** `git status` and current branch. If the tree is dirty with unrelated work, stop and report—don’t pile on.
2. **Branch policy.** Prefer a feature branch. Do not commit to `main`/`master` until you know that repo allows it.
3. **Protection check.** Before the first commit on a repo you haven’t verified this session, check whether default-branch pushes need a PR (GitHub branch protection / required checks). If protected, commit on a branch and open a PR instead of pushing main.
4. **ff-only.** Pull/rebase with fast-forward only. Never force-push unless Daniel explicitly asks in that chat.
5. **Scope the commit.** Stage only the files for this task. Keep toolkit pushes to the toolkit commit; don’t mix personal parts.
6. **Verify remote.** After push, confirm origin matches what you intended (log/sha).
7. **If you already committed to main by mistake.** Stop pushing. Report. Offer a PR or revert path—don’t paper over it.

## Known examples
- st185: main protected (PR + checks).
- fairsolid / PowerTune / handbuilt-models toolkit: direct push has been allowed—still verify each time.
