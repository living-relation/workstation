---
name: session-start
description: >-
  Use when starting any new chat, task or session in a repo or project folder,
  before reading code or changing anything: finds the project's true current
  state cheaply, detects whether the last session was cut off (usage limit,
  crash), checks GitHub/branches/worktrees, and writes one short state note.
  Read-only. Run it yourself or let a bot call it.
---
# Session start

**In one line:** figure out where the project really stands, change nothing,
then say so in one short note.

Works the same in Grok, Claude Code and Cursor. Anyone can run it by hand
("run session-start"), or a bot can call it at the start of a session.

**Why it exists:** a session can stop cold at a usage limit. A stopped session
can't save anything, so nothing may rely on "the end of a session". The *next*
session finds the leftovers and rebuilds the picture.

---

## Hard rules
- **Read-only.** No edits, commits, pulls, pushes, deletes or lock releases.
  The only file you write is the state note (step 8), and only if allowed.
- **Never read or print secrets** (`.env*` values, tokens, keys).
- **The repo beats memory.** If Claude/Cursor memory disagrees with the repo,
  trust the repo and flag the stale memory.
- **Report conflicts, never resolve them.** Contradictions go in the note as
  open questions for the user.

---

## Steps

### 1. Read the rules first (stop when you have the answer)
1. Root `AGENTS.md`. `CLAUDE.md` should just be `@AGENTS.md` (+ Claude-only lines).
2. The nearest nested `AGENTS.md` above the folder you'll work in (closest wins).
3. `README.md`.
4. The one state file `AGENTS.md` names (e.g. `STATE.md`), the to-do list, the log.
   If no state file is named, say "no live state file". Don't guess from random
   PLAN/HANDOFF files.
5. `.cursor/rules/*.mdc` with `alwaysApply: true`, if present.

Skip: `node_modules`, build output, caches, `_archive`/`old` folders, other
worktrees' copies, other modules' agent files.

### 2. Did the last session stop early?
Check each sign. Any one = **"last session stopped early"**.

| Sign | How to check |
|---|---|
| A lock is still held | lock files (e.g. `*.lock`, app/CAD locks) that name an agent or session |
| Outputs newer than the log | files changed after the log's last line (`git status`, file times) |
| Last transcript entry isn't a final reply | last entry of the newest session file is a tool call, tool result or plan, not an answer |
| Sure usage-limit stop | last entry has `"model":"<synthetic>"` **and** text like "hit your … limit" |
| Unapproved plan | a plan in `~/.claude/plans/` newer than the log |

Session files: Claude Code keeps them under `~/.claude/projects/<project>/*.jsonl`.
Read only the last few lines of each.

### 3. Check GitHub and branches, not just `main`
Run (read-only):
```bash
gh pr list --author @me --state open      # open PRs
git worktree list                         # extra checkouts
git branch --no-merged main               # unmerged local branches
git branch -r --no-merged origin/main     # unmerged remote branches
```
Note where live work actually is (it may be on a branch, not `main`).
If `gh` isn't signed in, say so and skip; don't start a sign-in.

### 4. Look for promised reports that don't exist
If a task card, plan or log says "will write a report/handoff/note at the end",
check the file exists. If not, flag it: **"promised, never written: …"**.

### 5. List facts that live outside the repo
Decisions or plans that exist only in a chat, memory, email or another machine.
List each as **"outside the repo: …"** with where it lives. Don't copy it in
here; cleanup does that.

### 6. Measure orientation cost
1. Add up the characters of every file you had to read to get oriented.
2. Tokens ≈ characters ÷ 4.
3. If over the cap (default **30k tokens**, or the cap `AGENTS.md` sets),
   warn: **"Orienting costs ~Nk tokens (cap 30k). Cleanup recommended."**

### 7. If the last session stopped early
Run the **agent-handoff-pack** skill (read-only sweep) to rebuild where things
stopped. Include leftover plans in `~/.claude/plans/`, locks, outputs newer than
the log, open PRs and branches. The old session doesn't need to do anything.
Never release a lock or finish someone's step without the user's yes.

### 8. Write one short state note
Put it in the repo's state file if one exists and writing it is allowed;
otherwise just show it in chat. Keep it under ~20 lines:

```markdown
**Goal now:** <one sentence: the current objective>
**Last session:** finished | stopped early (<which sign>) — handoff: <path>
**Where work is:** branch <x>, PR #N (open), worktrees: <list>
**Open:** <top 3 items, each with a date>
**Flags:** promised-not-written: … | outside the repo: … | stale memory: …
**Orientation cost:** ~Nk tokens
Cleanup needed, see CLEANUP-PLAN.md      <- only if step 9 applies
```

### 9. If the repo is messy
Mess = cost over the cap, more than one state/decisions/plan file, task cards
without a status line, handoffs in throwaway folders, or rules repeated across
agent files.
1. Add the single line **"Cleanup needed, see CLEANUP-PLAN.md"** to the note.
2. Offer: "Want me to run **repo-cleanup**? It runs as its own session, after
   this one's first task, and changes nothing without your yes."
3. Don't clean anything here.

### 10. Tell the user, then start the real work
Show the note. Then follow the user's instructions for the actual task.

---

## Rules for the working session (after session start)
Tell the agent these, and follow them:
1. **Log after every finished step**, one short line, never wait for the end:
   `2026-10-23 21:40 J1 done, 2.99 kg -> out/j1.step`
   The log is never more than one step behind.
2. **Give the path** of any saved output (plan, report, file) in that log line.
3. **Log `PR #N opened`** right after creating a PR.
4. **Every task card gets a status line** (`Status: open` / `Status: done <date>`).
5. **Decisions go in one decisions file**, one dated line each.
6. **Handoffs never go in throwaway folders** (`output/`, `tmp/`, scratch dirs).
7. **Finished to-dos:** delete from the to-do list; add one dated line to the
   decisions file or changelog.

---

## If the basics are missing
Offer (don't create without a yes): `AGENTS.md` (rules, under ~150 lines,
concrete commands, no status), `CLAUDE.md` = `@AGENTS.md`, one state file,
one log, one decisions file.

## How it starts automatically (optional setup)
- **Cursor:** a `.cursor/rules/session-start.mdc` with `alwaysApply: true`:
  "Run the session-start skill first."
- **Claude Code:** one line in `~/.claude/CLAUDE.md`: "At session start, use the
  session-start skill."
- **Grok / other bots:** call it by name at the start of a task.
