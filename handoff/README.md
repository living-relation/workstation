# 80% handoff hooks

When a chat gets close to its context limit, these hooks make the agent run the
`state-closeout` skill once in closeout mode: tag what the session did, graduate each item to its home, queue the rest in `BACKLOG.md`, and rewrite this branch's STATE file in the repo (`STATE.md` on trunk, `STATE-<branch-slug>.md` committed on a branch). No HANDOFF/handoffs files; STATE-<slug> is the handoff. A paste block for a new chat is `state-closeout` handoff mode, on demand. The skill does not push to main.
`context-guard.ps1` still copies the transcript to `~\.claude\compaction-backups\` before compaction. That copy is a backup of the chat, not the handoff record.

All of these run from the workstation-core plugin (decision D-2026-11-26-hooks-in-plugin). `install.ps1` copies no
hook files and writes no hook entries, `statusLine` or `~\.cursor\hooks.json`.

| File | Plugin manifest | Events |
|---|---|---|
| `claude\context-guard.ps1` | `hooks\hooks.json` (`-FromPlugin`) | `Stop` (fires at 80% of the compaction point), `PreCompact` (backs up the transcript to `~\.claude\compaction-backups\`). Usage comes from the statusline file `~\.claude\hooks\state\context-guard\<session>.pct` when a `statusLine` runs `context-guard.ps1 statusline` (set by an older install), else from the transcript's last `usage` (input + cache tokens). The compaction point is `CLAUDE_CODE_AUTO_COMPACT_WINDOW` or `autoCompactWindow`, else 200K (1M once usage passes 200K; unverified on 1M-context models). |
| `claude\pr-closeout-nudge.ps1` | `hooks\hooks.json` and `hooks\cursor-hooks.json` (`-FromPlugin`) | `PostToolUse` / `postToolUse`: after `gh pr create` or a GitHub create-pull-request tool succeeds, tells the agent to run the pr-closeout skill. |
| `cursor\handoff-at-80.py` via `cursor\run-handoff-at-80.ps1` | `hooks\cursor-hooks.json` | `preCompact` + `stop` (timeout 10, stop `loop_limit` 1). The launcher tries `py -3`, `python3`, `python` (3.7+) and prints `{}` with none. Armed by default from the plugin; disarm with the file `~\.cursor\hooks\state\handoff-at-80\disarmed`. |
| `..\skills\state-closeout\` | delivered only by the workstation-core plugin (`INSTALL.md`). Not linked into `%USERPROFILE%\.claude\skills\` | the skill both hooks trigger (closeout mode) |

- `link-skills.ps1` retires the old `handoff-sync-continue` copy: a same-name folder or link in either skills folder is moved to `~\.skills-backup\<stamp>\retired\` (never deleted).
- No double runs: a plugin copy stays quiet for an event while `~\.claude\settings.json` (or `~\.cursor\hooks.json`
  for handoff-at-80) still wires an older installed copy of the same script for that event. That older copy keeps
  working (it still needs the `armed` flag in Cursor); `uninstall.ps1` removes it only if install recorded it.
- No Python 3.7+: the Cursor hook does nothing (prints `{}`).
- Cursor also runs `~\.claude\settings.json` hooks; `context-guard.ps1` ignores Cursor payloads, so only
  `handoff-at-80.py` fires in Cursor.
- The skill never runs `git init`, never pushes to main, and never commits memory or
  memory pointer files (`CLAUDE.local.md`).
- Tests: `powershell -NoProfile -File handoff/claude/tests/test-state-closeout-trigger.ps1`,
  `powershell -NoProfile -File handoff/claude/tests/test-hooks-from-plugin.ps1`, `python -m pytest -q scripts/test_hooks_in_plugin.py`.
- `uninstall.ps1` removes only what an install added (listed in `<Projects>\_claude\automation-installed-files.txt`).
