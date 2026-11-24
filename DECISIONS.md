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

## D-2026-11-23-retire-skill-zips: Skill zip tooling retired
- **Status:** accepted, 2026-11-23 (Dan)
- **Source:** Dan, Grok Bot chat (Cursor Project leftovers: retire zips yes; 2026-11-23 ET).
- **Context:** skills reach Claude and Cursor through the workstation-core plugin. The committed `skills/<name>.zip` files, pack scripts, and pack-skill-zips CI bot were leftover install packaging.
- **Decision:** remove `scripts/pack-skill-zips.*`, the pack-skill-zips workflow, committed `skills/*.zip`, and the git-hook exception that allowed those zips. Skills are not installed by zip upload.
- **Rejected:** keeping the packer as an optional local tool.
- **Reopen if:** a consumer still needs a committed skill zip and cannot use the plugin.
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

## D-2026-11-24-install-runs-catalog: install runs the catalog commands; no npm and no local MCP
- **Status:** accepted, 2026-11-24 (Dan)
- **Source:** Dan's approval of items AL, AK, AM, and AQ (2026-11-24).
- **Context:** D-2026-11-23-claude-code-catalog put the Claude Code catalog commands in the docs and rejected having install scripts run them. PC setup also depended on an agent freely reading SETUP-PROMPT.txt. A local npm package or MCP server was considered as another way to ship the same tools.
- **Decision:**
  - `install.ps1` runs `claude plugin marketplace add living-relation/workstation`, then `claude plugin install workstation-core@workstation-plugins`. `install.cmd` starts `install.ps1`, so it runs them too. If the claude CLI is missing, those two commands are skipped and the install continues. Nothing is uninstalled or disabled. Refresh and update stay manual, one command per block, in INSTALL.md and README.md.
  - At the end of a real install, a paste helper does one instruction file at a time: copy it to the clipboard, open it in Sublime Text (`C:\Program Files\Sublime Text\subl.exe`, or notepad if that program is missing), print where to paste, and wait for Enter. Places: Claude Desktop > Settings > General > Instructions for Claude (`instructions/instructions-for-claude.md`); Cowork Global instructions (`instructions/cowork-global-instructions.md`) only if that box exists; Cursor Settings > Rules > User Rules (`instructions/cursor-user-rules.md`). `-Quiet` skips the helper.
  - PC setup is a printed guide with numbered phases (`scripts/setup_guide.py`). SETUP-PROMPT.txt is only a pointer to that script. `scripts/setup_verify.py` fails when a phase was missed. Per-repo setup lives in state-init: the agent scans the repo, proposes which of code, CAD, docs, and harness it stores, asks only the unclear items, and saves the answers in committed `repo-profile.json`. A rerun uses that file.
  - No npm package and no local MCP server for now. The tools are Windows-only PowerShell. The plugins already ship through the Claude catalog and the Cursor copy. MCP tools are model-optional, so they do not replace the start-of-chat rules.
- **Rejected:** leaving the catalog commands as docs-only (the rejected line in D-2026-11-23-claude-code-catalog); an npm package; a local MCP server.
- **Supersedes:** the "No script runs them" decision and the "Rejected: having install scripts run the commands" line of D-2026-11-23-claude-code-catalog. The rest of that entry stays.
- **Reopen if:** Claude Code's catalog install must stay manual, or a non-Windows host needs these tools as an npm package or a local MCP server.

## D-2026-11-24-no-powershell-quiet: no PowerShell means no Stop output and a once-only warning
- **Status:** accepted, 2026-11-24 (Dan)
- **Source:** Dan's bug report in the Grok Bot chat, 2026-11-23 9:25 PM ET: a Linux cloud Claude Code session looped on Stop.
- **Context:** with `powershell` and `pwsh` both missing, `run-ps.sh` printed the loud fail for every hook event, Stop included, so the "open your reply with" instruction came back after every reply.
- **Decision:**
  - Without PowerShell, `run-ps.sh` prints nothing for any event other than `SessionStart` and `SubagentStart`.
  - On those two events, `rules-inject`, `state-inject` and `subagent-rules` run `hooks/rules_fallback.py` (python3, else python), which prints the same rules or state text.
  - If Python is missing or the fallback fails, the loud fail prints at most once per session and event (marker file in `${TMPDIR:-/tmp}` keyed by `session_id`).
- **Rejected:** keeping the loud fail on every event; a separate POSIX sh copy of the rules text (it would drift from the templates).
- **Supersedes:** the `run-ps.sh` bullet of D-2026-11-24-hook-loud-fail. The rest of that entry stands.
- **Reopen if:** Claude Code cloud sessions ship PowerShell, or Python goes missing from them.
