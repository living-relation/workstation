# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: fusion-desktop-lock
Last_Verified_SHA: e9f06ea
Updated: 2026-11-24 -- Grok Bot

## Current Goal
- Objective: Bring back a per-PC Fusion Desktop lock (`app-lock.ps1 -Name fusion-desktop`), separate from the harness.design lock.
- Spec_Ref: DECISIONS.md#d-2026-11-24-fusion-desktop-lock

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] After merge: ff-only pull on each PC, update the workstation-core plugin, run install.ps1 to add the Fusion lines to older lock blocks, re-paste the instruction files (BACKLOG.md, 2026-11-24).

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: D-2026-11-24-fusion-desktop-lock
