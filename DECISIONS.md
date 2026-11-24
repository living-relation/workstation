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

## D-2026-11-24-health-indicators: health lines tell running, off, and broken apart
- **Status:** accepted, 2026-11-24 (Dan, approved health-check fixes)
- **Source:** Dan's approved list AA-AH, AO, AP (verified read-only on DansPC 2026-11-23).
- **Context:** Desktop Commander remote and Cursor worker lines printed [ OK ] in every branch, including off, extra copies, and a worker that died at once. The Cursor app starts its own worker on launch and puts the API key on that process command line.
- **Decision:**
  - Those two sections use [ RUN ] (running or healthy), [STOP] (off, normal for a manual start), [WARN] (extra copies, started outside our script, or an autostart), [FAIL] (died or broken), and [ -- ] (not checked). The health check exits 1 on any FAIL.
  - A Cursor-app or hand-started worker is reported by folder and pid only. The command line is never printed.
  - App-launch restart is a WARN when a `cursor-agent-worker-*.restart.json` file is present. When it is absent, the other line says "no Windows startup entry" and does not claim the app will stay off.
  - The skills line is information about the claude.ai synced copy. `workstation-core@synced` set to false is not "not added".
  - The Claude Code lock line uses the enabled copy from `installed_plugins.json`. The app-lock status check passes only on exit 0.
  - Cowork loading `rules-inject.ps1`, and a Cursor worker session running `hooks/cursor-hooks.json`, stay unverified (`hooks/README.md`).
- **Rejected:** printing [ OK ] for every branch; printing the worker command line; saying the app does not start a worker when `restart.json` is missing.
- **Supersedes:** none
- **Reopen if:** the Cursor app stops writing `restart.json` when it starts a worker on launch.
