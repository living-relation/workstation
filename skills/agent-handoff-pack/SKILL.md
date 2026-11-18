---
name: agent-handoff-pack
description: >-
  Use when handing a job to another session, or when context is near 80%: forwards to state-closeout handoff mode. The old name stays so existing hooks and prompts keep working.
---
# agent-handoff-pack (forward)

This skill is now a thin forward. Run **state-closeout** instead:

| Old call | Run now |
|---|---|
| quick mode (80% hooks), write or update | `state-closeout` closeout mode, then `handoff` mode |
| resume mode | **session-start** (it reads your STATE file and confirms in 3 lines) |

What changed:
- The handoff is your `STATE-<slug>.md` in the store, not a file in the repo. The paste block that `handoff` mode prints is a copy, not a second store.
- Do not write handoff files or a handoff folder in the repo, and no handoff in memory.
- A repo that still has old handoff files: run **repo-cleanup**, which tags each line and moves it to its home (or drops it as `[DONE]`).
