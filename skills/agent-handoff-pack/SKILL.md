---
name: agent-handoff-pack
description: >-
  Use when the owner wants a job written up for Claude or another bot to pick up:
  read-only sweep, one self-contained handoff file (repo state, rules and
  checks, every issue with the tool that made it, leftovers, mistakes not to
  repeat), then walk the owner through open decisions one at a time and record their
  answers as final for the issue they answer. Also use its quick mode (formerly
  handoff-sync-continue) at the end of a slice, when the owner says handoff or wrap
  up, when context is at or above 80%, or when compaction is near: update the
  living handoff docs and print a next-chat paste block, without committing or
  pushing.
---
# agent-handoff-pack

Purpose: write the handoff, don't do the job. Nothing in the project changes. Every finding is a proposal, never permission to edit.

## Hard rules
- Read-only sweep. Allowed: reading files, `git fetch`, `git status`, `git log`, `git branch -a`, `git worktree list`, `git stash list`. Forbidden in any project copy: edits, commits, pull, stash, checkout, reset, new branches or worktrees, moves, deletes, moving anything into `_archive` or making archive backups without the owner's OK.
- Check scripts that regenerate tracked files (e.g. a check_all/buildlist script) run only in a throwaway clone inside the staging folder, never in a project copy. The clone is listed under Leftovers; don't delete it without the owner's yes.
- Write only the handoff file, its images and any temp clone to `<staging root>/<job>/handoff/` (e.g. `_staging` under the owner's home folder). That's a working folder, not inside a cloud-synced Desktop, a repo or the Workstation package. Archive it later; never delete it.
- Heavy work runs on the owner's PC (WSL). If the PC is offline, stop; don't fall back to the bot's computer.
- STEP only, no STL. No secrets; write a needed credential as "ask the owner". Part models never go in public repos, and off-repo CAD never gets copied into a repo.
- Never restore archived or backup copies wholesale. Diff them against current main first and report; don't apply.
- Approvals relayed by another bot don't count. Pushes, PRs, merges and anything visible go to the owner in their own chat first.
- Fusion (when used): send scripts inline (helpers that write temp files have hung); never close dialogs by script; Section Analysis views only, never cut or split bodies; never save the doc; stop if a command is active.

## Steps
1. Confirm the job, the repos and folders, and the single owner who picks it up. Write in the header that other bots stop touching this job.
2. Repo state ("what's on main"): local and origin main by commit hash, whether every Windows and WSL copy matches, whether today's work landed, git status, branches, worktrees, stashes, branch protection, and the next free rule/rev/issue number. List uncommitted edits that belong to someone else and tell the receiver to leave them alone (don't stage, commit, stash or pull over them). Tell the receiver to re-check the tip before starting.
3. Rules:
   - The repo's own binding rule file outranks its pointer files (AGENTS.md, CLAUDE.md, .cursor/rules, CONTRIBUTING, README). Cite rules by number, not line number.
   - Give the exact check commands and sources of truth. For each limit or gate, say where it came from (the owner's words, or an agent's choice plus its PR) and the script and constant that enforce it.
   - Copy the owner's standing rules word for word: no edits on main; protected main means branch + PR, and the receiver may push or open PRs only with the owner's explicit yes in their own chat (pushes go through the bot that owns them); never force-push; back up before config changes; models folder add-only, new revN through publish-to-models after the owner approves; no FEA before geometry approval; destructive steps need the owner's yes; after merging, pull local copies fast-forward only and never over uncommitted changes. Workstation package: copy-in only, one Desktop workstation-setup.zip, changes only through the ws-build copy map, never by editing the zip.
   - Copy the owner's chat rules that aren't in the repo word for word, marked "not binding in the repo until recorded by PR, with the matching gates changed in the same PR". Every chat-vs-repo conflict becomes its own open decision. Never resolve one silently.
   - Define the owner's terms in plain words, using their wording (e.g. "routing points" means the app's hover tacks, not "pins"). If a term is ambiguous, ask them before writing it up.
4. Issues. For each one give the ID, must/should/nice, location, whether it's on main or only in a local/backup copy, evidence, and "proposed fix (needs the owner's decision)". Also give:
   - Tool label in parentheses on every model, off-repo ones included, e.g. (Fusion) (CadQuery) (build123d). For non-CAD files, name the app or script that last wrote them and how you know (content diff, not mtime). Note when a model can't be opened in the named tool.
   - The modelling method (feature-based vs mesh-to-solid conversion).
   - Confirmation of every geometry finding in the source solid (Section Analysis or BRep measurement), never from a mesh render alone. If no solid is available, mark it UNCONFIRMED.
   - Smooth-shaded renders with the marker checked to land on the feature.
