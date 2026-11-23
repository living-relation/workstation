---
name: session-start
description: >-
  Use when starting any chat, task or session in a repo or project folder, before reading code or changing anything: reads router, DECISIONS, SPEC and STATE, confirms in 3 lines, asks before follow-ups.
---
# Session start

**In one line:** figure out where the project really stands, change nothing, then say so in one short note.

## When to use
Finds the project's true current state cheaply, detects whether the last session was cut off (usage limit, crash), runs git-checker and a cheap drift check, lists the repo's STATE files, reports, then asks before each follow-up (repo-cleanup, iterative-cleaning, fixes, state-closeout, PR hook install). Those follow-ups do not run on their own. Any project folder.

Works the same in Grok, Claude Code and Cursor. It runs when the user calls it ("run session-start"), and a coordinator also runs it at the start of every session and after every compaction (coordinator-kit). The SessionStart hook only prints the state; it does not replace this skill.

**Why it exists:** a session can stop cold at a usage limit. A stopped session can't save anything, so nothing may rely on "the end of a session". The *next* session finds the leftovers and rebuilds the picture.

---

## Hard rules
- **Steps 1-7 are read-only**, except the CLAUDE fold-and-delete below. No other edits, commits, pulls, pushes, deletes or lock releases. Anything else happens only in step 8, after the user says yes: repo changes through **safe-repo-preflight** (branch + PR, never force-push, never skip hooks, every deletion waits for the user's yes); STATE changes through **state-closeout**.
- **`AGENTS.md` is the only agent instruction file.** If any `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` is found in the repo, fold its content into `AGENTS.md` (keep every rule, drop exact duplicates), then delete the CLAUDE file, in the same PR. That fold-and-delete is pre-approved by Dan. Do not read or write those CLAUDE files for any other reason. Do it on the task branch, with hooks. Do not do it on `main`.
- **Read-only helper session** (not the coordinator, no branch or job of its own): run steps 1-7 only, write no STATE file, put findings for `BACKLOG.md` in the report (with the date and source) for the coordinator to append, and report to the user. Any change goes to the coordinator.
- **Follow-ups are not automatic.** The read-only checks run on their own. Every action step in step 8 is one clear question to the user, quoting the finding that triggered it; run it only on his yes. A no or a dismissed question is final for this session.
- **Only this skill offers the chain.** Every other skill run alone does only its own job and may just suggest the next one.
- **Never read or print secrets** (`.env*` values, tokens, keys).
- **Files beat chat memory.** If Claude/Cursor memory disagrees with the repo or the STATE file, trust the files and flag the stale memory.
- **A resumed chat is a new session.** Reopening an old chat (any age) means running this skill fresh. Treat everything from the earlier chat — its summary, its notes, what it "already knows" — as stale until re-read from the files this session.
- **No memory-only claims.** Every fact in the note and report names the file it came from, opened this session. If you can't open it, write "not verified: <claim>" instead of stating it.
- **Report factual contradictions, do not guess them.** Contradictions between facts go in the note as open questions for the user. A conflict between an older agent doc and the workstation-core template (`AGENTS.md` router, state-init profiles, repo STATE) is not a blocker and not a reason to stop: step 8 offers state-init or repo-cleanup to migrate it.

---

## Steps

### 1. Read in this order (stop when you have the answer)
1. **Router:** root `AGENTS.md`, then the nearest nested `AGENTS.md` above the folder you'll work in (closest wins). If a `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` is in the repo, follow the fold-and-delete rule above before other work.
2. **DECISIONS**, where the router's role table says. Never skipped.
3. **SPEC**, if the repo has one (Full profile).
4. **STATE** in the repo (decision 2026-11-22): `python <workstation>/scripts/state/state_paths.py` gives the state folder (this worktree's root). On main: `STATE.md`. On a branch or worktree: `STATE-<slug>.md` (fall back to `STATE.md` if it doesn't exist yet). Then the store's notes, `<project>/INDEX.md` (notes only); store unreachable (PC offline, cloud session): say so; live state is still in the repo.
5. Every other doc the router names as source of truth, read in full; `README.md`; `.cursor/rules/*.mdc` with `alwaysApply: true`. List each in the note with its last-changed date. Any named doc you couldn't read, or read only partly, goes in the note as a gap.
6. **List every branch's `STATE-<slug>.md`** with `python <workstation>/scripts/state/state_manager.py branches --show` (pushed branches through `git fetch --prune` + `git show origin/<branch>:STATE-<slug>.md`, unpushed ones from each worktree). Flag any line with `(carried 2)` or more (it must graduate), and any top-level `STATE-*.md` on the trunk (`state_manager.py verify` flags it): archive the state file in a PR, on a yes.

Skip: `node_modules`, build output, caches, archive/`old` folders, other worktrees' copies, other modules' agent files.

**Orientation cost.** Count auto-loaded files (`AGENTS.md`, rules with no `paths:`, the first 200 lines of the memory index) and every "read X" step in read-first lists. Flag any that load lookup-only content.

### 1b. Confirm in 3 lines
Before anything else, print:
```
Goal: <Current Goal objective>
Last good commit: <Last_Verified_SHA>
Next: <Next Single Step>
```

### 2. Did the last session stop early?
Check each sign. Any one = **"last session stopped early"**.

| Sign | How to check |
|---|---|
| A lock is still held | lock files inside this repo, or the harness.design app lock held on this PC; say which repo/holder holds it |
| Outputs newer than STATE | files changed after the STATE file's `Updated:` date (`git status`, file times) |
| Last transcript entry isn't a final reply | last entry of the newest session file is a tool call, tool result or plan, not an answer |
| Sure usage-limit stop | last entry has `"model":"<synthetic>"` **and** text like "hit your … limit" |
| Unapproved plan | a plan in `~/.claude/plans/` newer than STATE that names this repo's path or name; ignore others |
| STATE fails the lint | `python <workstation>/scripts/state/state_lint.py --repo <dir>` exits 2 |

Session files: Claude Code keeps them under `~/.claude/projects/<project>/*.jsonl`. Read only the last few lines of each.

### 3. Health check: run git-checker, then GitHub
Run the **git-checker** skill on this project (read-only; `git fetch --prune` only), with its optional Generated-outputs and Deployed-copies checks if the repo lists them. Keep its verdict and any `STALE-OUTPUT` lines for step 8. Then (read-only):
```bash
gh pr list --author @me --state open      # open PRs
git worktree list                         # extra checkouts
git branch --no-merged main               # unmerged local branches
git branch -r --no-merged origin/main     # unmerged remote branches
```
Note where live work actually is (it may be on a branch, not `main`). If `gh` isn't signed in, say so and skip; don't start a sign-in.

### 4. Look for promised reports that don't exist
If a task card, plan or STATE says "will write a report/note at the end", check the file exists. If not, flag it: **"promised, never written: …"**.

### 5. List facts that live outside their homes
Decisions or plans that exist only in a chat, memory, email or another machine. List each as **"outside the repo: …"** with where it lives. Don't copy it in here; cleanup does that.
Check files outside the repo that agents load (a parent-folder `AGENTS.md`, the memory index) against this repo's sources of truth. Flag mismatches and any unsigned memory-index lines (missing `-- <agent>, YYYY-MM-DD`).

### 6. If the last session stopped early
Ask the user: "Last session stopped early (<sign>). Run **state-closeout** to rebuild the STATE file?" On yes, run it in closeout mode on that branch's STATE file. Include this repo's leftover plans (as scoped in step 2) and any held locks, outputs newer than STATE, open PRs and branches. Never release a lock or finish someone's step without the user's yes.

### 7. Show one short note in chat
Never write this note to the repo, to memory or to `AGENTS.md`; STATE changes only through state-closeout. Keep it under ~20 lines:

```markdown
**Goal now:** <Current Goal>
**Last session:** finished | stopped early (<which sign>)
**Where work is:** branch <x>, PR #N (open), worktrees: <list>
**State files:** STATE.md, STATE-<slug>.md … (flags: carried 2 | branch gone | lint fail)
**Read:** <path (last changed YYYY-MM-DD), each read in full>
**Gaps:** <named docs not read or only partly read, with why; or none>
**Open:** <Active Blocker, or none> · TASK.md <n> left · BACKLOG <n> items
**Flags:** promised-not-written: … | outside the repo: … | stale memory: … | unsigned memory: … | orientation-cost: …
**Health:** git-checker <verdict> · outputs: FRESH|STALE-OUTPUT <list> · hook: installed|missing
**Last cleanup:** <date> @ <commit>      <- from STATE Pointers (Last_Cleanup), written by repo-cleanup
Cleanup needed, see CLEANUP-PLAN.md      <- only if a threshold in step 8 is crossed
```

### 8. The chain (checks run; every action is asked first)
**a. Cheap drift check, every session (read-only, seconds).** Read `Last_Cleanup: <date> @ <commit>` from the STATE file's Pointers. If that commit equals `HEAD` and git-checker found nothing new, **skip to 8e**. Otherwise check these thresholds; any one crossed = drift:

| # | Threshold | How to check |
|---|---|---|
| T1 | More than one file of the same role (decisions, spec, plan) beyond the one the role table names; a handoff, open-items or progress file inside the repo other than the template's `STATE.md`, `STATE-<slug>.md`, `BACKLOG.md` and `archives/` | case-insensitive file names (`state*`, `decisions*`, `*plan*`, `open-items*`, `handoff*`); the one named file per role is not a duplicate; part specs and CAD pages that only contain "plan" in the name count only if they hold status or decisions |
| T3 | Any non-main branch or worktree (merged, unmerged or prunable) not marked keep at the last cleanup | git-checker notes, `git branch -a`, `git worktree list`, `Kept_Branches` in STATE Pointers |
| T4 | Any `STALE-OUTPUT`, `ORPHAN-SCRIPT`, `UNDECLARED-OUTPUT` or `DUPLICATE-OUTPUT`, or scripts/workflows but no `automation.yml` | git-checker Generated outputs / registry check |
| T5 | Docs changed since last cleanup commit | `git diff --name-only <last-cleanup>..HEAD -- '*.md' docs/` non-empty |
| T6 | Task cards without status lines, rules repeated across agent files, or read-first / auto-loaded lookup-only content | step 1 reads |
| T7 | After-merge / "not done here" steps from merged PRs missing from STATE, TASK.md and BACKLOG | PR bodies (and their `State:` lines) since last cleanup |
| T8 | Project progress (where work stopped, next steps, open items) in `INDEX.md` notes, a store `STATE*.md` / `BACKLOG.md`, or other local agent memory instead of the repo's STATE files | read-only scan of the agent's local memory/notes for this project's name or path |
| T9 | A STATE line with `(carried 2)` or more, or a top-level STATE-<slug> left on the trunk | step 1.6 |

T2 is retired; the other numbers stay the same so older notes still match.

No `Last_Cleanup` pointer at all = treat as drift (first run).

Report the findings first, then ask one question per step below, in order, each quoting its trigger. Skip steps with no trigger.
**b. Full cleanup (T1, T3, T6, T7, or step 5 outside-file / unsigned-index findings).** Add "Cleanup needed, see CLEANUP-PLAN.md" to the note. Ask: "Drift found: <threshold + evidence>. Run **repo-cleanup**?"
**c. Docs sweep (T5).** Ask: "Docs changed since last cleanup: <files>. Run **iterative-cleaning** (report-only)?"
**d. Fixes (T4 or approved cleanup results).** Ask: "Fix <item> on a branch + PR via **safe-repo-preflight**?" No force-push; each deletion is its own yes.
**d2. Automation registry (T4).** If there's no `automation.yml`, ask: "This repo has <N> scripts/workflows and no automation registry. Run repo-cleanup's automation inventory to draft one (read-only until you approve)?" Installing `registry-check.py` with the hook is part of the hook question below.
**d3. Graduate (T9).** Ask: "<file> has <line> carried 2 runs (or is a branch state file left on the trunk). Run **state-closeout** (or archive the state file in a PR)?"
**e. Hook.** If no graduation-check hook is installed, show the git-checker **Install question** word for word. On yes, install the chosen mode as its own PR via safe-repo-preflight. On no: nothing is installed, note `Hook: declined <date>` in the chat note, never re-ask this session; ask again only on a later session-start. Once merged, the hook runs on every PR by itself.
**e2. Progress in the wrong place (T8).** Live state goes in the repo's STATE files. Ask: "<file> holds project progress: <note + line>. Run **state-closeout** to tag it and move it to its home? Delete the old copy after that?" Move it only on yes. Never delete a memory note without its own yes.
**f. Stopped early?** If this session runs out of room mid-chain, run **state-closeout** `handoff` (or say so in the last reply if there's no room).

### 9. Tell the user, then start the real work
Show the note. Then follow the user's instructions for the actual task.

---

## Rules for the working session (after session start)
Tell the agent these, and follow them:
1. **Keep your own STATE file current** after every finished step: overwrite it (30 lines max), never wait for the end, and commit it on your branch. Finished steps are `[DONE]` and leave it. Never log progress in memory or in any repo file other than your STATE file.
2. **Give the path** of any saved output (plan, report, file) in the `[NEXT]` line or the report.
3. **After opening a PR**, run pr-closeout.
4. **Every task card gets a status line** (`Status: open` / `Status: done <date>`).
5. **Decisions go in DECISIONS** as `[ADR]` entries; how-to constraints go in `.claude/rules/` as `[RULE]`s.
6. **Handoffs:** run `state-closeout handoff`. No `HANDOFF` or `handoffs/` files; `STATE-<slug>.md` is the handoff.
7. **Finished to-dos:** delete them from `TASK.md`.
8. Before ending a turn at a milestone, or opening a PR, run state-closeout; if nothing changed, end with "State: no change."

---

## If the basics are missing
Offer **state-init** (don't run it without a yes) when the role files are missing, or when an older agent doc conflicts with the template layout. Do not create a second instruction file.

## Starting it
The user invokes it by name ("run session-start") in Grok, Claude Code or Cursor. Never add a "run session-start first" line to `AGENTS.md` or Cursor rules: it starts only when the user calls it. Once it has installed the hook, the hook covers every PR without anyone calling a skill.
