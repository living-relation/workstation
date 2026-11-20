---
name: state-init
description: >-
  Use when a repo has no state setup yet, work starts in a router-only repo, or older agent docs conflict with the template: adds the router role table, DECISIONS, rules and SPEC, plus STATE, BACKLOG and archives in the store. Shows the plan before any overwrite.
---
# State init

**In one line:** give a repo the template layout. Create what is missing, and migrate an older agent doc that conflicts. Show the plan before any overwrite.

Hooks, CI, and `CONTRIBUTING.md` still govern. The workstation-core template is the target: `AGENTS.md` is the router, the profiles below name the role files, and live state is the store STATE. An older `AGENTS.md`, `CLAUDE.md`, decision log, or state, plan, or handoff file that conflicts with that layout is migrated into it. That conflict is not a blocker and not a reason to stop. Changes in the repo go through **safe-repo-preflight** (branch, checks, PR).

## Profiles
| Profile | For | Repo gets | Store gets |
|---|---|---|---|
| **Full** | projects with milestones | router, SPEC, DECISIONS, rules, data; the git hook pack | STATE, STATE-<slug>, BACKLOG, archives |
| **Toolkit** | shared tools, no milestone | router, DECISIONS, rules | STATE, BACKLOG, archives |
| **Light** | small repos | router only | STATE, only when work starts |

Add SPEC or DECISIONS to a Light repo only when one is needed. If the profile is not clear, suggest one and ask.

## Steps
1. **Read first.** `AGENTS.md`, `README.md`, and any decisions, state, spec, rules or data files. Note each one's path.
2. **Plan.** For each role, list `exists` (already at the template home; point at it), `migrate` (an older agent doc conflicts with the template layout; its content moves into the template home), `create`, or `skip` (not in this profile). Never create a second file for the same role. A conflict with an older `AGENTS.md`, `CLAUDE.md`, decision log, or state, plan, or handoff file is not a blocker and not a reason to stop.
3. **Ask.** Show the plan and wait for the yes.
4. **Repo files** (on a branch):
   - **Router (`AGENTS.md`):** if missing, write a short one (read order, map, commands). If it already matches the router, add only what is missing: the role table below and the line "Store unreachable (PC offline, cloud session): work from committed docs." If it conflicts with that layout, migrate it in the plan. Fold any `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` into it (keep every rule, drop exact duplicates), then delete the CLAUDE file in this PR. That fold is pre-approved.
   - **DECISIONS:** a header and the entry format: ID, Status, Context, Decision, Rejected, Supersedes, Reopen if. Append only.
   - **Rules:** `.claude/rules/00-state-protocol.md` (always on): the seven tags and "run state-closeout at 80% context, on a pivot, a blocker, a milestone and a PR". Then `python <workstation>/scripts/state/rules_sync.py` writes `.cursor/rules/`. Never hand-edit those.
   - **SPEC (Full only):** beside DECISIONS, with headings for milestones and done criteria, interfaces, and tolerances. The owner fills it in; agents only read it.
   - **SoT registry:** for every data (values) file this repo treats as a source of truth, add an entry to `.claude/sot.json` (create it if missing; schema in `<workstation>/scripts/state/README.md`): its `paths`, the `checks` that prove it (mark quick ones `fast: true`), `regenerate` and `derived` for generated files, and `report: cells` for a CSV. A SoT with no check is a gap: say so in the report. Then `python <workstation>/scripts/state/sot_guard.py lint-registry` shows no warning you have not reported.
   - **`.gitignore`:** add `TASK.md`.
   - **Git hook pack (Full only):** offer to install it from `<workstation>/hooks/git/`, following its own notes. Install only on a yes.
5. **Store.** `python <workstation>/scripts/state/state_manager.py init --repo <dir>` creates STATE (schema v1, see state-closeout), `BACKLOG.md` and `archives/` in `<store>/<project>/`, and skips files that exist. If the tool is missing, create them by hand the same way. Add pointer lines for them to the project's `INDEX.md`; its preference and fact notes stay as they are.
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
| Live state | store `<project>/STATE.md`, `STATE-<slug>.md` |
| Backlog | store `<project>/BACKLOG.md` |
| Branch checklist | `TASK.md` at the worktree root, git-ignored |

## Hard rules
- Show the plan before any overwrite. Ask before a delete that is not the pre-approved CLAUDE fold. A file already at its template home stays. An older agent doc that conflicts with the template is migrated into that home in the plan.
- No progress in the repo: live state goes in the store only.
- No secrets, no personal paths in repo files.