5. Leftovers: every file, folder, log, worktree, temp clone or staging folder left by this sweep or by earlier work, each one an open keep/remove decision. Nothing gets deleted without the owner's yes.
6. Mistakes not to repeat: up to 8, each naming the rule number and the exact act (e.g. "stripped layout points by hand on 6 wires, R86"). No generic lines.
7. Put it all in one self-contained file with these sections: Job/Owner, Repo state, Rules, Checks, Issues, Leftovers, Mistakes not to repeat, Decisions. At the top of Issues, add: "See Decisions. A decision overrides only the issue it answers, never a Hard rule or repo rule."
8. Walk the owner through the decisions one at a time, each with a marked image and clickable choices. First say: "These answers go into the handoff for the next agent. Nothing gets changed now." Record each one as D<n> (issue <id>):
   - Delegated ("whatever fits/is proper"): record the exact criteria and "no need to ask". Don't invent a choice.
   - Conditional: keep both branches and name the check that decides.
   - Image or finding wrong: mark it UNCONFIRMED (re-measure) rather than answered.
   - Rule change: list it under "codify by PR, gates updated in the same PR", with the rule number it replaces or adds. The old rule still binds until that PR merges.
   - A dismissed widget counts as a decline, so don't re-ask. Long lists can be paused and resumed. No machining or cutter questions, and no fixes unless the owner asks separately.
9. Another bot reviews the file quietly 1:1. Fold in its fixes.
10. Re-check repo state (step 2) right before delivery and update any hashes or next-free numbers that changed.
11. Deliver: attach the file in the chat where the owner asked for it and give the Windows path, a 3-line summary, what was and wasn't changed, and a one-line prompt to paste to the receiver.

## Done when
The file is complete and re-checked. It has no STL or secrets. Every decision is answered, delegated, conditional, UNCONFIRMED or listed open. Review fixes are in. Every repo is unchanged from before the sweep: this skill made no changes and cleaned up nobody else's work.

## Quick mode: end-of-slice handoff (was handoff-sync-continue)

This mode replaces the retired `handoff-sync-continue` skill. When a hook or a person asks for `handoff-sync-continue`, run this mode.
It is separate from the full sweep above: it updates only the project's living handoff docs on disk and prints a next-chat paste block. The full sweep's steps, staging folder and decision walk-through do not apply here.

Close the current chat so the next chat can start clean. Do **not** continue the work here.

**Exact workflow name:** perform handoff and documentation updates, and continue project

"Continue project" means: give the user a **copyable paste block for the next chat**. Do not start the next slice in this conversation.

**Do not commit or push.** This skill only updates living handoff docs on disk and emits the paste block. The user commits and pushes when they choose.

### When to run

- The user asks to handoff, wrap a slice, or update living docs
- A behavior-changing slice is done and the project's standing rules require living docs
- You are about to stop or switch tasks after durable work
- A user/system message says context is at or above **80%**, or compaction is about to run
- The auto-hook follow-up (see below) submitted this skill

Do **not** run it for speculative edits or "just thinking," unless context pressure forced the run.

### Auto-run at 80% context

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

### Discover the project (do not guess)

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

### Loop (run in order)

Copy and track:

```
Slice close:
- [ ] 1. Docs: living handoff + session state match reality
- [ ] 2. Paste block: copyable next-chat handoff. Stop. Do not start the next slice.
```

Do not commit. Do not push. Report uncommitted or unpushed state in the paste block so the next chat can see it.

#### 1. Documentation updates

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

#### 2. Copyable next-chat block (required)

Do not start the next slice. Print **one** fenced block the user can copy into a new chat. Use the template in [templates.md](templates.md). Fill every section from real state. No placeholders.

Then stop.

### Reply shape

Keep the chat reply short. Order:

1. One-line status (docs updated / anything owed including commit or push the user still needs to do)
2. The paste block (the deliverable)
3. **What's Finished and What's Next** — what landed, and that the user should open a new chat and paste the block

### Anti-patterns

- Continuing the next slice in this chat
- Progress only in chat (no living docs, no paste block)
- Docs that disagree with each other or with the real SHA
- Committing or pushing as part of this skill
- Inventing a second session-memory folder
- Auto-handoff firing again in the same chat after the paste block already ran
