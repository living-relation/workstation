---
name: git-checker
description: >-
  Use when you need to know whether the local clones of the user's repos (on
  any OS) match the remote main: current branch, ahead/behind
  origin/main, uncommitted or untracked files, stashes, unmerged branches,
  worktrees, missing upstreams, stale generated outputs. Any project folder.
  Read-only: only `git fetch`. Suggests fixes, never applies them. Also holds
  the warn-only PR state-file hook templates (hooks/).
---
# Git checker

**In one line:** fetch, look, report. Never change a repo.

Works in Grok, Claude Code and Cursor. session-start runs it as its health check. Run alone, it only reports and may suggest `repo-cleanup` or `safe-repo-preflight`.

---

## Hard rules
- **Read-only.** The only network/write command allowed is `git fetch --prune`
  (it only updates remote-tracking refs). Never `pull`, `reset`, `checkout`,
  `switch`, `merge`, `rebase`, `stash pop/drop`, `clean`, `branch -d`,
  `worktree remove/prune`, or `push`.
- **Follow `safe-repo-preflight`.** Any fix you suggest goes through that
  skill: the repo's own rules first, a branch, a PR, no force-push, no
  `--no-verify`.
- **Suggest, never fix.** Each problem gets a suggested command in the report.
  The user (or a later, approved session) runs it.
- **Never read or print secrets.** Show file *names* only, never contents.
- **Line endings don't count.** CRLF-only differences are not "dirty"
  (`core.autocrlf` is ignored per-command via `git -c`, and diffs use
  `--ignore-cr-at-eol`).

---

## Inputs
| Input | Meaning | Default |
|---|---|---|
| `Roots` | list of folders that hold repo clones | ask the user / read from their notes or memory |
| `Depth` | how deep to look for `.git` under each root | 2 |
| `MainBranch` | branch to compare against | `origin/HEAD`, else `main` |
| `NoFetch` | skip `git fetch` (offline) | off |

Machine-specific roots live in the user's memory or notes, not in this skill.

---

## Steps
1. **Pick the script.** PowerShell: `git-checker.ps1`. bash (Linux/macOS/WSL):
   `git-checker.sh`. If one machine has two environments (e.g. Windows + WSL),
   run each on its own roots; don't scan the other side's mounted drive.
2. **Run it** with the roots:
   ```powershell
   pwsh -File git-checker.ps1 -Roots 'D:\code','E:\work'
   ```
   ```bash
   bash git-checker.sh ~/code ~/work
   ```
3. **Read the table.** One row per repo (columns below).
4. **Give the verdict list** exactly as printed, then for each non-OK repo one
   suggested fix (see table). Do not run them.
5. If `fetch` fails (no network, no auth), say so for that repo, mark the
   ahead/behind as `?` and continue. Don't start a sign-in.

---

## Columns
| Column | Command (read-only) |
|---|---|
| Branch | `git branch --show-current` (`(detached)` if empty) |
| Ahead/Behind | `git rev-list --left-right --count HEAD...origin/main` |
| Dirty | `git -c core.autocrlf=true status --porcelain` tracked lines, rechecked with `git diff --ignore-cr-at-eol --quiet` |
| Untracked | `git status --porcelain` `??` count |
| Stash | `git stash list` count |
| Unmerged | `git branch --no-merged origin/main` count, excluding main itself |
| Worktrees | `git worktree list` count minus 1 |
| Fetch | `ok` / `FAIL` / `skip` (`-NoFetch`) |
| Upstream | `git for-each-ref --format=%(upstream:short) refs/heads/<branch>`; `NONE` if missing |

## Verdicts (first match wins)
| Verdict | When | Suggested fix (not run) |
|---|---|---|
| **DIRTY** | uncommitted changes, untracked files or stashes | review; commit on a branch + PR, or stash/discard by hand |
| **NO-REMOTE** | no `origin`, or no `origin/<main>` ref | check `git remote -v` and the default branch name |
| **WORKTREE** | the folder is a git worktree (`.git` is a *file* whose git-dir differs from the common dir). Shown as `repo@worktree`, never as its own project | finish its branch via PR; after merge `git worktree remove` by hand |
| **OFF-MAIN** | not on main (or detached), or no upstream | finish the branch via PR; `git switch main` when clean; `git branch -u origin/<branch>` |
| **UNKNOWN** | fetch failed, so ahead/behind can't be trusted | check network/auth, re-run |
| **DIVERGED** | on main, ahead > 0 **and** behind > 0 | move local commits to a branch + PR, then reset main by hand |
| **AHEAD** | on main, unpushed commits only | move them to a branch + PR; don't push to main |
| **BEHIND** | on main, behind only | `git pull --ff-only` |
| **OK** | on main, 0/0, clean, upstream set | nothing |

