# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: fix/install-plugins-nesting
Last_Verified_SHA: 2db08dd
Updated: 2026-11-23 -- Grok Bot

## Current Goal
- Objective: install-plugins.ps1 re-runs merge into the Cursor copy instead of nesting (hooks\hooks, skills\skills). Same fix in the README/INSTALL one-liner; test runs it twice.
- Spec_Ref: Dan's install check 2026-11-23 (PR body)

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] CI green, archive this file as the last commit, merge. Then BACKLOG: clean the doubled folders on each PC (needs Dan's yes) and re-run install-plugins.cmd.

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: D-2026-11-22-state-in-repo
