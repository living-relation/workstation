# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: registry-check-content-stale
Last_Verified_SHA: 62b9124
Updated: 2026-11-23 -- Grok Bot

## Current Goal
- Objective: registry-check.py STALE-OUTPUT compares content (fresh run in a temp copy), not commit dates; slow: true keeps the commit-date check. Then byte-identical copies in sr-drawing-pack, custom-pdm, handbuilt-cad.
- Spec_Ref: Dan's request 2026-11-23 (PR body)

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] CI green, archive this file as the last commit, merge; then the copy PRs.

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: D-2026-11-22-state-in-repo
