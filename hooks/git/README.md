# State git hooks

Per-repo git hooks for live state in the memory store. They call the workstation state tools
(`scripts/state/`); they never reimplement them.

| Hook | Does |
|---|---|
| `pre-commit` | Blocks the commit when this branch's STATE file breaks STATE schema v1 (`state_lint.py`), or when `VERIFIED.lock` exists and a locked file changed (`deliverable_lock.py verify`). |
| `post-checkout` | On a branch checkout, creates `STATE-<branch-slug>.md` if it is missing (`state_manager.py new-branch`). |
| `post-merge` | After `git merge <branch>`, archives that branch's STATE file (`state_manager.py archive-branch`), then removes the branch's untracked `TASK.md`. |

No hook writes the root `STATE.md`: it has one writer, the coordinator, and its `Branch_States` line
is generated (`state_manager.py branches`).

`post-merge` sees only a local `git merge <branch>`. A squash merge or a rebase merge on GitHub, and
the `git pull` that brings it in, name no branch, so the hook cannot tell which STATE file to archive.
Archiving then happens through `pr-closeout` / `state-closeout` (`state_manager.py archive-branch`).

`state-hook-lib.sh` is shared by the three. Each hook skips its state steps (and never fails) when the
store is unreachable, the repo has no project folder yet, or the tools or Python 3 are missing. Then it
runs the repo's own hook of the same name, so the pack adds to a repo's hooks instead of replacing them.

## Install in one repo

Run in the repo. `<workstation>` is your workstation clone.

```sh
# Where the state tools are (needed when the hooks are copied, optional when hooksPath points here).
git config workstation.stateTools "<workstation>/scripts/state"

# Repo already has its own hooks folder (for example .githooks): keep it, chain to it.
git config workstation.chainHooksPath "$(git config --get core.hooksPath)"

# Point git at the pack.
git config core.hooksPath "<workstation>/hooks/git"
```

A repo with no `core.hooksPath` skips the chain line. To undo, set `core.hooksPath` back to the value
saved in `workstation.chainHooksPath` (or unset it) and unset the two `workstation.*` keys.

Copy instead of pointing: copy the four files into the repo's hooks folder only when that folder has no
hooks of the same name; otherwise use the chain setup above. Never bypass a hook with `--no-verify`.

## Settings

- `git config workstation.stateLint warn` lets a commit through with a bad STATE file (problems are still printed). The default blocks.
- `WORKSTATION_STATE_TOOLS` overrides `workstation.stateTools`; `WORKSTATION_MEMORY_STORE` overrides the store (both used by the tests).

Tests: `powershell -NoProfile -File hooks/tests/test-state-git-hooks.ps1`.
