# State tools

Shared tools for live state in the memory store. Python 3, standard library only. Run each with `--help` for its options.

- `state_paths.py`: resolves the store root, the project folder (a worktree uses its main repo's folder) and the branch's STATE file.
- `state_lint.py`: checks STATE files against schema v1 (30 lines, headers, only `[NEXT]`, the `(carried N)` rule); exit 2 on a violation, 0 with a note when the store is unreachable.
- `state_manager.py`: `init`, `verify`, `branches`, `new-branch` and `archive-branch` for STATE.md, STATE-<slug>.md, BACKLOG.md and archives/. Only `init` writes the root STATE.md (and never overwrites it; its `Branch:` is the repo's default branch from `origin/HEAD`, else the current branch); `branches` prints its generated `Branch_States` line.
- `deliverable_lock.py`: `lock`, `verify` and `unlock <path> --owner-phrase "<owner's words>"` for `VERIFIED.lock` (path to sha256, plus a dated `_history`) at the repo root. No token is printed or stored; the PreToolUse guard asks the owner before any unlock. `lock` refuses a path already locked with a different hash: unlock first.
- `rules_sync.py`: writes `.cursor/rules/<name>.mdc` from `.claude/rules/<name>.md`; `--check` fails on drift. A hand-made `.mdc` (no generated header) is never overwritten: it is a conflict (exit 2). No `.claude/rules` and no generated `.mdc`: exit 0 with a note.
- `move_integrity.py`: reports lines lost in a document move (exit 2), accepting proposal tags and `[DONE]` lines found in git history (searched without their leading tag).

## STATE schema v1: Pointers

Required: `- Branch_States:`, `- Backlog:`, `- Latest_ADR:`. Optional, root STATE only: `- Last_Cleanup: <date> @ <commit>` (repo-cleanup), `- Kept_Branches: <name> (<date>)` (repo-cleanup), `- Question_Counter: <last ID>` (coordinator-kit). Any other `- Key:` line in Pointers is a violation.

Tests: `python -m unittest discover scripts/state/tests`
