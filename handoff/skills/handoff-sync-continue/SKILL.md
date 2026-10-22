---
name: handoff-sync-continue
description: Perform handoff and documentation updates and emit a copyable next-chat paste block. Use at the end of a completed slice; when the user asks to handoff or wrap up; when a follow-up says context is at or above 80%; or when compaction is imminent. Do not commit or push. Do not continue project work after the paste block. Do not use for mid-slice coding unless context pressure forced this run.
---

# Handoff

Close the current chat so the next chat can start clean. Do **not** continue the work here.

**Exact workflow name:** perform handoff and documentation updates, and continue project

"Continue project" means: give the user a **copyable paste block for the next chat**. Do not start the next slice in this conversation.

**Do not commit or push.** This skill only updates living handoff docs on disk and emits the paste block. The user commits and pushes when they choose.

## When to run

- The user asks to handoff, wrap a slice, or update living docs
- A behavior-changing slice is done and the project's standing rules require living docs
- You are about to stop or switch tasks after durable work
- A user/system message says context is at or above **80%**, or compaction is about to run
- The auto-hook follow-up (see below) submitted this skill

Do **not** run it for speculative edits or "just thinking," unless context pressure forced the run.

## Auto-run at 80% context

Cursor Automations cannot trigger on chat context percent. A **user hook** does this instead:

- `preCompact` — Cursor reports `context_usage_percent`. At **80% or above**, it marks the chat.
- `stop` — when that mark is set (or the payload itself reports ≥80%), it auto-submits a follow-up that runs this skill **once per chat**.

Hook files: `~/.cursor/hooks.json` and `~/.cursor/hooks/handoff-at-80.py`. Armed flag: `~/.cursor/hooks/state/handoff-at-80/armed`. Delete that file to disarm.

**Claude Code** has its own version: `~/.claude/hooks/context-guard.ps1`, wired in `~/.claude/settings.json`:

- `statusLine` — shows `[model] NN% context | handoff at MM%` and saves used/trigger tokens per session (Claude Code hooks can't see context).
- `Stop` — at **80% of the compaction point** (not the raw window; honors `autoCompactWindow`), with at least 40K tokens always left, blocks the stop **once per context** so Claude runs this skill. Same behavior on any model or window size.
- `PreCompact` — backs up the transcript + git snapshot to `~/.claude/compaction-backups/`, then re-arms the trigger. Never blocks compaction.

Cursor also runs `~/.claude/settings.json` hooks. `context-guard.ps1` ignores Cursor payloads (`conversation_id`) so only `handoff-at-80.py` fires there. Remove the `Stop` entry in settings.json to disarm the Claude Code side.

When this run was forced by context pressure: take the **fast path** (docs + paste block only). Do not commit or push. Note unfinished work and any owed commit/push/CI/deploy in the paste block.

## Discover the project (do not guess)

Read standing docs first, in this order if they exist:

1. `AGENTS.md` / `CLAUDE.md` / `.cursor/rules` — git, branch, and doc rules
2. Living **phase handoff** (progress, tip SHA, next step)
3. Living **session state** (where we left off, gotchas, in-flight work)
4. The current **work queue** / roadmap if one is named

From those files, resolve:

| Fact | How to find it |
|------|----------------|
| Git clone path | The folder that contains `.git` (may be the workspace root or a subfolder such as `repo/`) |
| Working branch | Current branch; never assume `main` |
| Protected branch | `main` / `master` / whatever the docs freeze — report it; do not push |
| Continuity docs | Names/paths the project already uses; do not invent a parallel set |

If a required fact is missing, stop and ask. Do not invent remotes, branches, or product intent.

**No git repo:** if no folder in the workspace contains `.git`, the project is a plain folder. Update the docs on disk and say "not a git repo, docs on disk only" in the status line and the paste block. Never run `git init`, add a remote, or create a repo; making a folder a repo is only ever the user's decision.

If the project has **no** continuity docs yet, create the minimum pair using [templates.md](templates.md) in the project folder (no git repo: in the project folder; never `git init` for this). Prefer one live fact over duplicated conflicting facts.

## Loop (run in order)

Copy and track:

```
Slice close:
- [ ] 1. Docs: living handoff + session state match reality
- [ ] 2. Paste block: copyable next-chat handoff. Stop. Do not start the next slice.
```

Do not commit. Do not push. Report uncommitted or unpushed state in the paste block so the next chat can see it.

### 1. Documentation updates

Update living docs on disk so the next chat can rebuild context. Do not commit them as part of this skill.

**Phase handoff** (historical + current tip):

- Last updated date
- Tip SHA, branch, whether local matches origin (report only)
- Progress table / status of the slice just finished
- Blockers and the **next exact step**
- In-flight work another agent must not collide with

**Session state** (continuity for the next session):

- Same tip SHA and sync/CI status (report only)
- What landed, in one short paragraph
- Unfinished in-flight work (especially on a 80% forced run)
- Gotchas that cost time
- Test data or leftover state it is safe to delete
- Next exact steps (ordered)
- Do-not-do list if the project has frozen rules

Also update standing rules (`AGENTS.md`, refresh/deploy docs) **only** when those rules actually changed.

Keep docs tool-agnostic ("agent", not only one product name). Prefer editing the live file over adding a new handoff.

### 2. Copyable next-chat block (required)

Do not start the next slice. Print **one** fenced block the user can copy into a new chat. Use the template in [templates.md](templates.md). Fill every section from real state. No placeholders.

Then stop.

## Reply shape

Keep the chat reply short. Order:

1. One-line status (docs updated / anything owed including commit or push the user still needs to do)
2. The paste block (the deliverable)
3. **What's Finished and What's Next** — what landed, and that the user should open a new chat and paste the block

## Anti-patterns

- Continuing the next slice in this chat
- Progress only in chat (no living docs, no paste block)
- Docs that disagree with each other or with the real SHA
- Committing or pushing as part of this skill
- Inventing a second session-memory folder
- Auto-handoff firing again in the same chat after the paste block already ran
