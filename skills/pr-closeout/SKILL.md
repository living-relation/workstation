---
name: pr-closeout
description: >-
  Use after a pull request opens, or when the user says "close out": run state-closeout, commit graduated items on the PR branch, write the PR body State: line, save new preferences, run gates, report.
---

# PR close-out

**In one line:** after a PR opens, graduate the branch's live notes to their homes and say in the PR body what moved.
Memory gets a new preference, rule or cross-project fact only, each fact once. Then check, push and report.

## When to use
Right after a pull request is opened (the local pr-closeout hook says so when it is wired), or
when the user says "update state and memory" / "close out" / "run pr-closeout". Runs
**state-closeout** for this branch, commits the repo homes it touched (DECISIONS, rules, SPEC,
data) on the **same PR branch**, and writes a `State:` line in the PR body. Live state stays in
the store's STATE files, never in a repo file. Shared memory (`INDEX.md`) gets only preferences,
rules and cross-project facts (signed, each fact once). Then runs the repo's gates and doc
hygiene, and reports in a few lines. Any repo.

## Hard rules
- **Repo homes go on the PR's own branch.** Add a commit to the branch you just opened. Never open
  a second PR for it (stacked-PR rule, [[feedback-stacked-prs]]).
- **Read the gates and the router first.** The router `AGENTS.md` role table names DECISIONS, rules, SPEC and
  data. Hooks, CI, and `CONTRIBUTING.md` still govern, including a freeze written there. An older agent doc that conflicts with the workstation-core layout (router, state-init profiles, store STATE) does not freeze this closeout and is not a reason to stop. session-start, state-init, or repo-cleanup migrates it.
- **No progress in the repo or in INDEX.md.** Live state is the store's STATE / STATE-<slug> /
  BACKLOG. Memory notes get preferences, corrections, cross-project facts and external pointers.
- **SPEC and data change only after the owner's yes.**
- **Sign every memory note and index line** `-- <agent>, YYYY-MM-DD` (ET dates).
- **Never force-push, never skip hooks, never merge.** The user merges.
- **Skip what doesn't apply.** A PR that changes no state (a typo fix, a bot regen) needs no
  graduation. Write `State: no change` and move on.

## Steps
1. **What changed.** Read the PR's diff and body (`gh pr view <n> --json title,body,files`, or
   the GitHub tools if there is no `gh`). List each effect: a decision made, a rule learned, a
   value changed, work finished, work left for later, an after-merge step.
2. **Graduate.** Run **state-closeout** (closeout mode) on this branch's `STATE-<slug>.md`, with
   the effects from step 1 as input. Commit the repo homes it changed (DECISIONS, `.claude/rules/`
   plus the generated Cursor copies, SPEC or data after a yes) on the PR branch and push.
   After-merge steps become `[TASK]` or `[BKLG]` lines, never PR-only text.
3. **`State:` line.** Add one line to the PR body (`gh pr edit <n> --body-file <file>`), e.g.
   `State: STATE-<slug>.md -> 1 ADR (<id>), 1 RULE (<file>), 2 BKLG; NEXT updated` or
   `State: no change`. A router line that names another PR-body field stays. A line that puts live state, a handoff, or a `CLAUDE.md` in the repo does not.
4. **Memory.** Find the store with `python <workstation>/scripts/state/state_paths.py`.
   - **Where you run decides how you reach it.** On the PC (Claude Code, Cursor): write
     the files directly. In a cloud session or the Grok Bot: use Desktop Commander or Remote
     Control to reach the PC folder. If no route works, don't create a memory anywhere else.
     Put the facts (and the STATE text) in the report under "to save" so the user or the next
     PC session saves them. Claude desktop online Memory is not this store and is not synced.
   - Save new durable things the user said or that turned up this session: preferences,
     corrections, machine or tool gotchas, external links. One note per fact, with frontmatter
     (name, description, type) and the **Why:** / **How to apply:** lines.
   - Update a note that is now wrong; don't add a duplicate.
   - Add a signed index line for every new note.
   - If a memory note holds project progress, tag it and move it with state-closeout. Tell the
     user the memory copy is stale. Do not delete it without a yes.
5. **Hygiene.** Run the repo's gates from `AGENTS.md` "Commands" (example: `python tools/check_all.py`),
   plus its warn-only doc checks if it has them. Report new warnings only, not old ones.
6. **Report**, in at most 6 lines:
   - state: what moved where (or "no change"), with the commit, and the STATE lint result
   - memory: the notes added or updated (or "none")
   - checks: pass/fail
   - the full PR link
   - anything left for the user (a conflict between rules, a decision, a SPEC/data yes)

## Where it runs
One skill file for every agent. Workstation `install.ps1` copies `handoff/claude/pr-closeout-nudge.ps1`
into `~\.claude\hooks` and wires it in `~\.claude\settings.json` PostToolUse (merge; other hook
entries stay). Cursor on the PC also runs those user Claude hooks, so the same script fires there.
Skills get in only by turning on the workstation-core plugin from the workstation-plugins catalog on claude.ai
(`INSTALL.md`). Turn Sync automatically on so updates arrive after merges to main. Do not copy skills into `~\.claude\skills` and do not upload a skill zip. Where no hook runs (Grok, cloud, Cowork), the description
above is the trigger: run it as soon as you open a PR, or when the user says "run pr-closeout" /
"close out".

## Not this skill's job
Merging, deleting branches before the merge, CI babysitting (the app's Auto-fix does that), and
new docs, scripts or gates in a frozen repo. Archiving STATE-<slug> after the merge belongs to
the git hook pack (post-merge) or `state_manager.py archive-branch`.
