# STATE (max 30 lines, overwrite only)
Repo: workstation
Branch: fix/seal-install-tests-windows-ci
Last_Verified_SHA: bab2126
Updated: 2026-11-23 -- Grok Bot

## Current Goal
- Objective: Seal the paste-helper installer test so it cannot open an editor or write the clipboard; add a this-repo-only Windows (and Linux) CI job that runs the full suite and asserts no real editor/clipboard use; fix Windows-only state-files-gate bash and cleanup-settings chmod failures.
- Spec_Ref: DECISIONS.md#d-2026-11-23-workstation-repo-tests

## Active Blocker
- Status: NONE
- Detail: none

## Next Single Step
- [NEXT] Run the full suite on Linux and Windows, then open the PR. After merge: delete this branch, ff-only pull workstation on DansPC and RESEARCH-SPARK-ENGR, update the Claude Code plugin on both.

## Pointers
- Branch_States: none
- Backlog: BACKLOG.md
- Latest_ADR: D-2026-11-23-workstation-repo-tests
