# State tools

Shared tools for live state in the memory store. Python 3, standard library only. Run each with `--help` for its options.

- `state_paths.py`: resolves the store root, the project folder (a worktree uses its main repo's folder) and the branch's STATE file.
- `state_lint.py`: checks STATE files against schema v1 (30 lines, headers, only `[NEXT]`, the `(carried N)` rule); exit 2 on a violation, 0 with a note when the store is unreachable.
- `state_manager.py`: `init`, `verify`, `branches`, `new-branch` and `archive-branch` for STATE.md, STATE-<slug>.md, BACKLOG.md and archives/. Only `init` writes the root STATE.md (and never overwrites it; its `Branch:` is the repo's default branch from `origin/HEAD`, else the current branch); `branches` prints its generated `Branch_States` line.
- `deliverable_lock.py`: `lock`, `verify` and `unlock <path> --owner-phrase "<owner's words>"` for `VERIFIED.lock` (path to sha256, plus a dated `_history`) at the repo root. No token is printed or stored; the PreToolUse guard asks the owner before any unlock. `lock` refuses a path already locked with a different hash: unlock first.
- `rules_sync.py`: writes `.cursor/rules/<name>.mdc` from `.claude/rules/<name>.md`; `--check` fails on drift. A hand-made `.mdc` (no generated header) is never overwritten: it is a conflict (exit 2). No `.claude/rules` and no generated `.mdc`: exit 0 with a note.
- `sot_guard.py`: the source-of-truth registry `.claude/sot.json` (below). `match <path>` (JSON, for the hooks), `after-edit <path>` (fast checks, changed CSV cells vs HEAD; exit 2 on a failure or a hand-edited derived file), `check [--base REF]` (every check of each SoT changed since the merge-base, plus staged, unstaged and untracked files; exit 2; the git pre-commit gate), `lint-registry` (warnings; exit 2 only on an invalid registry). No registry: exit 0.
- `move_integrity.py`: reports lines lost in a document move (exit 2), accepting proposal tags and `[DONE]` lines found in git history (searched without their leading tag).

## STATE schema v1: Pointers

Required: `- Branch_States:`, `- Backlog:`, `- Latest_ADR:`. Optional, root STATE only: `- Last_Cleanup: <date> @ <commit>` (repo-cleanup), `- Kept_Branches: <name> (<date>)` (repo-cleanup), `- Question_Counter: <last ID>` (coordinator-kit). Any other `- Key:` line in Pointers is a violation.

## Source-of-truth registry: `.claude/sot.json`

Agents write and keep sources of truth (SoT), only with the owner's explicit yes; checks prove each edit. Plain JSON (stdlib, and PowerShell reads it natively), committed in the repo:

```json
{
  "entries": [
    {
      "name": "wirelist",
      "paths": ["data/master.csv"],
      "checks": [{"run": "python tools/check_wiring.py", "fast": true}, "python tools/check_all.py"],
      "regenerate": ["python tools/build_lists.py"],
      "derived": ["data/generated/**"],
      "report": "cells"
    }
  ]
}
```

- `paths` (required): repo-relative globs of the SoT files (`*` and `?` stay in one folder, `**` crosses folders, a trailing `/` means the folder; case-insensitive).
- `checks`: commands that must pass, run from the repo root. A string, or `{"run", "fast"}`; `fast: true` checks also run right after each edit.
- `regenerate`: commands that rebuild the derived files.
- `derived`: globs of generated files. They are never edited by hand: a warning after the edit, a failure in `check` unless the entry's SoT changed too.
- `report`: `cells` (CSV: each changed cell, by row and header), `lines`, or `none` (default).
- `name`: optional label (default: the first path).

Where it runs: `protected-files-guard` asks (Claude) or warns (Cursor) before a SoT edit and names the checks; `sot-after-edit` runs `after-edit` and hands the result to the agent; the git pre-commit pack runs `check` (the hard gate); `lint-registry` runs in iterative-cleaning; state-init adds entries.

Tests: `python -m unittest discover scripts/state/tests`
