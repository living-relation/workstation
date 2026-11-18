---
name: regression-restore
description: >-
  Use when a check or VERIFIED.lock shows a deliverable that passed before is now broken: stop, restore only the broken paths from Last_Verified_SHA, add a one-line Never-do rule, update STATE.
---
# Regression restore

**In one line:** do not argue with a broken deliverable; put the last good copy back and write down how it broke.

## Steps
1. **Stop.** Do not try to fix it in chat.
2. **Find the facts.** `Last_Verified_SHA` from your STATE file. The broken paths from `python <workstation>/scripts/state/deliverable_lock.py verify` or the failing check. What changed them: `git log --oneline <sha>..HEAD -- <paths>`.
3. **Ask.** Show the user the paths, the SHA and the commits that changed them. Wait for the yes.
4. **Keep current work.** Commit any uncommitted changes on the branch first, so git history holds them.
5. **Restore, on the branch (never on main):** `git restore --source <Last_Verified_SHA> -- <broken paths>`. Only those paths. Never `git reset --hard`, never restore the whole tree, never force-push.
6. **Re-check.** `deliverable_lock.py verify` and the repo's checks pass. If not, write the failing command under Active Blocker and stop.
7. **Never do.** Add one line to the matching `.claude/rules/<domain>.md`: `Never do: <the act> (broke <path>, <date>)`. Run `python <workstation>/scripts/state/rules_sync.py`.
8. **Update STATE:** Active Blocker `NONE`, and a `[NEXT]` to redo the wanted change safely. Run `state_lint.py`. Commit the restore and the rule on the branch.
9. **Report** the restored paths, the SHA and the new rule. If the chat is full of the failed attempts, suggest a new chat (state-closeout `handoff`).
