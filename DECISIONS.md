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

## D-2026-11-23-read-when-code-index: role table says when to read each file; generated code index
- **Status:** accepted, 2026-11-23 (Dan)
- **Source:** Dan's Grok Bot chat answer AN (2026-11-23 ET, "reask").
- **Context:** agents read every doc at session start or searched the tree to find which script does what. The router role table said where each file is, not when it is needed.
- **Decision:**
  - The router role table (this repo's `AGENTS.md`, and the state-init template) has a "Read when" column.
  - `CODE-INDEX.md` is generated by `scripts/gen-code-index.py` from `git ls-files`: one line per tracked script (tests and `archives/` left out) with its first comment line. Never edited by hand. The `code-index` CI check runs `--check` and fails when it is out of date. Both are in `automation.yml`.
- **Rejected:** a hand-kept code map (it drifts); narrowing the plugin to fewer files (AR, not approved).
- **Supersedes:** none.
- **Reopen if:** the index gets too long to be useful, or the CI check blocks unrelated PRs often.

## D-2026-11-23-workstation-repo-tests: full suite on Windows and Linux, this repo only
- **Status:** accepted, 2026-11-23 (Dan)
- **Source:** Dan's Grok Bot answers t1390s6026 (fix the installer test leak), t1391u (catch failures before a last-minute PR), t1391s6035 (save the full-suite-before-PR rule), and t1392u (workstation PRs only, not repos that only use workstation).
- **Context:** `scripts/test_install_catalog.py` (from #120) ran the paste helper unsealed. On Linux CI that only asserted "Sublime Text and notepad were not found," so the test passed. On DansPC it opened Sublime Text and wrote the real clipboard. Python tests were only partly run in CI, and only on Ubuntu, so Windows-only failures were missed until after the fact.
- **Decision:**
  - Before opening a PR in `living-relation/workstation`, run the full Python test suite and the PowerShell/launcher tests on Linux and on Windows.
  - This repo's `.github/workflows/repo-tests.yml` runs that suite on `ubuntu-latest` and `windows-latest`, and fails if the paste helper writes a real clipboard or opens an editor. The helper is sealed by `WORKSTATION_PASTE_HOOK_DIR` (logs only; no `Set-Clipboard` / `Start-Process` / `subl` / notepad / `clip.exe` / `pbcopy` / `xclip`). Under CI or pytest, a missing hook directory is a hard refusal.
  - This job, runner, and rule apply only to this repo. Do not copy them into state-init, git-checker templates, the plugin install path, or repos that only use workstation.
- **Rejected:** applying the Windows CI job or the full-suite-before-PR rule to every repo that uses workstation.
- **Supersedes:** none.
- **Reopen if:** a consumer repo needs its own Windows suite (add it there, do not reuse this workflow as a template).

## D-2026-11-24-fusion-desktop-lock: a separate per-PC lock for local Fusion Desktop
- **Status:** accepted, 2026-11-24 (Dan)
- **Source:** Dan's Grok Bot message t1393u (2026-11-24 ET): "I need a fusion lock back. Fusion compute doesn't give same functionality so agents still want fusion desktop. It can be a separate lock file from harness design."
- **Context:** #108 retired the Fusion lock when Fusion work moved to Autodesk's official MCP servers. Fusion Compute MCP (headless cloud) cannot do everything, so agents still drive local Fusion Desktop (its built-in MCP at `127.0.0.1:27182`, scripts in the app, or the UI), and two agents must not drive it at once.
- **Decision:**
  - `workstation/app-lock/app-lock.ps1 -Name fusion-desktop` is a second lock, with its own file `%LOCALAPPDATA%\Workstation\fusion-desktop.lock`, log `fusion-desktop-lock.log` and mutex. Holding it never blocks the harness.design lock, and the reverse.
  - Same commands as harness.design: acquire before use, check in at least every 10 min, release when done, never delete the lock file by hand. Rule: `instructions/projects-AGENTS.md` section 5.
  - `check` clears a stale (15+ min) lock only when `Fusion360.exe` is not running; otherwise it says ask the owner.
  - Fusion Compute and Fusion Data MCP need no lock.
- **Rejected:** reusing the harness.design lock file; restoring the old AutodeskFusionMCP fork and its port 8765 open-document probe, junctions, the hourly add-in pull, and any scheduled task, startup task or background keeper.
- **Supersedes:** the "Agents may use Fusion in parallel" part of #108 (Retire the Fusion lock), for Fusion Desktop only.
- **Reopen if:** Fusion Compute MCP covers what agents need from Fusion Desktop, or Fusion Desktop gets a safe multi-agent mode.

## D-2026-11-24-no-fusion-mcp: no Fusion MCP and no Fusion add-ins in this repo
- **Status:** accepted, 2026-11-24 (Dan)
- **Source:** Dan's Grok Bot message t1401u (2026-11-24 ET): "the fusion MCP isn't need to be in the workstation or handbuilt any more. not using it anymore. just keep all fusion specific add ins out of it because they really need to be up to the user"
- **Context:** D-2026-11-24-fusion-desktop-lock named the Fusion Desktop MCP (`127.0.0.1:27182`) and the Fusion Compute and Data MCP servers in the lock rule, the paste files, the hooks and the app-locks template. Dan no longer uses any Fusion MCP.
- **Decision:**
  - The Fusion Desktop lock stays (`app-lock.ps1 -Name fusion-desktop`, same commands and stale rule). It now covers using local Fusion Desktop: running a script in the Fusion app, or driving or clicking the app. No rule, template, hook, paste file or doc here names a Fusion MCP server.
  - Fusion add-ins are up to the user; this repo carries none and gives no add-in rules.
  - `install.ps1` replaces an older `Local Fusion Desktop` line that names the MCP with the template's line in an `<!-- app-locks:v1 -->` block, and still drops the retired `Fusion work uses Autodesk's official` line. Nothing is scheduled.
  - Repo only: no live PC config (Claude, Cursor or MCP registrations) is changed by this decision.
- **Rejected:** dropping the Fusion Desktop lock with the MCP (agents still use Fusion Desktop).
- **Supersedes:** the Fusion MCP parts of D-2026-11-24-fusion-desktop-lock (its built-in MCP wording, "Fusion Compute and Fusion Data MCP need no lock", and its Reopen-if line).
- **Reopen if:** Dan starts using a Fusion MCP again.

## D-2026-11-25-question-ids: two-character question IDs, listed by ID only
- **Status:** accepted, 2026-11-25 (Dan)
- **Source:** Dan in a claude.ai coordinator chat (2026-11-24/25): question IDs are one letter and one digit; "All questions must be one letter and number question id. Not numbered also."; "Moving forward if there's only one 'real' choice to move project forward, use your recommendation. No reason to ask me everything"; B2a: put the rule in workstation-core as its own PR.
- **Context:** coordinator-kit only said IDs come from `Question_Counter`; counters had grown past 2 characters (H55), and the end-of-turn line in the paste files asked for a numbered list, so questions got both a number and an ID.
- **Decision:**
  - A question ID is one capital letter and one digit (A1 to A9, then B1, ...); choices are one lower-case letter with a recommendation.
  - Questions are listed by ID only, never as a numbered list (coordinator-kit, `instructions/instructions-for-claude.md`, `instructions/cursor-user-rules.md`, repo-cleanup's fallback).
  - When only one choice really moves the work forward, the agent takes its recommendation and says so instead of asking.
- **Rejected:** keeping the rule per repo only.
- **Supersedes:** the "numbered list" wording of the end-of-turn line.
- **Reopen if:** more than 26 x 9 open questions are ever needed in one counter.

## D-2026-11-26-hooks-in-plugin: the three workstation hooks ship in the workstation-core plugin
- **Status:** accepted, 2026-11-26 (Dan)
- **Source:** Dan's Grok Bot chat answers t1414u ("Yes", move the hooks into the plugin) and t1416u ("They work. Put them in the package"), 2026-11-26 ET.
- **Context:** `install.ps1` copied memory-link-guard, context-guard and pr-closeout-nudge into `~\.claude\hooks`, wired them (and a context-guard `statusLine`) in `~\.claude\settings.json`, and copied `handoff-at-80.py` into `~\.cursor\hooks` with `~\.cursor\hooks.json` entries and an `armed` flag. A plugin user who never ran install got none of them.
- **Decision:**
  - `hooks/hooks.json` runs memory-link-guard (SessionStart, PreToolUse `Write|Edit`), context-guard (Stop, PreCompact) and pr-closeout-nudge (PostToolUse) with `-FromPlugin`. `hooks/cursor-hooks.json` runs memory-link-guard, pr-closeout-nudge and `handoff/cursor/run-handoff-at-80.ps1` (preCompact, stop).
  - `install.ps1` copies no hook files and writes no hook entries, no `statusLine`, no `~\.cursor\hooks.json` and no armed flag. It still sets `autoMemoryDirectory` (not when that folder is a real folder holding notes) and `pluginConfigs`. It no longer writes `memory-link-guard.config.json`; the guard finds the store through the junction target, and an existing config is still read.
  - A plugin copy stays quiet for an event while the user's settings (or `~\.cursor\hooks.json`) still wire an older installed copy of the same script for that event, so nothing runs twice. Older copies stay until the owner says to remove them; `uninstall.ps1` still removes what an older install recorded.
  - A plugin cannot set a `statusLine`, so context-guard stop mode reads the transcript's last `usage` when no statusline file exists. The compaction point is `CLAUDE_CODE_AUTO_COMPACT_WINDOW` or `autoCompactWindow`, else 200K (1M once usage passes 200K; unverified on 1M-context models).
  - In plugin mode memory-link-guard does nothing on a PC with no memory setup (no `WORKSTATION_MEMORY_STORE`, no guard config, no `autoMemoryDirectory`). The Cursor handoff is armed by default from the plugin; the file `~\.cursor\hooks\state\handoff-at-80\disarmed` turns it off.
- **Rejected:** keeping install-time copies; installing a `statusLine` from the plugin (not supported); removing the existing PC copies in this change.
- **Supersedes:** install.ps1 steps 5 (guard script and config), 6c (hook copies), 7 (hook and statusLine wiring) and 7b (Cursor hooks.json and armed flag).
- **Reopen if:** a client runs plugin hooks differently from its docs (Cowork, Cursor My Machines workers), or the transcript usage reading proves wrong on a 1M-context model.

## D-2026-11-26-no-third-party-installs: workstation installs only workstation-core items
- **Status:** accepted, 2026-11-26 (Dan); amended 2026-11-26 (Dan): our own Desktop Commander remote scripts and shortcuts stay.
- **Source:** Dan's Grok Bot chat, 2026-11-26 ET: "Any plugins that are not managed by us are none of our business and should not be included in an install... The only things we should install are those items related to the workstation core repo package"; card answer t1416s6192 ("Remove claude/, Desktop Commander and the CLAUDE.md+AGENTS.md setting from workstation"); amendment t1417u ("I want the shortcuts we made because we made them").
- **Context:** `install.ps1` step 7c ran `claude/claude-setup.ps1`, which merged 6 MCP servers from `claude/mcp-servers.json` into `~\.claude.json` (prompting for API keys) and installed the official-marketplace plugins listed in `claude/plugins.json`. The toolkit also ships our own Desktop Commander phone-remote scripts, shortcuts and health checks (they run `npx @wonderwhy-er/desktop-commander@latest remote` only when Start is clicked; install never installed Desktop Commander), and install set `pluginConfigs` (Project instructions = claude-md-and-agents-md) in `~\.claude\settings.json`. The `claude/` items and `pluginConfigs` are not workstation-core items.
- **Decision:**
  - `install.ps1` installs only workstation-core items. It adds no MCP servers, installs no other Claude Code plugins and does not set `pluginConfigs`. Which plugins and MCP servers a PC has is the user's choice.
  - Removed from the repo: `claude/` (`mcp-servers.json`, `plugins.json`, `claude-setup.ps1` and its test), the Desktop Commander version pin in `workstation.lock.yaml` (a third-party pin nothing read; Start uses `@latest`), and the `pluginConfigs` code in install, preflight and the Health check.
  - Nothing already installed is removed. `uninstall.ps1` lists MCP servers, plugins and `pluginConfigs` an older install recorded and leaves them as they are. No cleanup step is added.
  - Our own Desktop Commander tooling stays (amendment): `workstation/desktop-commander-remote/` (Start, Stop, status, lib, test), the 3 manual shortcuts in `toolkit.psd1`, the retired Startup-link cleanup, and the Desktop Commander sections in the Health check, orphan tool, `cleanup-legacy.ps1` and `ownership-notes.ps1`. The `windows-mcp` entry in `workstation.lock.yaml` (listed only, never installed) also stays.
- **Rejected:** keeping a curated MCP server and plugin list; removing our own Desktop Commander shortcuts and scripts (first version of this entry; Dan reversed it); removing what older installs added (that stays the user's call).
- **Supersedes:** the 2026-10-29 rule (BACKLOG.md, 2026-10-29) that install makes Claude Code MCP connectors and official-marketplace plugins match `claude\mcp-servers.json` and `claude\plugins.json`; the `pluginConfigs` part of D-2026-11-26-hooks-in-plugin (install no longer sets Project instructions to claude-md-and-agents-md).
- **Reopen if:** workstation-core itself needs an MCP server or another plugin to work.

## D-2026-11-27-agents-pointer-claude-md: a pure `@AGENTS.md` CLAUDE.md is allowed
- **Status:** accepted, 2026-11-27 (Dan)
- **Source:** Dan's choice in the ST185 Link ECU Config project session, 2026-11-27: add an exception for files a repo keeps on purpose by decision.
- **Context:** the SessionStart hook `hooks/agents-md-only-warn.ps1` warned on every CLAUDE file, and session-start and repo-cleanup said to fold and delete every one. A project repo keeps a one-line root `CLAUDE.md` whose only content is `@AGENTS.md`, by its own decision, so Claude Code loads the `AGENTS.md` router (install no longer sets Project instructions, D-2026-11-26-no-third-party-installs). The hook flagged it every session.
- **Decision:**
  - A `CLAUDE.md` or `.claude/CLAUDE.md` whose whole content, ignoring whitespace, is exactly `@AGENTS.md` is an import pointer that adds no rules. The hook does not warn on it, and session-start and repo-cleanup leave it alone when a repo decision keeps it.
  - `CLAUDE.local.md` is never exempt. A CLAUDE file with any other content still warns and is still folded and deleted.
  - The `no-claude-md` CI job and `scripts/check_no_claude_md.py` stay as they are: they guard only this repo, which has no such pointer.
- **Rejected:** a per-repo allow list file; exempting any CLAUDE file a repo names in its decisions (too wide, the hook cannot read decisions).
- **Supersedes:** none; narrows the "AGENTS.md is the only instruction file" rule in session-start and repo-cleanup.
- **Reopen if:** Claude Code reads `AGENTS.md` on its own, so the pointer is no longer needed.

## D-2026-11-28-rec-marker: every recommended choice is marked with ⭐, and the question rule loads in every session
- **Status:** accepted, 2026-11-28 (Dan)
- **Source:** Claude Code cloud chat session_01LBrZysuHzUuaj22cwXLigG, 2026-11-28: "Workstation core needs to enforce questions that get asked using 2 character ids, 1 letter, and 1 number. Never more. Each multiple choice answer uses a lower case letter. No normal numbered questions, and no numbers used in combination with the 2 character question id."; "every recommended answer for questions needs to be marked with the same emoji"; answers A1a (enforce it in workstation-core) and A2b (Claude Code opens the PR).
- **Context:** D-2026-11-25-question-ids put the ID rule in coordinator-kit and the paste files only. The concise skill had no ID rule (its examples used `w3`, `p1`) and marked the recommendation with `(rec)`, so agents drifted to IDs such as `q10`. `state_lint.py` accepted any `Question_Counter` value (its test used `Q22`).
- **Decision:**
  - The recommended choice is marked with ⭐ right after its letter and before its words (`a) ⭐ <words>`), every time and only there. No other marker replaces it (Dan, 2026-11-28: "after the recommended question's letter, before the answer's words, not at the end of the answer").
  - The question rule (`memory/templates/questions.md`, marker `questions:v1`) is printed at every session start by `hooks/rules-inject.ps1` and `hooks/rules_fallback.py`, next to the memory and app-lock blocks, so it applies in every Claude Code, Cowork and Cursor session with the plugin.
  - The concise skill, coordinator-kit, repo-cleanup's fallback and both paste files state the same rule.
  - `state_lint.py` fails a `- Question_Counter:` value that is not exactly one capital letter and one digit 1-9.
- **Rejected:** a different emoji per agent; leaving the rule in coordinator-kit only.
- **Supersedes:** the "with your recommendation" / `(rec)` wording in the concise skill, coordinator-kit and the paste files (D-2026-11-25-question-ids stays for the ID format).
- **Reopen if:** an app cannot show ⭐.
