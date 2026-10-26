---
name: repo-cleanup
description: >-
  Use when a repo's agent, state, plan, handoff or decision files have sprawled
  (session-start flagged "Cleanup needed", orienting costs too many tokens, or
  there are duplicate decisions/state files): the agent extracts every fact
  with its source and date, clusters and resolves them in context, asks the
  user only true conflicts and important unconfirmed facts, writes one doc per
  type, deletes the superseded docs, and lands it as one PR with every fact
  accounted for.
---
# Repo cleanup

**In one line:** turn a messy repo into one state file, one decisions file and short agent files, without losing anything, and only with the user's yes.

Works the same in Grok, Claude Code and Cursor, on any project folder. State file is `STATE.md` (no line limit). Its only helper is **safe-repo-preflight** (read the repo's rules, work on a branch, run checks, open a PR); git history is the backup (step 1b), and every fact is accounted for (step 8).

---

## When to run
0. **From session-start:** only when its drift check crosses a threshold (T1-T7, session-start step 9) **and the user says yes**. Never every session. Alone: when the user asks.
1. **Normally after the first task** of the day is done. Cleanup should never block real work.
2. **Run it first only if** the mess hides the true state (you can't tell what's current), **or** the repo has a rule saying cleanup comes first.
3. **Freeze rule?** If the repo or user says the repo is frozen, wait until the freeze ends or the user says "go". Don't even create the branch. If the freeze is a "no new docs/rules" freeze, ask whether a cleanup that only merges and deletes counts as allowed, and record the answer.

## Hard rules
- **Nothing changes before the user says yes** to the plan.
- **Merge, then delete.** Git history is the backup: superseded source docs are deleted in the cleanup PR, not moved to `docs/archive/`.
- **Context decides, not file dates.** A newer explicit decision replaces an older one only on the same subject in the same context. Explicit dated user decisions outrank agent notes. What the repo's code/config actually does outranks what docs say. Never "newest file wins". True conflicts are asked (step 6).
- **Facts, not documents.** Never paste whole documents together; move atomic facts with their sources.
- **Log every step** so a usage-limit stop can resume (step 2).
- **Never read or print secrets.**

---

## Steps

### 1. Start safely
1. Run **safe-repo-preflight**: read `AGENTS.md`, hooks, CI; note required checks.
2. Read the session-start note if there is one.

### 1b. Make everything safe in git first (no separate backup)
Git history is the backup. Before any change, list (read-only) and ask the user **per item**: **commit to a branch** · **push** · **leave alone** (leave-alone items are never touched by the cleanup).
- Uncommitted changes (`git status --porcelain`, CRLF-only ignored)
- Untracked files, and ignored files that look like real work (notes, drafts, exports; not build output or caches): `git status --porcelain --ignored`
- Local-only branches and unpushed commits (`git branch -vv`, `git rev-list --count origin/<b>..<b>`)
- Stash entries (`git stash list`): offer "save as a branch" (`git stash branch <name> stash@{n}`) or leave
Then record in `CLEANUP-PLAN.md`: **Starting commit:** `<hash>` (optionally a lightweight tag `cleanup-start-<date>`, pushed only on a yes). **Rollback:** revert the cleanup PR, or reset a branch to that commit.

### 2. Make it resumable
1. Create or open `CLEANUP-PLAN.md` at the repo root (if the repo's doc checks flag it, e.g. for naming deleted files, keep it untracked via `.git/info/exclude` and paste it into the PR body) (on the cleanup branch once it exists; until then, show it in chat).
2. It has a `## Progress` log. Add one line after every finished step: `2026-10-23 22:10 step 4 done: 1,840 facts from 212 files`.
3. **On start, read `## Progress` first.** If earlier steps are logged, skip them and continue from the next one.

### 2b. Automation inventory (read-only, before the fact pass)
1. List every automation: CI workflows, git hooks, cron/scheduled jobs, agent-settings allowlists, Makefile / package scripts, and every script file. For each: trigger, what it reads, what it writes (from reading it; mark "inferred" if guessed), whether it commits on its own, any protection bypass.
2. Draft `automation.yml` (format: git-checker "Automation registry"). **Intentional auto-writers stay** as declared entries with exact `writes`, `trigger`, `auto_commit: true` and `enabled` (ask the user: on or paused?). List any bypass in `bypass`.
3. Run `registry-check.py` on the draft and group what it finds into **one yes** for consolidation fixes:
   - merge duplicate generators (two scripts writing the same output)
   - fold per-batch runner copies into one parameterized runner
   - delete one-off scripts nobody calls (git history keeps them)
   - drop revision/date-named output folders (old revisions live in git)
   - gitignore pure build outputs
   Show each change in the list; a no or skip leaves that item as-is in the registry. Fixes go in the cleanup PR with the registry.

### 3. Save outside-only decisions into the ledger first
Decisions that live only in chats, memory, email or another machine (session-start lists them as "outside the repo"): add each to the fact ledger (step 4) with where it came from and its date, so it's compared like everything else.

### 4. Extract facts (agent does this, not the user)
Read every agent / state / plan / handoff / task / decision / notes file. If a line looks like it holds an actual secret value (a password, token or key written out, not just a mention such as "login is kept in the credentials file"), log only "possible secret at file:line" and ask about rotating it; never copy the value. Before raising it, confirm the value is really in a tracked file (`git ls-files`); a line that only points to an untracked or external credentials store is not a finding. Pull out **atomic facts**: decisions, rules, open items, specs, status. One row each in the **fact ledger**: `## Fact ledger` in `CLEANUP-PLAN.md` (or a temp file outside the main docs; deleted at the end, git keeps it in the PR history).

| ID | Fact | Type | Source (file:line) | Date | Who / context |
|---|---|---|---|---|---|
| F12 | Use Postgres, not SQLite | decision | `OPEN-ITEMS.md:40` | 2026-10-22 (stated) | user, chat plan |

Date = decision date if stated, else the file's last-commit date (`git log -1 --format=%cs -- <file>`); use `git blame -L` only for the facts that end up in a conflict. Large repos: offer subagent batches (step 10); no two batches read the same file; each writes its own ledger part.

### 5. Cluster and resolve automatically
1. **Cluster** facts about the same subject (e.g. "database", "relay box", "release process").
2. **Resolve** each cluster:
   - **Agree:** keep one canonical statement, cite all sources.
   - **Superseded:** a newer explicit decision clearly replaces an older one on the same subject and context: newer wins, logged in **Superseded (auto)** (winner, loser, why) for the user to spot-check.
   - **Stale:** status or history with no ongoing effect (done tasks, old progress notes): drop, with the reason.
   - **Repo reality:** if code/config shows which is true, that wins; cite the file.
   - **Can't tell:** goes to the Ask list (step 6).
3. **Single-source facts** (nothing confirms or contradicts): important ones (rules, specs, decisions that drive work) go to the Ask list; trivial ones are kept with a `(low confidence)` flag.

### 6. Ask only what the agent can't settle
**Re-check before asking.** For every Ask-list item, look for a newer clear decision on the same subject in the newest decision sources: the decisions doc, answered items in the tracker (OPEN-ITEMS / state file), bodies and review comments of PRs merged since the fact's date, and any decision log or memory the agent's app provides (recent chats included, if the app exposes them). If one exists and is dated after both sides, resolve it automatically (it moves to **Superseded (auto)** with the source and date) and write it into the decisions doc if it lives only in chat or memory. Ask only what is still open after this check.
Ask list = true conflicts + important single-source facts. Order by importance; batch them (grouped or multi-select) with the app's question tool: Grok → choice widget · Claude Code → `AskUserQuestion` · Cursor → ask-question; else a numbered list.
- Conflict: **A** (quote, date, source) · **B** (quote, date, source) · **something else** (type it) · **skip for now**.
- Single-source: **confirm** · **change** (type it) · **drop** · **skip for now**.
Skipped items stay on the list and keep their current wording in the output, marked `(unconfirmed)`. Log each answer as a dated line in `DECISIONS.md`. Also show the **Superseded (auto)** list for spot-checking; any line the user flips becomes an answer.

### 7. Plan the output docs (written in step 12, after the yes)
Exactly **one doc per type** (keep the repo's existing names if it has them):
- **Rules / agent doc:** root `AGENTS.md`, short (under ~150 lines), concrete commands, no status or history. `CLAUDE.md` = `@AGENTS.md`. Per-module agent files only where the repo intends them, thin, no rule repeated. Plain `.md` in `.cursor/rules/` is ignored by Cursor; convert to `.mdc` or fold in.
- **`DECISIONS.md`:** one dated line per decision with its source.
- **`STATE.md`** (or the tracker the repo's rules name, e.g. `docs/OPEN-ITEMS.md`; never add a second one):** current goal on top, status, open items (each dated), `**Last cleanup:**` line.
Plan to **delete** every source doc whose facts are fully moved. Task cards that stay get a `Status:` line. No handoffs in throwaway folders.

### 8. Account for every fact (before asking for the yes)
Each ledger row ends as exactly one of: **kept** (where), **superseded** (winner ID), **dropped-stale** (reason), **asked** (answer or skipped). Zero rows unaccounted. Counts go in the PR body.

### 9. Get the yes
Show the user: fact counts (kept / superseded / dropped / asked), the Superseded (auto) list, the Ask list, the output docs and which source docs get deleted, and the subagent offer (step 10) if it applies. **Wait for yes.** Changes to the plan → update and ask again.

### 10. Offer subagents when there's a lot to do
If the approved work splits into **many independent tasks** (e.g. extracting facts from hundreds of files, 50 task cards to add status lines to):
1. Group them into batches. **No two batches touch the same file.**
2. Offer: "This is N independent batches. Want me to launch N subagents, one per batch?" Show which files each batch owns.
3. Only launch after the user approves. Each subagent works on the same cleanup branch (or its own worktree), changes only its files, and logs to `## Progress`.
4. Shared files (`DECISIONS.md`, state file, root `AGENTS.md`) are edited only by the main session.

### 11. Stale branches and worktrees
1. List **every** non-main branch (local and remote) and worktree: merged, unmerged and prunable (folder gone). No age rule. One row each: name, last commit (date + subject), merged yes/no, unpushed commits (`git rev-list --count origin/<b>..<b>`, or "no upstream"), open PR if any.
2. For each branch, compare its changed files with the cleanup's (`git diff --name-only main...<b>`); flag overlapping or conflicting ones first, since merging both will clash.
3. Ask the user **per item**: **keep** · **delete** · **save notes first** (copy its unique notes/decisions into `STATE.md`/`DECISIONS.md` on the cleanup branch, then ask delete again).
4. Delete only on a yes, with normal git: `git branch -d <b>` (refuses unmerged; never `-D` or force for unmerged work), `git worktree remove <path>` (no `--force`), `git worktree prune` for gone folders. Unmerged work or unpushed commits need an explicit "yes, delete unmerged <b>"; save its last commit hash in `CLEANUP-PLAN.md` first (any branch, before deleting).
5. Remote branches (`git push origin --delete <b>`) are a separate yes each.
6. Log each result in `## Progress`. Branches the user keeps go in `STATE.md` as `**Kept branches:** <name> (<date>)` so session-start doesn't re-flag them until they change.

### 12. Apply
1. **Check step 1b is done** (starting commit recorded, nothing unsaved except leave-alone items).
2. **Dry run.** Show the user the exact list of docs written and docs deleted. Wait for yes.
3. **Apply** on the cleanup branch (via **safe-repo-preflight**): write the step 7 docs, `git rm` the superseded sources.
4. **Re-check step 8** on the written docs: every kept fact appears in exactly one output doc; every deleted file is on the approved list (`git diff --name-status <start>`). Then delete the temp ledger (it stays in the PR's history).
5. Run the repo's required checks.

### 13. Open one PR
One PR per repo. Body: fact counts (kept / superseded / dropped-stale / asked / skipped), Superseded (auto) list, docs written and deleted, Ask items still open, starting commit + rollback. Log `PR #N opened` in `## Progress`. Never force-push or skip hooks. Merging is the user's call.

### 14. Finish
Update the state file: remove "Cleanup needed", note the PR, and write `**Last cleanup:** <date> @ <merge commit>` (fill the commit after merge) so session-start skips full cleanup until something changes. Tell the user what's left on the Ask list.

### Hook template
The PR hook lives in `git-checker/hooks/`; its install question is in the git-checker skill. If missing, suggest it; session-start asks the user before installing it.

## Run alone vs. from session-start
Run by hand, this skill does only its own job and never loads another skill. If it finds something worth fixing, it may **suggest** one ("want me to run iterative-cleaning?"). Only `session-start` offers the full chain, and it asks the user before each step.
