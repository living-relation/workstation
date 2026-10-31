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
- 2026-10-29: `pr-closeout` and `iap-ship-workflow` live under `skills/` so install can
  junction them on both PCs. After merge: remove the old loose copies of those two skills on
  each PC (they block the new links), then Pull + Install on both PCs (skill linking is now the
  default; no `-LinkSkills`). Exact leftover paths are in the earlier PR body; do not delete
  them from here.
- 2026-10-29: install now makes both PCs' Claude Code setups match: MCP connectors in
  `~/.claude.json` (from `claude/mcp-servers.json`; no firecrawl), the 24 DansPC
  official-marketplace plugins in `claude/plugins.json` (that file is the source of
  truth), and DansPC's `pr-closeout-nudge.ps1` copied + wired as PostToolUse in
  `~/.claude/settings.json`. After merge: Pull + Install on both PCs. Set
  `GITHUB_PERSONAL_ACCESS_TOKEN` (or `GITHUB_TOKEN`) before install, or paste when
  prompted; missing keys skip that server. Install never prompts for Firecrawl.
- 2026-10-29: firecrawl dropped from `claude/mcp-servers.json` (not used). Merge-style
  install still leaves an existing firecrawl entry in `~/.claude.json` alone.
- 2026-10-29: `install.ps1` links skills every run (opt out with `-NoLinkSkills`; `-LinkSkills` is
  a no-op). End of install shows a Windows popup to upload `skills/*.zip` in Claude desktop
  (Settings > Capabilities > Skills); skipped for `-WhatIf`, `-UserHome`, `-NoPopup`/`-Quiet`, and
  CI. Changed zip names are tracked in `%LOCALAPPDATA%\Workstation\skill-zips.json`.

- 2026-10-29: Fusion lock (`workstation/fusion-lock/fusion-lock.ps1`, rule in `agents/projects-AGENTS.md` section 5). After merge: Pull on both PCs; the old router-project lock (`rtr-v2-router\_coordination\`) should be retired and that project's rules pointed at section 5 (owner's yes needed; not done here).

- 2026-10-30: Process check no longer treats Kapture's shared detached server, a young `claude -p`
  background job, or one Desktop Commander MCP per Claude window as a stray/orphan. Two Kapture
  servers, a `claude -p` job older than `backgroundJobMaxAgeHours` (default 2), and two Desktop
  Commander copies under the same Claude session still warn. Local `processCheck.expected` still
  appends to the built-in list. After merge: Pull on both PCs (the Dashboard shortcut already
  fast-forwards this clone).

- 2026-10-31: install section 7 merges a Claude Code `autoMode.allow` rule so auto mode may merge PRs
  in living-relation/* when required checks have passed or are queued via `gh pr merge --auto`.
  Existing `autoMode` keys and allow entries stay; `"$defaults"` is put first. No
  `permissions.allow` `Bash(gh pr merge*)` rule. After merge: Pull + Install on both PCs.

**Last added:** 2026-10-31 Claude Code autoMode.allow PR-merge rule (install settings merge).

**Kept branches:** none
**Hook:** state-check, comment mode (warn only), 2026-10-27
**Last cleanup:** 2026-10-27 @ 18ebd4d
