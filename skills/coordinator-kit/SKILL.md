---
name: "coordinator-kit"
description: "Use when one chat should coordinate all agent work on a repo or project folder: the coordinator owns the root STATE, each worker its STATE-<slug>, so any new session can resume without re-asking."
---

# Coordinator kit

One chat runs the project. Every other agent is dispatched from it. Live state lives in the store's STATE files, not in chat, so a fresh session can pick up at any time.

The project's own rules (AGENTS.md, its DECISIONS) always win over this skill.

## Who owns which file
| File (store project folder) | Owner |
|---|---|
| `STATE.md` (root) | the coordinator only; its `Branch_States` line is generated from the `STATE-*.md` files, never hand-edited |
| `STATE-<slug>.md` | one worker each; slug = its branch name, lowercase, non-letters/digits as `-` |
| `BACKLOG.md` | anyone, append only |

Workers never write the root STATE, another worker's STATE-<slug>, the router, SPEC or DECISIONS unless the brief says so. No `HANDOFF` files and no handoff folder in the repo: a worker's STATE-<slug> is its handoff.

## The five tools

| Tool | Job | When |
|---|---|---|
| `session-start` skill | Read router, DECISIONS, SPEC and STATE; confirm in 3 lines | Start of every session and after every compaction |
| `state-closeout` skill | Graduate live notes to their homes; rewrite STATE; `handoff` mode prints a resume block | 80% context, pivot, blocker, milestone, PR |
| `spec-drift` plugin (init, check, report) | Checklist of what the user asked, compared with what was built | init at job start, report before saying done |
| `pr-closeout` skill | Runs state-closeout on the PR branch; `State:` line in the PR body | Before every merge |
| `session-sweep` / `repo-cleanup` | Worktrees, branches and stale docs cleaned | After every merge |

If a tool is missing, say which one and carry on with the rest. Do not write new scripts or hooks to replace it unless the user asks.

## Set up in a new project (once)

1. Check the tools above are installed. List any that are not.
2. Find the router, DECISIONS and the store's STATE. If they are missing, offer **state-init** before creating anything.
3. Write `SPEC_CHECKLIST.md` at the repo root and keep it out of git with `.git/info/exclude` (`SPEC_CHECKLIST*.md`, `.spec-drift/`). It is spec-drift's per-request list, not the repo's SPEC.
4. Record in the root STATE (Current Goal) that this chat is the single coordinator.

## Every job

1. **Take stock first.** Git status, worktrees, branches, open PRs, the STATE-* files, and any live files in outside apps. Other sessions may have changed things.
2. **Checklist.** Write the user's asks into `SPEC_CHECKLIST.md`, including the implied ones (record decisions, clean up, verify).
3. **Dispatch.** One agent, one worktree, one PR. Give each agent the full rules in its brief, because agents do not inherit this skill. The brief names its branch and its `STATE-<slug>.md`, and says: write only that file, append discoveries to BACKLOG, run state-closeout before reporting. Run independent jobs in parallel; jobs that touch the same files run in order.
4. **Stop rules in every brief.** Stop and report when a change needs a source-of-truth edit the user has not approved, when anything physical or irreversible would change, or when the screen or repo is not what the brief described.
5. **Before merge.** Gates green, `pr-closeout` run, drift report clean or its gaps listed.
6. **After merge.** Archive the worker's STATE-<slug> (`state_manager.py archive-branch`, or the git hook pack does it; neither writes the root STATE), update the root STATE (its `Branch_States` line comes from `state_manager.py branches`), remove the worktree and branch, delete what the job replaced.
7. **Report.** One short reply: what changed, links to every changed artefact, what is next, blockers, open questions.

## Rules that keep a new session from asking again

- Record every user answer in its home in the same turn it is given, with the date: a decision in DECISIONS, a how-to in rules, a value in data or SPEC (after the yes).
- Question IDs come from one counter, a pointer line in the root STATE. Cite the date when an ID could repeat.
- Never ask what the repo or STATE already answers. Re-ask only questions the user has not answered.
- After compaction or a restart: read the root STATE, then every STATE-<slug>. Check PRs and worktrees, then continue. Resume stopped agents from their transcripts and STATE files; never restart a job without checking what it already did.
- Only one agent at a time drives a shared desktop app. Use the app's lock if the project has one.
- At 80% context: run state-closeout, then its `handoff` mode, and tell the user.

## Keeping this kit current

When a rule here fails in practice, or the user corrects the way work is run, propose an edit to this skill in the same session: what happened, the one-line rule that would have prevented it. Keep it short; project-specific rules go in that project's own files, not here.
