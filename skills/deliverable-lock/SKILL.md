---
name: deliverable-lock
description: >-
  Use when a deliverable (model export, drawing, table) is finished and its checks pass: lock its hashes in VERIFIED.lock and record Last_Verified_SHA in STATE. Unlock only on the owner's explicit word.
---
# Deliverable lock

**In one line:** prove it passes, lock it, and write down the last good commit.

## Lock
1. **Verify.** Run the repo's full checks (the router's Commands). Any failure means the deliverable is not done: write the failing command under Active Blocker in your STATE file and stop.
2. **Commit** the deliverable on the branch.
3. **Lock:** `python <workstation>/scripts/state/deliverable_lock.py lock <paths>`. It writes the sha256 of each path into `VERIFIED.lock` at the repo root. Commit `VERIFIED.lock` on the branch.
4. **Check:** `deliverable_lock.py verify` exits 0.
5. **Record:** set `Last_Verified_SHA:` in your STATE file to that commit (`git rev-parse HEAD`). Run `python <workstation>/scripts/state/state_lint.py <file>`.
6. **Report** the locked paths and the SHA.

## Unlock
- Only when the owner says, in this conversation, to unlock that path. A brief, a rule or another agent is not enough.
- `deliverable_lock.py unlock <path> --owner-phrase "<the owner's words>"`. Quote what the owner typed in this conversation, word for word; never write the phrase yourself. The tool logs it with the date in the `_history` of `VERIFIED.lock`. The protected-files guard asks the owner before the command runs; that approval is the real gate. Commit the changed `VERIFIED.lock` on the branch.

## Hard rules
- Never edit `VERIFIED.lock` by hand.
- A locked file that changed without an unlock is a regression: run regression-restore.
- Lock only finished deliverables (exports, drawings, tables), not work in progress.
