# Plugin hooks

Claude hooks are in `hooks.json`, Cursor hooks in `cursor-hooks.json` (the Cursor manifest `hooks` path).
Every script and its test is listed in `automation.yml`.

## Rules at session start (`rules-inject.ps1`)

Owner decision 2026-11-22: the memory-store rules (`memory/templates/claude-global-memory-section.md`; Cursor:
`claude-shared-memory.mdc` without its front matter) and the app lock rules for harness.design and Fusion Desktop (`memory/templates/app-locks.md`)
load from this hook in Claude Code (SessionStart and SubagentStart) and the Cursor desktop app (sessionStart,
`additional_context`). Cowork runs plugin hooks in its own sandbox, likely Linux with no PowerShell, so `run-ps.sh`
loads the rules through `rules_fallback.py` when Python is there, else reports WORKSTATION RULES NOT LOADED once
per session (unverified in Cowork; see Launcher); a cloud Cowork session may not fire
SessionStart at all (unverified). A Cursor My Machines worker session: Cursor's docs list project `.cursor/hooks.json`
and `~/.cursor/hooks.json`, not local plugins, so the plugin's hooks may not run there (unverified). Chat runs no hooks.
`install.ps1` no longer creates or appends them in `~\.claude\CLAUDE.md` or `~\.cursor\rules`. If an older install
already appended a marked block there, the hook skips that part so nothing loads twice. Placeholders come from
`WORKSTATION_PROJECTS_ROOT` or `%LOCALAPPDATA%\Workstation\workstation.json`. No projects root: silent exit 0.
An unexpected error is a loud fail (still exit 0, so the session is not blocked). Claude Code gets `systemMessage`
(the visible warning) and `additionalContext` inside `hookSpecificOutput` (`hookEventName` `SessionStart`).
Cursor `sessionStart` cannot show a user message (`https://cursor.com/docs/hooks`), so the same instruction goes
in `additional_context` only. The instruction tells the agent to open its reply with
`WORKSTATION RULES NOT LOADED: <reason>`. `state-inject.ps1` uses the same loud fail.
Chat on claude.ai runs no hooks and reads no local files; `<Projects>\AGENTS.md` still carries both blocks for agents
without hooks. The paste texts `instructions/instructions-for-claude.md` and
`instructions/cowork-global-instructions.md` say to speak first if the `rules-inject:` header is missing.

## Subagent rules (`subagent-rules.ps1`)

Claude Code `SessionStart` context does not reach a Task-tool subagent. `hooks/hooks.json` runs this script on
`SubagentStart` (no matcher, so every agent type gets it). The event name and output schema are in
`https://code.claude.com/docs/en/hooks` (SubagentStart): `hookSpecificOutput.hookEventName` is `SubagentStart`
and `additionalContext` is a short form of the memory-store rules and the app lock rules (harness.design, Fusion Desktop), starting
with the `rules-inject:` header. For the built-in `web-fetch` subagent, Claude Code runs `SubagentStart` hooks
from managed settings only, so this plugin hook does not fire there.

Cursor is out of scope. Its `subagentStart` hook can only return `permission` `allow` or `deny` (and
`user_message` when denied). It has no `additional_context` (`https://cursor.com/docs/hooks`). `"ask"` is
treated as deny. `hooks/cursor-hooks.json` does not wire this script.

## Launcher

Every Claude command is `sh "${CLAUDE_PLUGIN_ROOT}/hooks/run-ps.sh" "${CLAUDE_PLUGIN_ROOT}/<path>/<script>.ps1" [args]`
(most scripts are in `hooks/`; memory-link-guard, context-guard and pr-closeout-nudge run from `memory/hooks/` and
`handoff/claude/` with `-FromPlugin`, see `handoff/README.md`).
`run-ps.sh` runs the script with `powershell`, else `pwsh`; stdin, stdout and the exit code pass
through (exit 2 still blocks). With neither on PATH (Linux cloud sessions such as Claude Code web and
mobile, containers, WSL) it always exits 0:
- Any event other than `SessionStart` or `SubagentStart` (`Stop`, `PreToolUse`, `PostToolUse`, and so on)
  prints nothing. Output on `Stop` is fed back to the agent after every reply, which looped the session.
- On `SessionStart` or `SubagentStart`, `rules-inject`, `state-inject` and `subagent-rules` run
  `rules_fallback.py` with `python3` (else `python`). It prints the same text as the PowerShell hook from
  the same templates, state tools and `subagent-rules.ps1` lines. With no projects root (a cloud session),
  paths show as `<Projects>`. Other scripts (`agents-md-only-warn`) print nothing.
- If Python is missing or the fallback fails, it prints the loud fail (`systemMessage` plus
  `additionalContext`) at most once per session and event. The marker is an empty file
  `${TMPDIR:-/tmp}/workstation-rules-warned-<session_id>-<event>`; with no `session_id` it prints every time.
  `hookEventName` is copied from the payload's `hook_event_name`, or `SessionStart` when absent.

Claude Code runs hook
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
