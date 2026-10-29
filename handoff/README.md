# 80% handoff hooks

When a chat gets close to its context limit, these hooks make the agent run the
`agent-handoff-pack` skill once in its quick mode (it replaced `handoff-sync-continue`): update the living docs and print a paste block for a new chat.
It does not commit or push.

| File | Installed to | Wired in |
|---|---|---|
| `claude\context-guard.ps1` | `%USERPROFILE%\.claude\hooks\` | `~\.claude\settings.json`: `statusLine` (measures context), `hooks.Stop` (fires at 80% of the compaction point), `hooks.PreCompact` (backs up the transcript to `~\.claude\compaction-backups\`) |
| `cursor\handoff-at-80.py` | `%USERPROFILE%\.cursor\hooks\` | `~\.cursor\hooks.json`: `preCompact` + `stop` (`py -3`, timeout 10, stop `loop_limit` 1). Armed by the flag file `~\.cursor\hooks\state\handoff-at-80\armed` (delete it to disarm) |
| `..\skills\agent-handoff-pack\` | linked into `%USERPROFILE%\.claude\skills\` (Cursor reads it too) by `link-skills.ps1` (`install.ps1`, opt out with `-NoLinkSkills`) | the skill both hooks trigger (quick mode) |

- `link-skills.ps1` retires the old `handoff-sync-continue` copy: a same-name folder or link in either skills folder is moved to `~\.skills-backup\<stamp>\retired\` (never deleted).
- `install.ps1` copies the hooks and merges the entries (no duplicates; an entry for the same script elsewhere is
  re-pointed). An unrelated `statusLine` is never overwritten (install warns; the Claude side then cannot fire).
- No `py -3` (Python 3.7+): the Cursor hook is skipped with a warning.
- Cursor also runs `~\.claude\settings.json` hooks; `context-guard.ps1` ignores Cursor payloads, so only
  `handoff-at-80.py` fires in Cursor.
- The skill never runs `git init`, never commits or pushes, and never commits memory or
  memory pointer files (`CLAUDE.local.md`).
- `uninstall.ps1` removes only what install added (listed in `<Projects>\_claude\automation-installed-files.txt`).
