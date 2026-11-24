# Decisions

Append only. A change is a new entry that names the one it supersedes. Newest at the bottom.

## D-2026-11-22-state-in-repo: live state lives in each repo
- **Status:** accepted, 2026-11-22 (Dan)
- **Source:** Claude Code cloud chat session_01LBrZysuHzUuaj22cwXLigG; confirmed in Dan's Grok Bot chat answers G, H, I, J, K, L, N (2026-11-22/23).
- **Context:** the PR #90 tier rule (2026-11-18) put live state in the PC memory store. Cloud and phone sessions could not reach it, a new coordinator session could not see worker state, and state drifted between the store and the repos.
- **Decision:**
  - All live state lives in each repo, at the worktree root: `STATE.md` (the trunk's, coordinator only), `STATE-<slug>.md` (one per branch, committed on that branch), `BACKLOG.md` (append only) and `archives/`. The PC memory store keeps notes only (preferences, machine facts, gotchas) and can be rebuilt.
  - pr-closeout's final step runs `git mv STATE-<slug>.md archives/STATE-<slug>-<date>.md` as the PR's last commit before merge ("archive the state file"). The `state-files-gate` CI check (block mode) fails a PR into main when any top-level `STATE-*.md` exists outside `archives/`.
  - The coordinator reads worker state with `state_manager.py branches`: `git fetch --prune`, then `git show origin/<branch>:STATE-<slug>.md`, plus each local `git worktree list` path for unpushed work.
  - No HANDOFF/handoffs files; STATE-<slug> is the handoff.
  - State is committed as written (all repos are public; gitleaks still runs). No secrets in state files.
  - Workstation core supersedes all: a repo whose state does not match the template migrates to it with no content deleted (overflow goes to `BACKLOG.md` or `archives/`), and its pointers are updated. Store state copies move to the store's `_archive\` after they are copied into the repo (never deleted).
- **Rejected:** keeping live state in the memory store (PR #90 tier rule); per-branch state left untracked in the worktree; deleting archived branch state.
- **Supersedes:** the 2026-11-18 tier rule (PR #90, "live state in the memory store project folder").
- **Reopen if:** a repo must hold state that cannot be public, or the CI gate blocks real merges it should not.

## D-2026-11-23-claude-code-catalog: Claude Code installs workstation-core from the repo catalog
- **Status:** accepted, 2026-11-23 (Dan)
- **Source:** Dan's Grok Bot chat answers Y and Z (2026-11-23 ET).
- **Context:** the claude.ai synced copy in Claude Code did not refresh after merges (DansPC stayed on the 2026-11-21 copy after Check for updates, a full restart and `claude plugin update workstation-core@synced`, which Claude Code refuses for synced plugins). The work PC had no synced copy at all. So Claude Code never got `hooks/rules-inject.ps1`.
- **Decision:**
  - Claude Code gets workstation-core from this repo's `workstation-plugins` catalog: `claude plugin marketplace add living-relation/workstation`, then `claude plugin install workstation-core@workstation-plugins`. Refresh later with `claude plugin marketplace update workstation-plugins`, then `claude plugin update workstation-core@workstation-plugins`.
  - That copy takes precedence over the claude.ai synced copy of the same name; Claude Code lists the synced one as not loaded. Nothing needs disabling.
  - Claude desktop, Cowork and chat still get the plugin from claude.ai (Sync automatically on). The Cursor copy is unchanged (`install-plugins.ps1`).
  - The commands are in INSTALL.md and README.md, one per block. No script runs them; `install-plugins.ps1` only points to them.
- **Rejected:** claude.ai as the only Claude Code route (it went stale); having install scripts run the commands.
- **Supersedes:** the 2026-11-19 "Claude install is claude.ai only" rule (BACKLOG.md, 2026-11-19 entry), for Claude Code only.
- **Reopen if:** the claude.ai sync reliably refreshes Claude Code's copy, or the two copies stop resolving by precedence.

## D-2026-11-24-hook-loud-fail: a failed rules hook says so
- **Status:** accepted, 2026-11-24 (Dan)
- **Source:** Dan approved the loud-fail and SubagentStart items in the Grok Bot chat that opened this change.
- **Context:** `rules-inject.ps1` and `state-inject.ps1` exited 0 with no output on any error, and `run-ps.sh` did the same when PowerShell was missing. A session could start with no memory-store or lock rules and no sign that they were missing. Claude Code `SessionStart` `additionalContext` also does not reach a Task-tool subagent.
- **Decision:**
  - An unexpected error in those two hooks exits 0 and prints a loud fail. Claude Code gets `systemMessage` (shown to the user) and `hookSpecificOutput.additionalContext` (`https://code.claude.com/docs/en/hooks`). The context tells the agent to open its reply with `WORKSTATION RULES NOT LOADED: <reason>`. Cursor `sessionStart` cannot show a user message, so the same instruction goes in `additional_context` only (`https://cursor.com/docs/hooks`).
  - `run-ps.sh` prints that same Claude JSON when `powershell` and `pwsh` are both missing. `hookEventName` comes from the payload.
  - Expected skips stay quiet: no projects root, nothing to add, not a git repo, repo not migrated, no state file.
  - Claude Code `SubagentStart` (`hooks/subagent-rules.ps1`, no matcher) gives each subagent a short form of the existing memory-store rules and the harness.design lock rule. Output is `hookSpecificOutput.hookEventName` `SubagentStart` plus `additionalContext` (`https://code.claude.com/docs/en/hooks`, SubagentStart).
  - Cursor stays unwired. Its `subagentStart` output is only `permission` `allow` or `deny` (`https://cursor.com/docs/hooks`).
  - The two paste texts say to speak first if a `rules-inject:` header is missing. No other new rule.
- **Rejected:** staying silent on hook errors; a Cursor subagent hook (it cannot carry the rules); blocking the session (these events cannot block).
- **Supersedes:** none.
- **Reopen if:** Cursor's `subagentStart` grows an `additional_context` field, or Claude Code starts passing `SessionStart` context into Task-tool subagents.
