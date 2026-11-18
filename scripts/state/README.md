# State tools

Shared tools for live state in the memory store. Python 3, standard library only. Run each with `--help` for its options.

- `state_paths.py`: resolves the store root, the project folder (a worktree uses its main repo's folder) and the branch's STATE file.
- `state_lint.py`: checks STATE files against schema v1 (30 lines, headers, only `[NEXT]`, the `(carried N)` rule); exit 2 on a violation, 0 with a note when the store is unreachable.
- `state_manager.py`: `init`, `verify`, `branches`, `new-branch` and `archive-branch` for STATE.md, STATE-<slug>.md, BACKLOG.md and archives/. Only `init` writes the root STATE.md (and never overwrites it); `branches` prints its generated `Branch_States` line.
- `deliverable_lock.py`: `lock`, `verify` and `unlock <path> --owner-phrase "<owner's words>"` for `VERIFIED.lock` (path to sha256, plus a dated `_history`) at the repo root. No token is printed or stored; the PreToolUse guard asks the owner before any unlock.
- `rules_sync.py`: writes `.cursor/rules/<name>.mdc` from `.claude/rules/<name>.md`; `--check` fails on drift.
- `move_integrity.py`: reports lines lost in a document move (exit 2), accepting proposal tags and `[DONE]` lines found in git history.

Tests: `python -m unittest discover scripts/state/tests`
