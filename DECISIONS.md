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

## D-2026-11-23-health-indicators: health check marks running, stopped and plugin versions
- **Status:** accepted, 2026-11-23 (Dan)
- **Source:** Dan's Grok Bot chat answers AA-AH and AO (2026-11-23 ET, "reask").
- **Context:** the health check printed `[ OK ]` for a stopped Desktop Commander remote and a stopped Cursor worker, missed a worker that died right after Start ("Authentication required for worker mode"), missed the worker the Cursor app starts by itself, said nothing about which workstation-core version each app had, and passed the Claude Code lock check on any stray `rules-inject.ps1` under `.claude\plugins`. The lock-script loop also ran `status -Name h` twice.
- **Decision:**
  - Marks: `[ OK ]` checked and fine, `[ RUN ]` running, `[STOP]` off (normal for a manual tool), `[ -- ]` not checked or info only, `[WARN]` / `[FAIL]` needs a fix.
  - Desktop Commander: 0 copies STOP, 1 healthy RUN, 1 stale or extra copies WARN.
  - Cursor worker: STOP or RUN for workers Start started; RUN for the Cursor app's own worker (never stopped by Stop, command line never printed); FAIL for a worker Start recorded that exited with an error since the last boot; WARN when the Cursor app restarts its own worker at app launch (`<worker>.restart.json`). The startup line only claims sign-in and reboot.
  - Start Cursor worker waits up to 8 s and fails (exit 1, error line, `agent login` advice) when the worker exits right away.
  - Plugins section: Claude Code catalog copy vs this clone's `origin/main` (WARN when behind, with the two update commands); Cursor copy vs this clone's tracked plugin files; the claude.ai synced copy is info only (a script cannot see the website). A synced copy turned off in Claude Code still counts as on claude.ai.
  - The Claude Code lock check passes on the hook only from the enabled `workstation-core@workstation-plugins` record in `installed_plugins.json`. The lock script check passes on exit 0 only, once.
- **Rejected:** `[ OK ]` for stopped manual tools; printing worker command lines (they carry a key); narrowing the plugin to fewer files (AR, not approved).
- **Supersedes:** none.
- **Reopen if:** Claude Code changes the `installed_plugins.json` layout, or the Cursor app stops keeping `<worker>.restart.json`.
