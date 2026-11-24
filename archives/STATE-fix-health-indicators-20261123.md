# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: fix/health-indicators
Last_Verified_SHA: c9eb39a
Updated: 2026-11-23 -- Grok Bot

## Current Goal
- Objective: Health check shows RUN/STOP/OK/--/WARN/FAIL honestly (Desktop Commander, Cursor worker incl. the Cursor app's own worker and dead workers, plugin versions per app), Start Cursor worker fails when the worker exits right away, lock check uses the installed plugin record (AA-AH, AO).
- Spec_Ref: DECISIONS.md#d-2026-11-23-health-indicators

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] CI green, archive this file as the last commit, merge, then ff-only pull workstation on DansPC and the work PC and run the health check.

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: D-2026-11-23-health-indicators
