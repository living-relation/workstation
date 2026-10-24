---
name: repo-cleanup
description: >-
  Use when a repo's agent, state, plan, handoff or decision files have sprawled
  (session-start flagged "Cleanup needed", orienting costs too many tokens, or
  there are duplicate decisions/state files): sorts every file into
  keep/merge/archive/delete, asks about conflicts one at a time, and lands the
  approved result as one PR with nothing lost. Runs as its own session.
---
# Repo cleanup

**In one line:** turn a messy repo into one state file, one decisions file and
short agent files, without losing anything, and only with the user's yes.

Works the same in Grok, Claude Code and Cursor. Uses two other skills:
- **safe-repo-preflight**: read the repo's rules, work on a branch, run checks, open a PR.
- **backup-dryrun-apply**: hash-backed backup, dry run, apply, verify.

---

## When to run
1. **Normally as its own session, after the first task** of the day is done.
   Cleanup should never block real work.
2. **Run it first only if** the mess hides the true state (you can't tell what's
   current), **or** the repo has a rule saying cleanup comes first.
3. **Freeze rule?** If the repo or user says the repo is frozen, wait until the
   freeze ends or the user says "go". Don't even create the branch.

## Hard rules
- **Nothing changes before the user says yes** to the plan.
- **Archive, don't delete.** Move to `docs/archive/` (git keeps history). Delete
  only what the user names, one by one.
- **Never "newest wins".** Conflicts are always asked (step 6).
- **Never merge whole documents.** Only pull out dated decision lines (step 5).
- **Log every step** so a usage-limit stop can resume (step 2).
- **Never read or print secrets.**

---

## Steps

### 1. Start safely
1. Run **safe-repo-preflight**: read `AGENTS.md`, hooks, CI; note required checks.
2. Read the session-start note if there is one.

### 2. Make it resumable
1. Create or open `CLEANUP-PLAN.md` at the repo root (on the cleanup branch
   once it exists; until then, show it in chat).
2. It has a `## Progress` log. Add one line after every finished step:
   `2026-10-23 22:10 step 4 done: 212 files sorted`.
3. **On start, read `## Progress` first.** If earlier steps are logged, skip
   them and continue from the next one.

### 3. Save outside-only decisions into the repo first
Decisions that live only in chats, memory, email or another machine (session-start
lists them as "outside the repo"):
1. Save each as a file under `docs/sources/` (e.g. `docs/sources/2026-10-22-chat-plan.md`)
   with where it came from and its date.
2. Now they can be compared like everything else. Nothing is lost if the chat disappears.

### 4. Sort every file
Inventory every agent/state/plan/handoff/task/decision/notes file (name, size,
last commit date, one-line purpose; no content dumps). Put each in a table in
`CLEANUP-PLAN.md`:

| File | Action | Why | Goes to |
|---|---|---|---|
| `OPEN-ITEMS.md` | merge | open items + decisions | `STATE.md`, `DECISIONS.md` |
| `old/PLAN-v2.md` | archive | stale since Oct 14 | `docs/archive/` |

Actions: **keep** (source of truth) · **merge** (extract lines, then archive) ·
**archive** · **delete** (only junk like empty files or build output; list each).

### 5. How "merge" works
1. From each merge file, pull out **dated decision lines only**.
2. Add each to the one `DECISIONS.md` with its source:
   `2026-10-22 Use Postgres, not SQLite. (source: docs/sources/2026-10-22-chat.md)`
3. Open items go to the one state file, each with a date.
4. Then archive the original. Never paste whole documents together.

### 6. Ask about conflicts, one at a time
When two sources disagree, list both in an **Ask the user** section of
`CLEANUP-PLAN.md` with quotes and dates. Nothing touching them is merged or
archived until answered.

Ask **one conflict per question**, using the app's clickable question tool:
Grok → choice widget · Claude Code → `AskUserQuestion` · Cursor → ask-question.
If none exists, use a numbered list and wait for a number.

Options, in this order:
1. **Latest decision wins:** quote it, with its date and source.
   "Latest" = the user's latest *dated decision*, **not** the newest file edit.
2. **Older one wins:** quote it, with its date and source.
3. **Type my own.**
4. **Skip for now** (stays on the Ask list; its files stay untouched).

Log each answer as a dated line in `DECISIONS.md`.

### 7. Agent files
1. **Root `AGENTS.md`:** short (under ~150 lines), concrete commands, no status
   or history. `CLAUDE.md` = `@AGENTS.md`.
2. **Per-module files:** keep them where the repo intends one per app/module.
   Make them thin: only what's specific to that module.
3. **No rule repeated in two places.** Move shared rules to the root; delete the
   copies from module files.
4. Plain `.md` in `.cursor/rules/` is ignored by Cursor; convert to `.mdc` or move.

### 8. Target end state (write it into the plan)
- One **state file** with the current goal on top.
- One **decisions file**.
- Every task card has a status line: `Status: open` or `Status: done <date>`.
- No handoffs in throwaway folders.
- Short root agent file + thin module files.

### 9. Get the yes
Show the user: the file table summary (counts per action), the Ask list, the
end state, and the subagent offer (step 10) if it applies. **Wait for yes.**
Changes to the plan → update and ask again.

### 10. Offer subagents when there's a lot to do
If the approved work splits into **many independent tasks** (e.g. 50 task cards to
add status lines to, several modules' agent files):
1. Group them into batches. **No two batches touch the same file.**
2. Offer: "This is N independent batches. Want me to launch N subagents, one per
   batch?" Show which files each batch owns.
3. Only launch after the user approves. Each subagent works on the same cleanup
   branch (or its own worktree), changes only its files, and logs to `## Progress`.
4. Shared files (`DECISIONS.md`, state file, root `AGENTS.md`) are edited only
   by the main session.

### 11. Apply
1. On a branch (via **safe-repo-preflight**), run **backup-dryrun-apply**:
   hash-backed backup → dry run shown to user → apply.
2. Archive with `git mv` so history stays.
3. **Hash-verify nothing was lost:** every original file is either still in place,
   in `docs/archive/`, or on the approved delete list, and its hash matches the backup.
4. Run the repo's required checks.

### 12. Open one PR
One PR per repo. Body: summary table, decisions recorded, Ask items still open,
verification result. Log `PR #N opened` in `## Progress`. Never force-push or
skip hooks. Merging is the user's call.

### 13. Finish
Update the state file: remove "Cleanup needed", note the PR. Tell the user what's
left on the Ask list.
