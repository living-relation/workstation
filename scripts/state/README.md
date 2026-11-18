# State tools

Shared tools for live state in the memory store. Python 3, standard library only. Run each with `--help` for its options.

- `state_paths.py`: resolves the store root, the project folder (a worktree uses its main repo's folder) and the branch's STATE file.
- `state_lint.py`: checks STATE files against schema v1 (30 lines, headers, only `[NEXT]`, the `(carried N)` rule); exit 2 on a violation, 0 with a note when the store is unreachable.
- `state_manager.py`: `init`, `verify`, `new-branch` and `archive-branch` for STATE.md, STATE-<slug>.md, BACKLOG.md and archives/.
- `deliverable_lock.py`: `lock`, `verify` and `unlock --confirm <token>` for `VERIFIED.lock` (path to sha256) at the repo root.
- `rules_sync.py`: writes `.cursor/rules/<name>.mdc` from `.claude/rules/<name>.md`; `--check` fails on drift.
- `move_integrity.py`: reports lines lost in a document move (exit 2), accepting proposal tags and `[DONE]` lines found in git history.

Tests: `python -m unittest discover scripts/state/tests`
