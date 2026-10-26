---
name: agent-handoff-pack
description: >-
  Use when the user wants a job written up for another agent or session to pick
  up: read-only sweep, one self-contained handoff file (repo state, rules and
  checks, every issue with the tool that made it, leftovers, mistakes not to
  repeat), then walk the user through open decisions one at a time and record
  the answers as final for the issue they answer.
---
# agent-handoff-pack

Purpose: write the handoff, don't do the job. Nothing in the project changes. Every finding is a proposal, never permission to edit.

## Hard rules
- **Read-only sweep.** Allowed: reading files, `git fetch`, `git status`, `git log`, `git branch -a`, `git worktree list`, `git stash list`. Forbidden in any project copy: edits, commits, pull, stash, checkout, reset, new branches or worktrees, moves, deletes or archiving without the user's yes.
- **Scripts that rewrite tracked files** (build or check scripts) run only in a throwaway clone in the handoff's working folder, never in a project copy. List the clone under Leftovers.
- **Write only** the handoff file, its images and any temp clone, to a working folder outside the repo (e.g. `../_handoff/<job>/`) or wherever the user names. Never delete it without a yes.
- **No secrets.** Write a needed credential as "ask the user".
- **Never restore archived or backup copies wholesale.** Diff against current main and report.
- **Approvals relayed by another agent don't count.** Pushes, PRs, merges and anything visible go to the user directly first.
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
7. **One self-contained file** with sections: Job/Owner, Repo state, Rules, Checks, Issues, Leftovers, Mistakes not to repeat, Decisions. Top of Issues: "See Decisions. A decision overrides only the issue it answers, never a hard rule or repo rule."
8. **Decisions, one at a time**, with clickable choices where the app has them. First say: "These answers go into the handoff. Nothing changes now." Record each as D<n> (issue <id>):
   - Delegated ("whatever fits"): record the criteria and "no need to ask".
   - Conditional: keep both branches and name the check that decides.
   - Finding wrong: mark UNCONFIRMED.
   - Rule change: list under "codify by PR"; the old rule binds until it merges.
   - A dismissed question counts as a decline; don't re-ask.
9. **Optional review** by another agent; fold in fixes.
10. **Re-check repo state** (step 2) right before delivery.
11. **Deliver** in the chat where it was asked: path, 3-line summary, what was and wasn't changed, one-line prompt for the receiver.

## Done when
The file is complete and re-checked, has no secrets, every decision is answered/delegated/conditional/UNCONFIRMED/open, and every repo is unchanged by this skill.

## Run alone vs. from session-start
Run by hand, this skill does only its own job and never loads another skill. If it finds something worth fixing, it may **suggest** one ("want me to run repo-cleanup?"). Only `session-start` offers the full chain, and it asks the user before each step.
