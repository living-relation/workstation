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
- The handoff is your `STATE-<slug>.md` at the repo root, committed and pushed on your branch. The paste block that `handoff` mode prints is a copy, not a second store.
- No HANDOFF/handoffs files; STATE-<slug> is the handoff. No handoff in memory.
- A repo that still has old handoff files: run **repo-cleanup**, which tags each line and moves it to its home (or drops it as `[DONE]`).
