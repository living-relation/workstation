---
name: "coordinator-kit"
description: "Use when one chat should coordinate all agent work on a repo or project folder: sets up checklist, handoff, closeout and cleanup tools so any new session can resume without re-asking."
---

# Coordinator kit

One chat runs the project. Every other agent is dispatched from it. State lives in the repo, not in chat, so a fresh session can pick up at any commit.

The project's own rules (AGENTS.md, its decisions file) always win over this skill.

Handoffs follow `agent-handoff-pack`. This skill does not install a community handoff plugin, and it does not add a hook.

## The five tools

| Tool | Job | When |
|---|---|---|
| `session-start` skill | Read state and source-of-truth docs | Start of every session and after every compaction |
| `agent-handoff-pack` skill | Write `handoffs/<task-slug>.md` on the task branch. An orchestrator's per-subagent file is `handoffs/<task-slug>--<subtask>.md`. Commit it. No pointer in the state file. No root `HANDOFF.<name>.md` | Every job bigger than one file, and before context runs out |
| `spec-drift` plugin (init, check, report) | Checklist of what the user asked, compared with what was built | init at job start, report before saying done |
| `pr-closeout` skill | PR effect into the state file on the same branch | Before every merge |
| `session-sweep` / `repo-cleanup` | Worktrees, branches and stale docs cleaned | After every merge |

If a tool is missing, say which one and carry on with the rest. Do not write new scripts or hooks to replace it unless the user asks.

## Set up in a new project (once)

1. Check the tools above are installed. List any that are not.
2. Find the project's state file, decisions file and agent rules. If there are none, ask the user where state should live before creating anything.
3. Write `SPEC_CHECKLIST.md` at the repo root. A handoff is `handoffs/<task-slug>.md`, committed on the task branch. An orchestrator's per-subagent file is `handoffs/<task-slug>--<subtask>.md`. More than one may exist. A newer handoff for the same task replaces the old file in place. Do not write `HANDOFF.<name>.md` at the repo root.
4. Keep the checklist out of git with `.git/info/exclude` (`SPEC_CHECKLIST*.md`, `.spec-drift/`). Handoff files are committed on the task branch. They never go inside the state file.
5. Record in the state file that this chat is the single coordinator. Do not add a pointer to the handoff file.

## Every job

1. **Take stock first.** Git status, worktrees, branches, open PRs, and any live files in outside apps. Other sessions may have changed things.
2. **Checklist.** Write the user's asks into `SPEC_CHECKLIST.md`, including the implied ones (record decisions, clean up, verify).
3. **Dispatch.** One agent, one worktree, one PR. Give each agent the full rules in its brief, because agents do not inherit this skill. Run independent jobs in parallel; jobs that touch the same files run in order. Each subagent handoff is `handoffs/<task-slug>--<subtask>.md`, committed on that task branch.
4. **Stop rules in every brief.** Stop and report when a change needs a source-of-truth edit the user has not approved, when anything physical or irreversible would change, or when the screen or repo is not what the brief described.
5. **Before merge.** Gates green, `pr-closeout` run, drift report clean or its gaps listed.
6. **After merge.** Update the handoff file, remove the worktree and branch, delete what the job replaced.
7. **Report.** One short reply: what changed, links to every changed artefact, what is next, blockers, open questions.

## Rules that keep a new session from asking again

- Record every user answer in the repo in the same turn it is given, with the date.
- Question IDs come from one counter in the state file. Cite the date when an ID could repeat.
- Never ask what the repo already answers. Re-ask only questions the user has not answered.
- After compaction or a restart: read `handoffs/<task-slug>.md` and any `handoffs/<task-slug>--<subtask>.md`, then the state file. Check PRs and worktrees, then continue. The state file has no pointer to the handoff. Resume stopped agents from their transcripts; never restart a job without checking what it already did.
- Only one agent at a time drives a shared desktop app. Use the app's lock if the project has one.
- Around 85% context: tell the user and refresh `handoffs/<task-slug>.md` on the task branch.

## Keeping this kit current

When a rule here fails in practice, or the user corrects the way work is run, propose an edit to this skill in the same session: what happened, the one-line rule that would have prevented it. Keep it short; project-specific rules go in that project's own files, not here.
