---
name: state-init
description: >-
  Use when a repo has no state setup yet, work starts in a router-only repo, or older agent docs conflict with the template: adds the router role table, DECISIONS, rules and SPEC, plus STATE, BACKLOG and archives in the repo. Shows the plan before any overwrite.
---
# State init

**In one line:** give a repo the template layout. Create what is missing, and migrate an older agent doc that conflicts. Show the plan before any overwrite.

Hooks, CI, and `CONTRIBUTING.md` still govern. The workstation-core template is the target: `AGENTS.md` is the router, the profiles below name the role files, and live state is the repo STATE (`STATE.md`, `STATE-<slug>.md`, `BACKLOG.md`, `archives/` at the repo root; decision 2026-11-22). The store keeps notes only. An older `AGENTS.md`, `CLAUDE.md`, decision log, or state, plan, or handoff file that conflicts with that layout is migrated into it. That conflict is not a blocker and not a reason to stop. Changes in the repo go through **safe-repo-preflight** (branch, checks, PR).

## Profiles
| Profile | For | Repo gets | Store gets (notes only) |
|---|---|---|---|
| **Full** | projects with milestones | router, SPEC, DECISIONS, rules, data, STATE, BACKLOG, archives/; the git hook pack and the `state-files-gate` CI check | `<project>/INDEX.md` |
| **Toolkit** | shared tools, no milestone | router, DECISIONS, rules, STATE, BACKLOG, archives/; the `state-files-gate` CI check | `<project>/INDEX.md` |
| **Light** | small repos | router; STATE, BACKLOG and archives/ only when work starts | `<project>/INDEX.md` |

Add SPEC or DECISIONS to a Light repo only when one is needed. If the profile is not clear, suggest one and ask.

## Steps
1. **Read first.** `AGENTS.md`, `README.md`, and any decisions, state, spec, rules or data files. Note each one's path.
2. **Plan.** For each role, list `exists` (already at the template home; point at it), `migrate` (an older agent doc conflicts with the template layout; its content moves into the template home), `create`, or `skip` (not in this profile). Never create a second file for the same role. A conflict with an older `AGENTS.md`, `CLAUDE.md`, decision log, or state, plan, or handoff file is not a blocker and not a reason to stop.
3. **Ask.** Show the plan and wait for the yes.
4. **Repo files** (on a branch):
   - **Router (`AGENTS.md`):** if missing, write a short one (read order, map, commands). If it already matches the router, add only what is missing: the role table below, the store pointer line (notes only) from `<workstation>/memory/templates/project-pointer-line.txt`, and the line "No HANDOFF or handoffs/ files; STATE-<slug>.md is the handoff." If it conflicts with that layout, migrate it in the plan. Fold any `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` into it (keep every rule, drop exact duplicates), then delete the CLAUDE file in this PR. That fold is pre-approved.
   - **DECISIONS:** a header and the entry format: ID, Status, Context, Decision, Rejected, Supersedes, Reopen if. Append only.
   - **Rules:** `.claude/rules/00-state-protocol.md` (always on): the seven tags and "run state-closeout at 80% context, on a pivot, a blocker, a milestone and a PR". Then `python <workstation>/scripts/state/rules_sync.py` writes `.cursor/rules/`. Never hand-edit those.
   - **SPEC (Full only):** beside DECISIONS, with headings for milestones and done criteria, interfaces, and tolerances. The owner fills it in; agents only read it.
   - **SoT registry:** for every data (values) file this repo treats as a source of truth, add an entry to `.claude/sot.json` (create it if missing; schema in `<workstation>/scripts/state/README.md`): its `paths`, the `checks` that prove it (mark quick ones `fast: true`), `regenerate` and `derived` for generated files, and `report: cells` for a CSV. A SoT with no check is a gap: say so in the report. Then `python <workstation>/scripts/state/sot_guard.py lint-registry` shows no warning you have not reported.
   - **`.gitignore`:** add `TASK.md`.
   - **Git hook pack (Full only):** offer to install it from `<workstation>/hooks/git/`, following its own notes. Install only on a yes.
   - **State files gate (Full and Toolkit, repos with CI):** copy `<workstation>/skills/git-checker/hooks/state-files-gate.sh` to `.github/state-files-gate.sh` and `state-files-gate.yml` to `.github/workflows/`. It blocks a PR that leaves a top-level `STATE-*.md`.
5. **State files.** `python <workstation>/scripts/state/state_manager.py init --repo <dir>` creates `STATE.md` (schema v1, see state-closeout), `BACKLOG.md` and `archives/.gitkeep` at the repo root, and skips files that exist. If the tool is missing, create them by hand the same way. Older state (a store `STATE*.md`, `BACKLOG.md`, `archives/`, or a repo state, plan or open-items file) is migrated in: copied into these files with no content deleted (overflow beyond 30 lines goes to `BACKLOG.md` or `archives/`). Store copies then move to the store's `_archive\<project>\` (never deleted). The store's `<project>/INDEX.md` keeps only notes.
6. **Lint:** `python <workstation>/scripts/state/state_lint.py --repo <dir>` exits 0.
7. **Commit** on the branch, open the PR, and report: each role, its path, and `created`, `exists`, or `migrated`.

## Role table (in the router)
| Role | Location |
|---|---|
| Router | `AGENTS.md` |
| Decisions (why) | `<path>` |
| Rules (how) | `.claude/rules/` (Cursor copies generated) |
| SPEC (done criteria) | `<path>` or none |
| Data (values) | `<paths>` or none |
| Live state | `STATE.md` (trunk), `STATE-<slug>.md` (committed on its branch), `archives/` at the repo root |
| Backlog | `BACKLOG.md` at the repo root |
| Notes | store `<project>/INDEX.md` (preferences, machine facts, gotchas; no status) |
| Branch checklist | `TASK.md` at the worktree root, git-ignored |

## Hard rules
- Show the plan before any overwrite. Ask before a delete that is not the pre-approved CLAUDE fold. A file already at its template home stays. An older agent doc that conflicts with the template is migrated into that home in the plan.
- Live state goes in the repo's STATE files only, never in the store, `INDEX.md` or a `HANDOFF` file.
- No secrets, no personal paths in repo files.
