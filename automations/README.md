# Automations / routines

| Name | Owner | Where it runs | Schedule | What |
|---|---|---|---|---|
| Skill watch | Skill Expert bot | Grok Bot server-side (no file) | every 3 hours | Watches conversations for repeated patterns and drafts/updates skills (drafts in `drafts/`). |
| Workstation folder sync | Skill Expert bot | Grok Bot server-side, works on DansPC | 9 AM and 9 PM ET (waiting for Grok Bot all-clear) | Copies newly finished skills/tools into this shared folder and updates INVENTORY.md. Copy-in only. |
| Claude memory -> Cursor sync | Windows Task Scheduler | DansPC | see `memory/_claude/register-memory-sync-task.ps1` | Part of the original workstation kit. |
