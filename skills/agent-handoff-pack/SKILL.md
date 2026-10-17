---
name: agent-handoff-pack
description: >-
  Use when the owner wants a job written up for Claude or another bot to pick up:
  read-only sweep, one self-contained handoff file (repo state, rules and
  checks, every issue with the tool that made it, leftovers, mistakes not to
  repeat), then walk the owner through open decisions one at a time and record his
  answers as final for the issue they answer.
---
# agent-handoff-pack

Purpose: write the handoff, don't do the job. Nothing in the project changes. Every finding is a proposal, never permission to edit.

## Hard rules
- Read-only sweep. Allowed: reading files, `git fetch`, `git status`, `git log`, `git branch -a`, `git worktree list`, `git stash list`. Forbidden in any project copy: edits, commits, pull, stash, checkout, reset, new branches or worktrees, moves, deletes, moving anything into `_archive` or making archive backups without the owner's OK.
- Check scripts that regenerate tracked files (e.g. a check_all/buildlist script) run only in a throwaway clone inside the staging folder, never in a project copy. The clone is listed under Leftovers; don't delete it without the owner's yes.
- Write only the handoff file, its images and any temp clone to `<staging dir>\<job>\handoff\` (e.g. `%USERPROFILE%\_staging`). That's a working folder, not inside a synced Desktop, a repo or the models folder. Archive it later; never delete it.
- Heavy work runs on the owner's workstation (WSL). If it is offline, stop; don't fall back to the bot's computer.
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
   - Copy the owner's standing rules word for word: follow the repo's own rules, hooks and CI gates and never bypass one; no edits on main; protected main means branch + PR, and the receiver may push or open PRs only with the owner's explicit yes in their own chat (pushes go through the bot that owns them); never force-push; back up before config changes; models folder add-only, new revs through publish-to-models after the owner approves; no FEA before geometry approval; destructive steps need the owner's yes; after merging, pull local copies fast-forward only and never over uncommitted changes; no batch git shortcuts (one repo at a time).
   - Copy the owner's chat rules that aren't in the repo word for word, marked "not binding in the repo until recorded by PR, with the matching gates changed in the same PR". Every chat-vs-repo conflict becomes its own open decision. Never resolve one silently.
   - Define the owner's terms in plain words, using their wording (e.g. "routing points" means the app's hover tacks, not "pins"). If a term is ambiguous, ask before writing it up.
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
