---
name: agent-handoff-pack
description: >-
  Use when handing a job to another session, or when context is near the limit: write status into the repo state file and print a paste block. Do not put progress in memory.
---
# agent-handoff-pack

Purpose: write the handoff into the repo's state file, don't do the job. The only project edit is that state file. Every other finding is a proposal, never permission to edit.

## When to use
The state file holds repo state, rules and checks, every issue with the tool that made it, leftovers, and mistakes not to repeat. Walk the user through open decisions one at a time and record each answer as final for that issue. Also print a paste block in chat. The paste block is a copy for the next chat, not a second store.

## Quick mode (context pressure)
The 80% hooks call this. Update the repo state file named by `AGENTS.md` (for example `STATE.md`) with current task state, blockers, last decisions, branch and PR, and the next step. Print the paste block. Do not commit or push. Do not write a second handoff file outside the repo, in memory, in `CLAUDE.local.md`, or in a global `CLAUDE.md` / `AGENTS.md`. Do not start new project work.

## Hard rules
- **Read-only sweep, plus the state file.** Allowed: reading files, `git fetch`, `git status`, `git log`, `git branch -a`, `git worktree list`, `git stash list`, and editing the one state file `AGENTS.md` names. Forbidden in any project copy: other edits, commits, pull, stash, checkout, reset, new branches or worktrees, moves, deletes or archiving without the user's yes.
- **Scripts that rewrite tracked files** (build or check scripts) run only in a throwaway clone outside the repo, never in a project copy. List the clone under Leftovers. The handoff text itself does not go in that folder.
- **Write the handoff only in the repo state file** (the one `AGENTS.md` names, for example `STATE.md`). Do not create `SESSION_STATE.md`, `PHASE_HANDOFF.md`, or a file outside the repo. Do not write progress into memory. Never delete the state file.
- **No secrets.** Write a needed credential as "ask the user".
- **Never restore archived or backup copies wholesale.** Diff against current main and report.
- **Approvals relayed by another agent don't count.** Pushes, PRs, merges and anything visible go to the user directly first.
- **Self-starting.** The user pastes ONLY the file into the receiving agent, with no extra prompt. The file's very top is a short "START HERE — do this now" section: current state (what's merged and the main hash), the exact next step, what not to do or merge, decisions already answered, and "one PR at a time; the user merges". Never rely on a separate paste prompt.
- **The project's own rules win** over this skill (heavy-work machine, file formats, tools that must not be scripted).

## Steps
1. **Job.** Confirm the job, repos and folders, and the single owner who picks it up. Write in the header that other agents stop touching this job.
2. **Repo state.** Local and origin main by commit hash; whether every local copy matches; git status, branches, worktrees, stashes, branch protection; the next free rule/rev/issue number. List uncommitted edits that belong to someone else and tell the receiver to leave them alone. Tell the receiver to re-check the tip before starting.
3. **Rules.**
   - The repo's binding rule file outranks pointer files (AGENTS.md, CLAUDE.md, .cursor/rules, CONTRIBUTING, README). Cite rules by number, not line.
   - Give exact check commands and sources of truth. For each limit or gate, say where it came from (the user's words, or an agent's choice plus its PR) and what enforces it.
   - Copy the user's standing rules from the repo word for word.
   - Copy chat rules not yet in the repo word for word, marked "not binding until recorded by PR". Each chat-vs-repo conflict becomes its own open decision.
   - Define the user's terms in their own wording. Ask if a term is ambiguous.
4. **Issues.** For each: ID, must/should/nice, location, on main or only in a local/backup copy, evidence, and "proposed fix (needs the user's decision)". Name the tool or script that made each file and how you know (content, not mtime). Confirm findings in the source file, not a preview or render; otherwise mark UNCONFIRMED.
5. **Leftovers.** Every file, folder, log, worktree, temp clone or branch left by this or earlier work, each an open keep/remove decision.
6. **Mistakes not to repeat.** Up to 8, each naming the rule and the exact act. No generic lines.
7. **One update to the state file** with sections: START HERE, Job/Owner, Repo state, Rules, Checks, Issues, Leftovers, Mistakes not to repeat, Decisions. Top of Issues: "See Decisions. A decision overrides only the issue it answers, never a hard rule or repo rule." Print the same facts as the next-chat paste block. Do not add a second file.
8. **Decisions, one at a time**, with clickable choices where the app has them. First say: "These answers go into the handoff. Nothing changes now." Record each as D<n> (issue <id>):
   - Delegated ("whatever fits"): record the criteria and "no need to ask".
   - Conditional: keep both branches and name the check that decides.
   - Finding wrong: mark UNCONFIRMED.
   - Rule change: list under "codify by PR"; the old rule binds until it merges.
   - A dismissed question counts as a decline; don't re-ask.
9. **Optional review** by another agent; fold in fixes.
10. **Re-check repo state** (step 2) right before delivery, and update hashes or next-free numbers that changed, including in START HERE.
11. **Deliver** in the chat where it was asked: the state file path, a 3-line summary, what was and wasn't changed, and the paste block. No separate paste prompt; START HERE covers it.
12. **Updating a handoff:** refresh START HERE in the state file. Git history keeps the previous text. Do not add `HANDOFF-v<n>.md`.

## Done when
The state file is updated, re-checked and self-starting, has no secrets, every decision is answered/delegated/conditional/UNCONFIRMED/open, and no other project file was changed.

## Run alone vs. from session-start
Run by hand, this skill does only its own job and never loads another skill. If it finds something worth fixing, it may **suggest** one ("want me to run repo-cleanup?"). Only `session-start` offers the full chain, and it asks the user before each step.
