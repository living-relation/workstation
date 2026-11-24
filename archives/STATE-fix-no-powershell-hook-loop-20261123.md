# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: fix/no-powershell-hook-loop
Last_Verified_SHA: 24c9dc1
Updated: 2026-11-24 -- Grok Bot

## Current Goal
- Objective: Without PowerShell (Linux cloud Claude Code), hooks never print on Stop or other non-start events; start events load the rules through a Python fallback, else warn once per session.
- Spec_Ref: DECISIONS.md#d-2026-11-24-no-powershell-quiet

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] CI green, archive this file as the last commit, merge, then update the plugin on both PCs.

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: D-2026-11-24-no-powershell-quiet
