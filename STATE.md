# State

The one state file for this repo. Rules live in `AGENTS.md`; this file holds only current status.

**Goal now:** dashboard task actions (4 features). 1 (full text + GitHub link), 2 (answer) and
3 (hand to Claude) are done; 4 (done / snooze) is next.

## Open items
- 2026-10-27: Feature 4 - **Done** starts Claude through the same launcher with a "mark done / fold
  in" task; **Snooze** hides a row locally for N days (default 7, `snooze.json` in the dashboard's
  local folder, never git).
- 2026-10-27: actions are off until the home PC has the local `settings.json`
  (`{"writeActions": true, "ownerName": ...}`); see `workstation/dashboard/README.md`.
- 2026-10-27: later - the older dashboard POST buttons (toggles, Health, send) don't check the
  `X-Workstation-Dashboard` header yet.
- 2026-10-27: Workstation Status prerequisite check reported Claude Code as not logged in when
  `claude auth status` JSON was multi-line or mixed with extra output. Parse now joins lines, slices
  the JSON object, WARNs on timeout or unparseable output, and FAILs only when loggedIn is false.
  preflight.ps1 has no login check (version only).
- 2026-10-28: After merge of the skill first-pass checks — re-upload the repo-cleanup,
  iterative-cleaning and session-start skill zips to Claude desktop, and run Pull + Install on
  both PCs.

**Last added:** 2026-10-28 skill first-pass checks in repo-cleanup, iterative-cleaning and
session-start (broken pointers, rule-file drift, one state home, heavy read-first, outside-repo
facts, leftovers).

**Kept branches:** none
**Hook:** state-check, comment mode (warn only), 2026-10-27
**Last cleanup:** 2026-10-27 @ 18ebd4d
