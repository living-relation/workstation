---
name: iterative-cleaning
description: >-
  Use when the user says "iterative cleaning" or "find stale docs", or wants docs swept one at a time for stale or conflicting content; also flags 2-run STATE lines and stale BACKLOG. Report-first.
---

# Iterative cleaning

A document-by-document staleness sweep. The running notes go in the branch's `TASK.md`. Works on any repo or project folder.

## When to use
Record findings as you go and wrap around the file tree until you are back at the start file. Also when the user asks "which docs are superseded or conflict with newer ones" or wants the tree walked and audited. Report-first; do not edit docs unless the user says to.

**Scope vs repo-cleanup:** repo-cleanup consolidates agent / state / plan / handoff / decision files into the role layout. This skill sweeps the other prose docs (README, guides, specs, rules docs) for staleness against them. Same judgment rule: a newer explicit decision beats an older one only on the same subject and context; dated user decisions outrank agent notes; what the code/config does outranks what docs say.

## Settle first (ask only if you cannot infer it)

1. **Start file** - the doc the user first asked about (or the first prose doc in the tree). The sweep ends when you are back at it.
2. **Reference change(s)** - the newer decision that made things stale (a merged PR, a renamed part, a retired file). Take it from the user's question, `git log -30 --stat`, and the most recently changed docs. Write it at the top of the sweep section.
3. **Pace** - default is one document (or one tightly related group) per step, then wait for "ok". If the user says to continue without stopping, run the whole loop and report at the end.
4. **Edit mode** - default is report-only. Edit docs only on a clear instruction; edits stay in the working tree uncommitted unless told otherwise.

## Where the sweep notes go

Put them in `TASK.md` at the worktree root (git-ignored), under a `## Stale-doc sweep` heading. Your STATE file keeps one `[NEXT]` line pointing at it. Do not create a separate sweep or handoff file, and do not put the sweep in memory.

Sections inside that heading:

- **Reference change** and **Method**.
- **Done** - numbered items, one per doc or group: verdict (FIXED / FOUND-NOT-FIXED / CURRENT), then bullets with line numbers and the evidence (the newer file or commit that contradicts it).
- **Queue (next)** - what is unread.
- **Shipping** - what is committed and what is not.

Update that section after every step, before replying. Keep each item short: what is stale, why (cite the newer source), where. When the sweep is done, run state-closeout: FOUND-NOT-FIXED items become `[BKLG]` (or `[TASK]` if this branch fixes them), and the sweep section goes.

## Loop

1. **Order the tree.** `git ls-files`, then drop generated files, binaries, vendored data, archives and anything the repo says is not authoritative (read its AGENTS.md / README for these). Keep prose docs, rules, skills, workflows and contract/config docs. Sort the way the tree lists (root files, then directories alphabetically). Rotate the list so it starts at the start file.
2. **Per document:**
   a. Run the scripted check from the repo root: `python -I ~/.claude/skills/iterative-cleaning/refcheck.py --terms '<regex of retired names>' <files>`. It lists missing paths, `file:line` citations that drifted onto blank lines, and retired-term hits. Build the terms regex from the reference change(s): old names, deleted files, renamed parts, old paths.
   b. Read the hits in context, plus the doc's header, status and date lines. Check what no script can: counts ("14 files"), lists of items, "current" vs "planned" statements, cross-references to rows or sections, every pointer ("see X", "rules live in Y", a heading or file link) resolving to a real heading or file, and statements that contradict a newer sibling doc.
   c. Classify each hit: **stale** (fix or flag), **history** (dated log or decision record - leave it, optionally suggest a banner), **cross-repo / intentional** (leave), **false positive**.
   d. For contract and config files, run the repo's own gate (a parity or consistency script) instead of eyeballing; a passing gate is the verdict.
3. **Record** the item in the sweep section. Reply with the verdict, the stale lines, and what comes next.
4. **Cascade.** When a fact is stale, or a heading is renamed, grep the whole repo for every link to it once and list every other place in the sweep section, so later steps start with leads.
5. **Wrap.** At the end of the list, go back to the top and continue until the next file is the start file. Then add a coverage statement: what was swept, what was only scripted, what was out of scope (data tables, generated files, code beyond docstrings).
6. **State and backlog check** (store project folder; read-only):
   - **2-run rule:** list every line in `STATE.md` / `STATE-*.md` marked `(carried 2)` or more, or `python <workstation>/scripts/state/state_lint.py --project <project>` exit 2. Each must graduate (`[ADR]`, `[RULE]`, `[TASK]` or `[BKLG]`) with state-closeout.
   - **Stale BACKLOG:** items older than 30 days (unless the project sets another age) with no `[closed]` line; items whose file, row or branch no longer exists; items already settled in DECISIONS, rules or `TASK.md`. Suggest close or keep for each; closing is a new `[closed <date>] <item>` line, only on the owner's yes.

## Rules

- Evidence over suspicion: every "stale" claim names the newer file, commit or gate that contradicts it. If you cannot find one, write "unverified".
- A dated log or decision record is not stale just for being old; flag it only if it reads as current with no superseded banner.
- If a later step shows an earlier verdict was wrong, correct the earlier item in the sweep section and say so.
- Work inside the repo, never on a parent store folder, except the read-only check in step 6. Do not commit or push unless asked; if asked to push to a protected default branch, use a branch.
- Report depth honestly: a scripted check plus targeted reads is not a full read of every line.

## Run alone vs. from session-start
Run by hand, this skill does only its own job and never loads another skill. If it finds something worth fixing, it may **suggest** one ("want me to run repo-cleanup?"). Only `session-start` offers the full chain, and it asks the user before each step.
