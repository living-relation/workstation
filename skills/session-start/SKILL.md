---
name: session-start
description: >-
  Use when starting any new chat, task or session in a repo or project folder,
  before reading code or changing anything: finds the project's true current
  state cheaply, detects whether the last session was cut off (usage limit,
  crash), runs git-checker and a cheap drift check, reports, then asks the user
  before each follow-up (repo-cleanup, iterative-cleaning, fixes, handoff,
  PR hook install). Nothing runs automatically. Any project folder.
---
# Session start

**In one line:** figure out where the project really stands, change nothing, then say so in one short note.

Works the same in Grok, Claude Code and Cursor. It runs only when the user calls it ("run session-start").

**Why it exists:** a session can stop cold at a usage limit. A stopped session can't save anything, so nothing may rely on "the end of a session". The *next* session finds the leftovers and rebuilds the picture.

---

## Hard rules
- **Steps 1-8 are read-only.** No edits, commits, pulls, pushes, deletes or lock releases. The only file written there is the state note, and only if allowed. Anything that changes the repo happens only in step 9, after the user says yes, through **safe-repo-preflight**: branch + PR, never force-push, never skip hooks, every deletion waits for the user's yes.
- **Nothing is automatic.** Only the read-only checks run on their own. Every action step in step 9 is one clear question to the user, quoting the finding that triggered it; run it only on his yes. A no or a dismissed question is final for this session.
- **Only this skill offers the chain.** Every other skill run alone does only its own job and may just suggest the next one.
- **Never read or print secrets** (`.env*` values, tokens, keys).
- **The repo beats memory.** If Claude/Cursor memory disagrees with the repo, trust the repo and flag the stale memory.
- **Report conflicts, never resolve them.** Contradictions go in the note as open questions for the user.

---

## Steps

### 1. Read the rules first (stop when you have the answer)
1. Root `AGENTS.md`. `CLAUDE.md` should just be `@AGENTS.md` (+ Claude-only lines).
2. The nearest nested `AGENTS.md` above the folder you'll work in (closest wins).
3. `README.md`.
4. The one state file `AGENTS.md` names (e.g. `STATE.md`), the to-do list, the log. If no state file is named, say "no live state file". Don't guess from random PLAN/HANDOFF files.
5. `.cursor/rules/*.mdc` with `alwaysApply: true`, if present.

Skip: `node_modules`, build output, caches, archive/`old` folders, other worktrees' copies, other modules' agent files.

### 2. Did the last session stop early?
Check each sign. Any one = **"last session stopped early"**.

| Sign | How to check |
|---|---|
| A lock is still held | lock files (e.g. `*.lock`, app locks) that name an agent or session |
| Outputs newer than the log | files changed after the log's last line (`git status`, file times) |
| Last transcript entry isn't a final reply | last entry of the newest session file is a tool call, tool result or plan, not an answer |
| Sure usage-limit stop | last entry has `"model":"<synthetic>"` **and** text like "hit your … limit" |
| Unapproved plan | a plan in `~/.claude/plans/` newer than the log |

Session files: Claude Code keeps them under `~/.claude/projects/<project>/*.jsonl`. Read only the last few lines of each.

### 3. Health check: run git-checker, then GitHub
Run the **git-checker** skill on this project (read-only; `git fetch --prune` only), with its optional Generated-outputs and Deployed-copies checks if the repo lists them. Keep its verdict and any `STALE-OUTPUT` lines for step 9. Then (read-only):
```bash
gh pr list --author @me --state open      # open PRs
git worktree list                         # extra checkouts
git branch --no-merged main               # unmerged local branches
git branch -r --no-merged origin/main     # unmerged remote branches
```
Note where live work actually is (it may be on a branch, not `main`). If `gh` isn't signed in, say so and skip; don't start a sign-in.

### 4. Look for promised reports that don't exist
If a task card, plan or log says "will write a report/handoff/note at the end", check the file exists. If not, flag it: **"promised, never written: …"**.

### 5. List facts that live outside the repo
Decisions or plans that exist only in a chat, memory, email or another machine. List each as **"outside the repo: …"** with where it lives. Don't copy it in here; cleanup does that.

### 6. Measure orientation cost
1. Add up the characters of every file you had to read to get oriented.
2. Tokens ≈ characters ÷ 4.
3. If over the cap (default **30k tokens**, or the cap `AGENTS.md` sets), warn: **"Orienting costs ~Nk tokens (cap 30k). Cleanup recommended."**

### 7. If the last session stopped early
Ask the user: "Last session stopped early (<sign>). Run **agent-handoff-pack** to rebuild where it stopped?" On yes, run the skill (read-only sweep) to rebuild where things stopped. Include leftover plans in `~/.claude/plans/`, locks, outputs newer than the log, open PRs and branches. The old session doesn't need to do anything. Never release a lock or finish someone's step without the user's yes.

### 8. Write one short state note
Put it in the repo's state file if one exists and writing it is allowed; otherwise just show it in chat. Keep it under ~20 lines:

```markdown
**Goal now:** <one sentence: the current objective>
**Last session:** finished | stopped early (<which sign>) — handoff: <path>
**Where work is:** branch <x>, PR #N (open), worktrees: <list>
**Open:** <top 3 items, each with a date>
**Flags:** promised-not-written: … | outside the repo: … | stale memory: …
**Orientation cost:** ~Nk tokens
**Health:** git-checker <verdict> · outputs: FRESH|STALE-OUTPUT <list> · hook: installed|missing
**Last cleanup:** <date> @ <commit>      <- written by repo-cleanup; drift check compares against it
Cleanup needed, see CLEANUP-PLAN.md      <- only if a threshold in step 9 is crossed
```

