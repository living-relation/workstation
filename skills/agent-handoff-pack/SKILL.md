---
name: agent-handoff-pack
description: >-
  Use when handing a job to another session, or when context is near 80%: write a handoff file under handoffs/ and print a paste block in quick mode. Never store it in the state file or in memory.
---
# agent-handoff-pack

Purpose: write the handoff, then stop. Do not do the job in this skill.

A handoff is its own temporary file. It never goes inside `STATE.md`, `OPEN-ITEMS`, memory, or `AGENTS.md`. `AGENTS.md` is the only agent instruction file.

Path: `handoffs/<task-slug>.md` in the task's branch/worktree. An orchestrator's per-subagent file is `handoffs/<task-slug>--<subtask>.md`. More than one may exist. No duplicates: a newer handoff for the same task replaces the old file in place. The header says what it replaces.

The shape is in `templates.md` next to this skill. Fill it from the repo. No placeholders.

Ideas drawn from the community agent-handoff notes (WillowRyu, MIT). This text is ours. This skill does not install that plugin.

## Status header
At the top of the file:

| Field | What to write |
|---|---|
| Task | short name |
| Owner | who picks the job up |
| Status | `active`, `frozen (reason, until)`, or `done` |
| Branch/worktree | the task branch, and the worktree if the work is in one |
| main hash | current `main` commit |
| Last verified | date and the commit hash you checked |
| Replaces | `none`, or the date and hash of the handoff this file replaced |
| Next step | one concrete step |

## Sections
After the header, in this order:

1. **START HERE** — current state, the exact next step, what not to do, and "run resume mode and verify every claim before acting".
2. **Remaining steps** — each step has a status: `todo`, `in progress`, `blocked`, or `verified`.
3. **Open decisions** — still unanswered. Do not invent an answer.
4. **Rules and checks** — pointers only (file and rule name). Do not copy rule text.
5. **Leftovers** — files, folders, logs, or clones this work left behind.
6. **Mistakes** — at most 8. Each one names the rule and the exact act.

When a step is finished, record its facts in the decisions file, a source-of-truth doc, or the tracker. Then remove that step from the handoff and leave a pointer to where the facts went.

## Modes
**(a) Write or update.** Create the file, or replace the same task's file in place. Set `Replaces`. Commit it on the task branch.

**(b) Resume.** A new session does this before acting. Verify every claim against the repo (hashes, PR state, files). Then continue, freeze, or confirm done. Never blindly fold the handoff into the state file, the decisions file, or the tracker. Never delete it unless the git rule below says it is verified done.

**(c) Quick save.** The 80% hooks call this when context is near the limit. Update the same file, commit it, and print the paste block from `templates.md`. Do not start new project work.

## Blocker
Stop. Mark that step `blocked` and write the reason. Do not keep going on that step.

## Git
Handoff files are committed on the task branch. Do not push to `main`.

Before merge: if resume mode has verified the handoff complete (`Status: done`, and the claims match the repo), delete the file. Deleting a verified-done handoff is pre-approved by Dan. Rely on git history. Do not leave a `.bak`.

If it is not verified complete, leave the file and let it merge. The next session's resume mode flags it and handles it first.

## Hard rules
- **No secrets.** Write a needed credential as "ask the user".
- **No second store.** Do not create `SESSION_STATE.md`, `PHASE_HANDOFF.md`, `HANDOFF-v<n>.md`, a backlog file, or a config file. Do not add an auto-scan or a hook.
- **Not a git repo.** Show the handoff in chat and stop. Do not invent a file outside the repo.
- **The project's own rules win** over this skill.

## Done when
The handoff file matches the template, is committed on the task branch (or deleted because it was verified done), and no handoff text was written into `STATE.md` or `OPEN-ITEMS`. Quick mode also printed the paste block.

## Run alone vs. from session-start
Run by hand, this skill does only its own job and never loads another skill. If it finds something worth fixing, it may **suggest** one ("want me to run repo-cleanup?"). Only `session-start` offers the full chain, and it asks the user before each step.
