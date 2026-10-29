# State

The one state file for this repo. Rules live in `AGENTS.md`; this file holds only current status.

**Goal now:** dashboard task actions (4 features). 1 (full text + GitHub link), 2 (answer) and
3 (hand to Claude) are done; 4 (done / snooze) is next.

## Open items
- 2026-10-28: Claude-importable skill zips live at `skills/<name>.zip` (generated, beside the skill folders). A GitHub Action rebuilds them on same-repo PRs that touch skills (commits onto the PR branch, never onto main, and never if the PR head is main). If main is stale it resets `chore/skill-zips` to `origin/main` and force-with-lease that bot branch only. Local `scripts/pack-skill-zips.ps1` / `.sh` is optional. Do not edit zips by hand. Skill YAML descriptions were shortened; dropped detail is in each skill's **When to use** section. Description over 200 chars is a `::warning` only (never fails). `deploy-project-watcher` YAML description has no angle-bracket tags; `<project>` placeholders stay in the body. Owner must keep **Allow GitHub Actions to create and approve pull requests** on, and a ruleset on `main` that blocks direct pushes.
- 2026-10-28: Per-project Claude remote-control shortcuts and per-repo lines in Workstation Status are in PR #55 (https://github.com/living-relation/workstation/pull/55), open. This PC's shortcuts\rc\ links are already generated. After merge, switch this clone back to main. The other PC runs Generate RC shortcuts once after pull.
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
- 2026-10-29: `pr-closeout` and `iap-ship-workflow` live under `skills/` so `-LinkSkills` can
  junction them on both PCs. The local `pr-closeout-nudge.ps1` Claude Code hook stays on the PC
  (this repo does not ship Claude Code PostToolUse hooks from skill folders). After merge:
  remove the old loose copies of those two skills on each PC (they block the new links), then
  Pull + Install `-LinkSkills` on both PCs. Exact leftover paths are in the PR body; do not
  delete them from here.

- 2026-10-29: Fusion lock (`workstation/fusion-lock/fusion-lock.ps1`, rule in `agents/projects-AGENTS.md` section 5). After merge: Pull on both PCs; the old router-project lock (`rtr-v2-router\_coordination\`) should be retired and that project's rules pointed at section 5 (owner's yes needed; not done here).

**Last added:** 2026-10-29 Fusion lock.

**Kept branches:** none
**Hook:** state-check, comment mode (warn only), 2026-10-27
**Last cleanup:** 2026-10-27 @ 18ebd4d