### 9. The chain (checks run; every action is asked first)
**a. Cheap drift check, every session (read-only, seconds).** Read `**Last cleanup:** <date> @ <commit>` from the state file found in step 4 (`STATE.md`, or whatever `AGENTS.md` names, e.g. `docs/OPEN-ITEMS.md`). If that commit equals `HEAD` and git-checker found nothing new, **skip to 9e**. Otherwise check these thresholds; any one crossed = drift:

| # | Threshold | How to check |
|---|---|---|
| T1 | More than one file of the same type (state, decisions, plan, handoff) beyond the one the repo's rules name | case-insensitive file names (`state*`, `decisions*`, `*plan*`, `handoff*`, `open-items*`); the one named file per type is not a duplicate; part specs and CAD pages that only contain "plan" in the name count only if they hold status or decisions |
| T2 | Orientation cost over 30k tokens (all files read to get oriented, not a line limit) | step 6 |
| T3 | Any non-main branch or worktree (merged, unmerged or prunable) not marked keep at the last cleanup | git-checker notes, `git branch -a`, `git worktree list`, `**Kept branches:**` in the state file |
| T4 | Any `STALE-OUTPUT`, `ORPHAN-SCRIPT`, `UNDECLARED-OUTPUT` or `DUPLICATE-OUTPUT`, or scripts/workflows but no `automation.yml` | git-checker Generated outputs / registry check |
| T5 | Docs changed since last cleanup commit | `git diff --name-only <last-cleanup>..HEAD -- '*.md' docs/` non-empty |
| T6 | Task cards without status lines, handoffs in throwaway folders, rules repeated across agent files | step 1 reads |
| T7 | After-merge / "not done here" steps from merged PRs missing from `STATE.md` or OPEN-ITEMS | PR bodies since last cleanup |
| T8 | Project progress (where work stopped, next steps, open items for this repo) found in local agent memory/notes instead of the repo's state file | read-only scan of the agent's local memory/notes for this project's name or path |

No `Last cleanup` line at all = treat as drift (first run).

Report the findings first, then ask one question per step below, in order, each quoting its trigger. Skip steps with no trigger.
**b. Full cleanup (T1, T2, T3, T6, T7).** Add "Cleanup needed, see CLEANUP-PLAN.md" to the note. Ask: "Drift found: <threshold + evidence>. Run **repo-cleanup**?"
**c. Docs sweep (T5).** Ask: "Docs changed since last cleanup: <files>. Run **iterative-cleaning** (report-only)?"
**d. Fixes (T4 or approved cleanup results).** Ask: "Fix <item> on a branch + PR via **safe-repo-preflight**?" No force-push; each deletion is its own yes.
**d2. Automation registry (T4).** If there's no `automation.yml`, ask: "This repo has <N> scripts/workflows and no automation registry. Run repo-cleanup's automation inventory to draft one (read-only until you approve)?" Installing `registry-check.py` with the hook is part of the hook question below.
**e. Hook.** If no state-file hook is installed, show the git-checker **Install question** word for word (it explains what the hook checks, COMMENT vs BLOCK, escapes, the switch command, how to uninstall, and what "no" means). On yes, install the chosen mode as its own PR via safe-repo-preflight. On no: nothing is installed, note `Hook: declined <date>`, never re-ask this session; ask again only on a later session-start. Once merged, the hook runs on every PR by itself.
**e2. Progress in local memory (T8).** Warn only: "Local memory holds project progress: <note + line>. It belongs in <repo state file>. Move it there and delete the local copy?" Never move or delete without a yes; each note is its own yes.
**f. Stopped early?** If this session runs out of room mid-chain, ask to run **agent-handoff-pack** (or say so in the last reply if no room to ask).

### 10. Tell the user, then start the real work
Show the note. Then follow the user's instructions for the actual task.

---

## Rules for the working session (after session start)
Tell the agent these, and follow them:
1. **Log after every finished step**, one short line, never wait for the end: `2026-10-23 21:40 J1 done, 2.99 kg -> out/j1.step`. The log is never more than one step behind.
2. **Give the path** of any saved output (plan, report, file) in that log line.
3. **Log `PR #N opened`** right after creating a PR.
4. **Every task card gets a status line** (`Status: open` / `Status: done <date>`).
5. **Decisions go in one decisions file**, one dated line each.
6. **Handoffs never go in throwaway folders** (`output/`, `tmp/`, scratch dirs).
7. **Finished to-dos:** delete from the to-do list; add one dated line to the decisions file or changelog.

---

## If the basics are missing
Offer (don't create without a yes): `AGENTS.md` (rules, under ~150 lines, concrete commands, no status), `CLAUDE.md` = `@AGENTS.md`, one state file (`STATE.md`), one log, one decisions file.

## Starting it
the user invokes it by name ("run session-start") in Grok, Claude Code or Cursor. Never add a "run session-start first" line to `AGENTS.md`, `CLAUDE.md` or Cursor rules: it starts only when the user calls it. Once it has installed the hook, the hook covers every PR without anyone calling a skill.
