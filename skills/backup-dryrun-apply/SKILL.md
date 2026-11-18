---
name: backup-dryrun-apply
description: >-
  Use for installs, reorganizations, or folder moves on the owner’s PC: broadcast a
  heads-up, hash-backed backup, dry-run, pause warning, real apply, verify
  against backup, archive, then all-clear.
---
# Backup, dry-run, then apply

Use for workstation installs, folder merges, archives, or any destructive-ish change on the owner’s PC.

## Steps
1. **Heads-up.** Tell the bots that matter a change is coming (what and roughly when).
2. **Backup with hashes.** Copy affected files to a dated folder under `_scratch` or `_archive` prep; record hashes so you can prove the backup.
3. **Dry-run.** Run the installer or move plan with `-WhatIf` / equivalent (or a copy map listing every source and destination). Fix surprises before the real run.
4. **Pause warning.** Broadcast that the real run is about to start so other bots don’t write the same trees.
5. **Apply.** Run the real change once.
6. **Verify.** Compare live files to the backup hashes; confirm expected new state.
7. **Archive + where the outcome goes.** Move the backup into `_archive` with a short README for undo. That README is how to undo the copy, not the project status. Record the outcome with state-closeout, by the tier rule: live status and the next step go in your STATE file in the memory store (`STATE.md`, or `STATE-<slug>.md` on a branch); a decision goes to the repo's DECISIONS. Write a memory note (`INDEX.md`) only when a new preference, rule or cross-project fact turned up, once.
8. **All-clear.** Tell the bots they can resume. If a StopSubagent(all) was used, check what other agents’ in-flight work got cancelled and restart only what’s still needed.

## Hard rules
- Destructive steps need the owner’s yes.
- Only the owner deletes projects.
- Don’t disable the owner’s cloud sync client.
- Protected destination folders (check shared memory, e.g. a permanent models home) are copy-into only: never archive, move, clean up, or delete them, and never pick them as a backup source to be moved away. Copy files in; leave the originals where they were until the owner says otherwise.
- If a destination is under a cloud-synced folder, let sync finish before verifying hashes.
