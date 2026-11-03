# Continuity notes

Write these fields into the repo's one state file (the one `AGENTS.md` names, for example `STATE.md`). Do not create `docs/SESSION_STATE.md`, `docs/PHASE_HANDOFF.md`, or any other progress file. Do not put them in memory or outside the repo. The handoff skill updates the state file on disk only; it does not commit or push.

If the project has no state file, say so and show the note in chat. Do not invent a second file. Offer to add the one file `AGENTS.md` should name, and wait for a yes.

## Fields to keep current in the state file

Short continuity for the next session. Do not let it become a history dump.

- **Last updated** and **git tip** (SHA, branch, whether it matches origin, CI).
- **Where the build stands** and **what just changed**.
- **In flight** — anything another agent must not collide with.
- **Next exact step** — one concrete slice.
- **Gotchas** and **do not do**.
- **Uncommitted, untracked, or unpushed work.**

## Next-chat paste block

Print this as a single markdown fenced block (` ```text `) so it copies cleanly. Fill from real state. No placeholders, no omitted sections. This block is for the next chat. The state file is the record.

```text
NEXT CHAT HANDOFF — paste this as the first message in a new chat.

Project: [name]
Workspace: [absolute path]
Clone: [git clone path, or "none, not a git repo (docs on disk only)"]
Branch: [working branch] (do not push [protected] unless I explicitly order it)
Tip: [short SHA] — local [matches / does not match] origin/[branch]
CI: [green / waiting / skipped-owed / n/a]
Test/deploy: [URL + SHA, or owed, or n/a]

Read first:
1. [standing rules file]
2. [repo state file named by AGENTS.md]

What just landed:
- [bullet]

In flight (do not collide / finish this first):
- [bullet, or "none"]

Next exact step:
[one concrete slice]

Gotchas:
- [bullet]

Do not:
- [frozen rules]

Unpushed / unfinished:
- [files, failed push, or "none"]
```
