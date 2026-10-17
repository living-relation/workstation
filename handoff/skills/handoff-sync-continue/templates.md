# Continuity doc templates

Use these only when the project has no living handoff docs yet. If it already names files, update those instead of creating a parallel set. Put both files **inside the git clone** (no git repo: in the project folder; never `git init` for this). The handoff skill updates these on disk only; it does not commit or push.

Suggested paths: `docs/SESSION_STATE.md` and `docs/PHASE_HANDOFF.md` (or whatever `AGENTS.md` already points at).

## SESSION_STATE.md

Short continuity for the next session. Keep it current; do not let it become a history dump.

```markdown
# Session state — [Project]

**Last updated:** YYYY-MM-DD
**Git tip:** `SHA` — in sync with `origin/<branch>`, CI [green / waiting / n/a]
**Test/deploy:** [SHA and where it is running, or n/a]

## Read first (new session)

1. `AGENTS.md` — standing rules
2. Phase handoff — progress + tip SHA
3. This file
4. [Work queue / roadmap if one exists]

## Where the build stands

| Piece | State |
|-------|-------|
| … | ✅ / ⏳ / ❌ |

## What just changed

[One short paragraph.]

## In flight — read before continuing

[Anything another agent must not collide with.]

## Next exact steps

1. [Next slice]
2. …

## Gotchas that cost time

- …

## Do not do

- Push the protected default branch unless explicitly ordered
- Forget to tell the next chat about uncommitted or unpushed work
```

## PHASE_HANDOFF.md

Living progress record. Session state is "where we are"; this file is "what landed and the tip SHA."

```markdown
# [Project] — Phase handoff (living)

**Last updated:** YYYY-MM-DD
**Branch tip:** `SHA` on `origin/<branch>` (in sync, CI [status])
**Working branch:** `<branch>` — do not push `<protected>` unless explicitly ordered

> After every meaningful slice: update this file **and** session state on disk. Do not leave progress only in chat. (Commit and push are the user's choice; the handoff skill does not do them.)

## Progress

| # | Step | Status |
|---|------|--------|
| 1 | … | ✅ / ⏳ / ⬜ |

## Next exact step

[One concrete slice.]

## Git status (report only)

1. Durable work lives in the git clone on the working branch (when a repo exists).
2. After a slice: note uncommitted, untracked, or unpushed work in the handoff docs and paste block.
3. Do not commit or push as part of the handoff skill.

## Notes from this slice

[What landed, blockers, decisions.]
```

## Next-chat paste block

Print this as a single markdown fenced block (` ```text `) so it copies cleanly. Fill from real state. No placeholders, no omitted sections.

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
2. [phase handoff path]
3. [session state path]
4. [work queue path if any]

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
