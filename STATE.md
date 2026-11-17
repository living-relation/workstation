# State

The one state file for this repo. Rules live in `AGENTS.md`; this file holds only current status.

**Goal now:** shared memory, handoff and context tools, guards, the two app locks, a manual Desktop Commander phone remote (one copy per PC), and a manual Cursor worker (Start and Stop shortcuts only). The old shortcut set is gone from the repo. Phase 2 also ships this repo as the `workstation-core` plugin.

**Plugin (2026-11-17):** Phase 2 adds `.claude-plugin/plugin.json` and `.cursor-plugin/` (`plugin.json` plus a one-entry marketplace, `"source": "."`). No `version` field. Skills stay in `skills/`. `plugin-validate` CI runs `claude plugin validate .` (no `--strict`, because a missing `version` is only a warning) and checks the Cursor JSON. Cursor's live import of `"source": "."` is not verified. Later phases stay unstarted.

## Open items
- 2026-11-17: Removed `skills/iap-ship-workflow` and its zip. Eleven skill folders remain (the README count). After this merges, delete that skill at claude.ai Customize > Skills on each of Dan's two accounts if it is still uploaded, then run `workstation\skills-drift.ps1`. A Grok library copy of the same name, if one exists outside this repo, should be removed too.
- 2026-11-17: Dan merges the phase 2 plugin PR. Later phases stay unstarted. Cursor live import of marketplace `"source": "."` was not run.
- 2026-11-17: Cursor worker is manual only. On each PC, after this merges: `git pull --ff-only`, then `install.ps1` (that refreshes `shortcuts\Start Cursor worker.lnk` and `Stop Cursor worker.lnk`). Start lists folders in the detected `<Projects>\active` and starts one worker for the folder you pick. Stop lists workers this tool started. No scheduled task, Startup item, Run key, or hourly check. Health check may report running workers and does not warn when none is running. It warns if an autostart entry exists. If `agent` is missing: install the CLI and run `agent login` (see `workstation\cursor-worker\README.md`).
- 2026-11-16: Concise skill updated with structured Done / Found / Next / Open replies, and project prefs can start the mode on. After this merges, upload `skills/concise.zip` at claude.ai Customize > Skills > Upload on each of Dan's two accounts, then run `workstation\skills-drift.ps1`.
- 2026-11-15: Skills live in this repo. After a skill change merges, upload `skills/<name>.zip` at claude.ai Customize > Skills > Upload on each of Dan's two accounts, then run `workstation\skills-drift.ps1`. `check-upstream.ps1` is manual (no schedule). wizard tracks upstream vlad-ko/claude-wizard `skill/` at `43756e1`.
- 2026-11-15: Health check is a manual shortcut again (`workstation\health\workstation-status.ps1`). No scheduled task, Startup item, or Run key. kill-orphans treats one cmd -> npx node -> cmd -> node phone remote as one copy and does not offer to stop the working copy. cleanup-legacy is safe on Windows PowerShell 5.1. install removes an empty `shortcuts\rc` folder only.
- 2026-11-15: After merge, on each PC that still has the old local setup: `powershell -NoProfile -ExecutionPolicy Bypass -File cleanup-legacy.ps1 -WhatIf`, review, then run it (admin only for the old firewall rule, and only if the script says it skipped that step). Then `git pull --ff-only` and `install.ps1`. Health check: `workstation\health\workstation-status.ps1 -NoPause` (0 FAIL, 0 WARN). Locks: same script with `-Locks`. Start Desktop Commander is manual: it cleans leftover phone-remote copies, then keeps exactly one phone remote (`npx.cmd @wonderwhy-er/desktop-commander@latest remote`). It does not launch the desktop app. No sign-in item.
- 2026-11-13: harness.design desktop lock is the same script as Fusion, with `-Name harness-design` (default remains fusion). Lock file `%LOCALAPPDATA%\Workstation\harness-design.lock`. Rule: `agents/projects-AGENTS.md` section 5b. `-Repo` on acquire is recorded and shown. It does not change who is blocked. One lock per PC still blocks every other session. Window titles are conservative. MCP cloud tools do not need the lock; an agent delete goes through the desktop app under the lock.
- 2026-11-05: Memory policy (owner): two stores, different jobs. The local Working Memory folder is the shared project source of truth (Claude Code, Cowork, Cursor); Claude account Memory is a separate, allowed store for general prefs (duplicates OK, no sync, never the project source of truth). Install only appends a marked section when the marker is missing.
- 2026-10-28: Claude-importable skill zips live at `skills/<name>.zip` (generated). A GitHub Action rebuilds them on same-repo PRs that touch skills. Do not edit zips by hand.
- 2026-10-29: `pr-closeout` lives under `skills/`. Install links skills by default.
- 2026-10-29: install makes Claude Code MCP connectors and official-marketplace plugins match `claude\mcp-servers.json` and `claude\plugins.json`. The Fusion connector url is `http://127.0.0.1:8765/mcp`.
- 2026-11-03: The `~\.claude\working-memory` link stays retired. Install does not create or check it. Local Working Memory (the store path) is still the project source of truth.

**Last added:** 2026-11-17 workstation-core plugin manifests (no version field; Cursor live import of source `.` not verified).

**Kept branches:** none
**Hook:** state-check, comment mode (warn only)
**Last cleanup:** 2026-11-17
