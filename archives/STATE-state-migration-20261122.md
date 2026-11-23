# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: state-migration/cursor-permission
Last_Verified_SHA: 2dd0e96
Updated: 2026-11-19 -- Claude Code (cloud coordinator)

## Current Goal
- Objective: Wave 1 of the state migration is merged (#90, 2dd0e96). Next: land PR #91 (Cursor permission + no-PowerShell launcher), then open the sot-guard PR (branch state-migration/sot-guard, 07456f5).
- Spec_Ref: none (rule: SoT edits need Dan's yes, checks gate correctness, the only hard block is another branch's STATE file)

## Active Blocker
- Status: NONE
- Detail: PR #91 waits for Dan's merge.

## Next Single Step
- [NEXT] After #91 merges: open the sot-guard PR, run install.ps1 on DansPC (remove the hand-wired root hooks first, with a backup), upload the skill zips, then start Wave 2 (st185).

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: none
- Kept_Branches: state-migration/cursor-permission, state-migration/sot-guard