A failed fetch shows as `FAIL` in the **Fetch** column (`ok` / `FAIL` / `skip`)
and the verdict becomes **UNKNOWN** (never OK/AHEAD/BEHIND/DIVERGED), since
ahead/behind is against a possibly stale `origin/main`.

**Worktrees.** A worktree's `.git` is a file
(`gitdir: <repo>/.git/worktrees/<name>`). Treat the folder before `.git/worktrees/`
as the project: label the row `repo@worktree`, don't count nested worktrees
(e.g. `.claude/worktrees/x/`, `.worktrees/x/`) as untracked files in the parent,
and flag *prunable* worktrees (registered, folder gone) on the parent row.
Submodules also have a `.git` file but are plain repos (git-dir equals common dir).

Every non-main branch (merged and unmerged), extra and prunable worktrees, and stashes are listed as notes even when
the verdict is OK/BEHIND, so nothing is hidden.

---

## Deployed copies (optional)
A repo can be OK while the files it *installs* are stale: installers that only
append when a marker is missing, or a copy on one PC where the other PC uses a
symlink. When the user's notes list deployed files (repo file and installed
path), compare them read-only and add one line each:
`LINK` (symlink to the repo copy), `MATCH` (same hash), `DRIFT` (different:
suggest re-running the repo's install/link step), `MISSING`. Never copy or relink.

## Automation registry (optional, `automation.yml` at the repo root)
One entry per script, workflow, hook and scheduled job. Template: `hooks/automation.example.yml`. Fields: `id`, `script`, `helpers`, `trigger` (manual | pr-check | push-main | cron:<expr> | called-by:<id>), `reads`, `writes` (exact outputs), `committed` (yes | gitignored | artifact), `auto_commit`, `enabled` (on/off switch), `bypass` (any protection bypass, e.g. a deploy key), `run_cmd`, `check_cmd`, `owner`. Top level: `generated_patterns`, `ignore`, `handmade` (hand-made docs never flagged). Built-in ignore: vendor, third_party, datasheets, manuals, reference(s), handmade folders; a PDF/HTML/XLSX is flagged only when a writer script names it or sits in its folder, or a `<stem>.checks.json` is beside it.

**Intentional auto-writers are allowed.** A bot or workflow that commits its own outputs (e.g. a dashboard updater) is never flagged when its entry lists its exact `writes`, `trigger`, `auto_commit: true` and `enabled`. Protection bypasses go in `bypass` and are shown as a NOTE, not forbidden. Pause one with `python3 hooks/registry-check.py --set <id> off` (resume: `on`), committed via a PR; the workflow's first step runs `registry-check.py --enabled <id>` and exits when `false`.

Run read-only: `python3 hooks/registry-check.py` (add `--diff <base> <head>` in a PR, `--run-checks` to run each enabled `check_cmd` and catch writes outside `writes`). Flags (same comment/block mode as the hook):

| Flag | Means |
|---|---|
| **STALE-OUTPUT** | an entry's `reads` or script was committed after its `writes` (marked "paused" if `enabled: false`) |
| **ORPHAN-SCRIPT** | a script/workflow/hook with no entry, or an entry whose script is gone |
| **UNDECLARED-OUTPUT** | a tracked generated-looking file no entry writes; a `check_cmd` that wrote outside its `writes`; a workflow that commits/pushes without `auto_commit: true` |
| **DUPLICATE-OUTPUT** | two entries write the same file, or outputs sit in revision/date-named folders (`*-revN`, `*-vN`, `*-YYYY-MM-DD`) |

The hook skips declared outputs when deciding "code changed", so a declared auto-commit never trips the state check.

## Generated outputs (optional, without a registry)
In any repo, a file can be built from a script (for example a PDF
BOM from a drawing script). When the user's notes or the repo's own rules list
generator and output pairs, compare read-only with
`git log -1 --format=%ct -- <path>` and add one line each: `FRESH` (output committed
after its generator) or `STALE-OUTPUT` (generator changed later: suggest re-running the
repo's own build step on a branch + PR). Never regenerate. A repo's own "drawings
current" check may not cover generator scripts, so don't treat its pass as proof.

---

## Output format
```
Repo        Branch   A/B   Dirty Untr Stash Unmrg WT Fetch Upstream
proj-a      main     0/3   0     0    0     2     1  ok    origin/main
app-x       feat/y   2/0   4     1    1     0     0  FAIL  NONE

proj-a  BEHIND   — 3 behind origin/main. Suggest: git pull --ff-only (after safe-repo-preflight)
app-x   DIRTY    — 4 changed, 1 untracked, 1 stash. Suggest: review, commit on a branch + PR
```
Keep it to the table plus one line per repo. No extra prose.

---

## PR hook (templates in `hooks/`, installed only on the user's yes via session-start)
Never commits, pushes or opens PRs. **Mode toggle:** `bash state-check.sh --mode comment|block` writes `.state-check-mode` at the checkout root; commit it on a branch + PR. Default `comment` (warns, always passes). `block` = exit 1 on a missing state update or unrecorded after-merge step, so the PR check fails / the commit is refused. The `no-state-change` label (PR) or `[no-state]` (commit message) passes in both modes.
- `state-check.sh <base> <head>`: shared logic. Warns when "code" changed but `STATE.md` / `DECISIONS.md` / `OPEN-ITEMS*` / `AGENTS.md` didn't, and when a PR body or commit message has an "After merge" / "Not done here" step not found in `STATE.md` or OPEN-ITEMS. "Code" = everything except `*.md` and `docs/`, so drawing and BOM generator scripts count. Override per repo with `.state-check-paths`. Resolves worktrees to the main repo (`git rev-parse --git-common-dir`).
- `state-check.yml`: GitHub Action for repos with CI (script copied to `.github/state-check.sh`). Comments on the PR; fails the check only in block mode; skipped by the `no-state-change` label.
- `pre-commit-hook.yaml`: local `pre-commit` entry (commit-msg stage) for repos without CI (script copied to `hooks/state-check.sh`; activate with `pre-commit install --hook-type commit-msg`). The commit message is passed in, so an "After merge" step in it is checked too. Refuses the commit only in block mode. Skip per commit with `[no-state]` in the message, never `--no-verify`.
- If `automation.yml` exists, the hook also runs `registry-check.py` (copy it next to `state-check.sh`) in the same mode.
- No line limit on `STATE.md`.

### Install question (show every time, word for word, filling the <>)
> **No PR hook in <project>. Install one? It goes in as its own PR, which you merge.**
> **What it checks** on every PR (or every commit if the repo has no CI):
> 1. Real work changed (code, scripts, drawings, data; not just `.md`/`docs/`) but `STATE.md`, `DECISIONS.md` or OPEN-ITEMS wasn't updated.
> 2. The PR or commit mentions an "after merge" or "not done here" step that isn't written in `STATE.md` or OPEN-ITEMS.
>
> 3. If the repo has `automation.yml`: scripts, workflows and outputs match the registry (undeclared writers, orphan scripts, stale or duplicate outputs). Declared auto-writers are allowed.
>
> **COMMENT mode (default):** posts a warning on the PR (or prints it at commit). It never stops a PR or a commit.
> **BLOCK mode:** fails the PR check, or refuses the commit, until the state file is updated.
> **Escapes (both modes):** add the `no-state-change` label to the PR, or put `[no-state]` in the commit message.
> **Switch later:** `bash <script path> --mode comment` or `--mode block`, then commit `.state-check-mode` on a branch + PR.
> **Turn it off / uninstall:** on a branch + PR, delete <`.github/workflows/state-check.yml` and `.github/state-check.sh`> (CI) or <run `pre-commit uninstall --hook-type commit-msg` first, then delete the `state-check` entry in `.pre-commit-config.yaml` and `hooks/state-check.sh`> (no CI), plus `.state-check-mode` and `registry-check.py` if installed. `automation.yml` can stay as documentation. Nothing else is left behind.
> **If you say no:** nothing is installed. I won't ask again this session; I'll ask again only the next time you run session-start.
>
> **Install? 1. Yes, comment mode · 2. Yes, block mode · 3. No**

On no: add `Hook: declined <date>` to the state note. Never re-ask in the same session.
