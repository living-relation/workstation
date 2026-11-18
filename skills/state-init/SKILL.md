---
name: state-init
description: >-
  Use when a repo has no state setup yet, or work starts in a router-only repo: adds the router role table, DECISIONS, rules and SPEC, plus STATE, BACKLOG and archives in the store. Never overwrites.
---
# State init

**In one line:** give a repo its role files and its store folder, creating only what is missing.

The project's own rules win over this skill. Changes in the repo go through **safe-repo-preflight** (branch, checks, PR).

## Profiles
| Profile | For | Repo gets | Store gets |
|---|---|---|---|
| **Full** | projects with milestones | router, SPEC, DECISIONS, rules, data; the git hook pack | STATE, STATE-<slug>, BACKLOG, archives |
| **Toolkit** | shared tools, no milestone | router, DECISIONS, rules | STATE, BACKLOG, archives |
| **Light** | small repos | router only | STATE, only when work starts |

Add SPEC or DECISIONS to a Light repo only when one is needed. If the profile is not clear, suggest one and ask.

## Steps
1. **Read first.** `AGENTS.md`, `README.md`, and any decisions, state, spec, rules or data files. Note each one's path.
2. **Plan.** For each role, list `exists` (keep it, point at it), `create`, or `skip` (not in this profile). An existing file that already plays a role keeps its name and place; the role table points at it. Never create a second file for the same role.
3. **Ask.** Show the plan and wait for the yes.
4. **Repo files** (on a branch):
   - **Router (`AGENTS.md`):** if missing, write a short one (read order, map, commands). If present, add only what is missing: the role table below and the line "Store unreachable (PC offline, cloud session): work from committed docs."
   - **DECISIONS:** a header and the entry format: ID, Status, Context, Decision, Rejected, Supersedes, Reopen if. Append only.
   - **Rules:** `.claude/rules/00-state-protocol.md` (always on): the seven tags and "run state-closeout at 80% context, on a pivot, a blocker, a milestone and a PR". Then `python <workstation>/scripts/state/rules_sync.py` writes `.cursor/rules/`. Never hand-edit those.
   - **SPEC (Full only):** beside DECISIONS, with headings for milestones and done criteria, interfaces, and tolerances. The owner fills it in; agents only read it.
   - **`.gitignore`:** add `TASK.md`.
   - **Git hook pack (Full only):** offer to install it from `<workstation>/hooks/git/`, following its own notes. Install only on a yes.
5. **Store.** `python <workstation>/scripts/state/state_manager.py init --repo <dir>` creates STATE (schema v1, see state-closeout), `BACKLOG.md` and `archives/` in `<store>/<project>/`, and skips files that exist. If the tool is missing, create them by hand the same way. Add pointer lines for them to the project's `INDEX.md`; its preference and fact notes stay as they are.
6. **Lint:** `python <workstation>/scripts/state/state_lint.py --repo <dir>` exits 0.
7. **Commit** on the branch, open the PR, and report: each role, its path, and `created` or `exists`.

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
- Never overwrite or rename an existing file. Never move a role's existing file.
- No progress in the repo: live state goes in the store only.
- No secrets, no personal paths in repo files.
