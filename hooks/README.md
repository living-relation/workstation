# Plugin hooks

Claude hooks are in `hooks.json`, Cursor hooks in `cursor-hooks.json` (the Cursor manifest `hooks` path).
Every script and its test is listed in `automation.yml`.

## Rules at session start (`rules-inject.ps1`)

Owner decision 2026-11-22: the memory-store rules (`memory/templates/claude-global-memory-section.md`; Cursor:
`claude-shared-memory.mdc` without its front matter) and the harness.design lock rule (`memory/templates/app-locks.md`)
load from this hook in Claude Code, Cowork (Claude SessionStart) and Cursor (sessionStart, `additional_context`).
`install.ps1` no longer creates or appends them in `~\.claude\CLAUDE.md` or `~\.cursor\rules`. If an older install
already appended a marked block there, the hook skips that part so nothing loads twice. Placeholders come from
`WORKSTATION_PROJECTS_ROOT` or `%LOCALAPPDATA%\Workstation\workstation.json`. No projects root: silent exit 0.
Chat on claude.ai runs no hooks and reads no local files; `<Projects>\AGENTS.md` still carries both blocks for agents
without hooks.

## Launcher

Every Claude command is `sh "${CLAUDE_PLUGIN_ROOT}/hooks/run-ps.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/<script>.ps1"`.
`run-ps.sh` runs the script with `powershell`, else `pwsh`; stdin, stdout and the exit code pass
through (exit 2 still blocks). With neither on PATH (Linux containers, WSL) it exits 0 with no output,
so the host shows no hook error and these Windows guards stay out of the way. Claude Code runs hook
commands with `sh -c` on Linux and macOS and with Git Bash on Windows
(`https://code.claude.com/docs/en/hooks`); without Git Bash it falls back to PowerShell, where `sh`
is missing. Cursor commands call `powershell` directly: `sh` is not on the plain Windows PATH.

## Protected files (`protected-files-guard.ps1`)

Owner rule: sources of truth, files locked in `VERIFIED.lock`, `VERIFIED.lock` itself, SPEC files,
paths in `.claude/protected-paths.txt`, and the root `STATE.md` from a branch session are written by
agents, never silently: only with the owner's explicit yes, and checks prove each edit.

| Host | Protected edit | Unlock command | Another branch's `STATE-<slug>.md` |
|---|---|---|---|
| Claude (PreToolUse) | ask | ask | deny |
| Cursor preToolUse | allow + warning | allow + warning | deny |
| Cursor beforeShellExecution | n/a | ask | n/a |

Cursor does not enforce "ask" in `preToolUse`; it does in `beforeShellExecution`
(`https://cursor.com/docs/hooks`). The warning tells the agent it needs the owner's explicit yes in
chat, must report every changed value afterwards, and names the checks that will run. The always-on
Cursor rule `rules/sot-permission.mdc` says the same before any edit.

## Sources of truth (`.claude/sot.json`)

The guard also reads the repo's SoT registry (schema: `scripts/state/README.md`): a listed SoT, or the
registry itself, asks (Claude) or warns (Cursor) like any protected file, and the message names the
entry's fast checks and its commit-time checks. `sot-after-edit.ps1` (Claude PostToolUse, Cursor
postToolUse; Cursor's afterFileEdit has no output fields) runs `sot_guard.py after-edit` and hands the
result to the agent; a failed check or a hand-edited derived file is loud but never blocks. The git
pre-commit pack runs `sot_guard.py check`: there a failure blocks the commit.

Tests: `powershell -NoProfile -File hooks/tests/test-state-protected-files-guard.ps1`,
`powershell -NoProfile -File hooks/tests/test-state-sot-hooks.ps1`,
`python -m pytest -q scripts/test_run_ps_launcher.py`.
