# Handoff file

One file per task: `handoffs/<task-slug>.md` on the task branch (in that task's worktree when the work is in a worktree). An orchestrator adds one file per subagent: `handoffs/<task-slug>--<subtask>.md`.

Never write this into `STATE.md`, `OPEN-ITEMS`, memory, or a file outside the repo. A newer handoff for the same task replaces this file in place. The header says what it replaces.

## Status header

| Field | Value |
|---|---|
| Task | |
| Owner | |
| Status | active / frozen (reason, until) / done |
| Branch/worktree | |
| main hash | |
| Last verified | date + hash |
| Replaces | none, or the date and hash of the handoff this file replaced |
| Next step | |

## START HERE

Current state, the exact next step, and what not to do. The next session runs agent-handoff-pack resume mode and verifies every claim against the repo before acting.

## Remaining steps

- step — status: todo / in progress / blocked / verified

When a step is finished, record its facts in the decisions file, a source-of-truth doc, or the tracker. Then remove the step and leave a pointer to where those facts went.

## Open decisions

## Rules and checks

Pointers only. Name the file and the rule. Do not copy rule text.

## Leftovers

## Mistakes

At most 8. Each one names the rule and the exact act.

## Quick-save paste block

Print this as one fenced `text` block when context is near 80%. Fill it from the file. No placeholders, no omitted lines.

```text
NEXT CHAT HANDOFF — paste this as the first message in a new chat.

File: handoffs/[task-slug].md
Task: [name]
Owner: [who picks it up]
Status: [active / frozen (reason, until) / done]
Branch/worktree: [branch]
main hash: [hash]
Last verified: [date + hash]
Replaces: [none, or date + hash]
Next step: [one concrete step]

Run agent-handoff-pack resume mode on this file before acting. Verify every claim against the repo. Do not fold this into STATE.md or OPEN-ITEMS.
```
