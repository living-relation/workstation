# Instructions for Claude and Cursor (paste by hand)

Texts pasted by hand, once per account. They follow the account to every PC and hold no PC paths.
install.ps1 never edits them and does not check them on disk.

| File | Paste into | Applies to |
|---|---|---|
| `instructions-for-claude.md` | Claude desktop > Settings > account **Instructions for Claude**, if that box is still there | desktop chat |
| `cowork-global-instructions.md` | only if a **Global instructions** box is still there | desktop chat |
| `cursor-user-rules.md` (only the text inside its code block) | Cursor > Settings > Rules > **User Rules** | every Cursor Agent chat, all projects |

How:
1. Open the file in a text editor (Notepad is fine), select all, copy.
2. Paste it into the box named above, replacing what is there, and save.
3. Do the other files the same way. For `cursor-user-rules.md`, copy only the text inside the code block.

## Memory split (verified 2026-11-03, personal account)

Claude desktop Store app **4.4212.0.0** ("Unified Claude": Chat and Cowork merged) no longer writes
memory to local files. A "remember" in Cowork saved a topic to account **online Memory**
(Settings > Your Claude > Memory) and changed no local folder. Local Cowork memory has had no writes
since 2026-10-19. App data for that install lives under `%LOCALAPPDATA%\Claude-Data\claude_<id>`
(older copies may still be under `%APPDATA%\Claude` or the Store package path).

- **Claude Code file store** (`<Projects>\_claude\Claude Projects\Working Memory\memory\`) is the record
  for preferences, rules and cross-project facts. Claude Code reaches it through the `autoMemoryDirectory`
  junction. The guard hook keeps that junction. Project progress stays in each repo's state file.
- **Claude online Memory** is account-level facts about the user. It is separate and not synced with the file store.
- The **work account** is very likely the same and is **unverified**.

`cowork-global-instructions.md` used to tell Cowork to read and write `%USERPROFILE%\.claude\working-memory`.
That paragraph is retired. install.ps1 does not create or check that junction. A leftover link on a PC
is harmless; leave it. Do not delete it from the installer.

Old local Cowork notes are stranded. Copy the ones worth keeping into the Claude Code store, or use the
app's **Import memory** button to bring them into online Memory.

Claude Code is set up separately (install.ps1 and the per-project pointer lines). Pointer lines name the
store path, not `~\.claude\working-memory`. These paste texts do not replace that setup.

`cursor-user-rules.md` holds behavior only: no memory paths (Cursor's memory rule is `claude-shared-memory.mdc`,
written by install.ps1) and no repo rules beyond pointing at each repo's `AGENTS.md`. It does say project
progress goes in the repo state file. Cursor stores User Rules in the account, not on disk, so install.ps1
cannot check them.

`repo-rules.mdc` is the Cursor user-rule version of the repo-rules section (copy to `~/.cursor/rules/`).

`state-sot.mdc` is a one-line alwaysApply Cursor rule: read and keep current the project's state and source of truth (copy to `~/.cursor/rules/`).

The Fusion lock and the harness.design lock are in `cowork-global-instructions.md`, `instructions-for-claude.md`, `cursor-user-rules.md` (inside the paste block), and `repo-rules.mdc`. Re-paste or re-copy those after pulling. On-disk copies are checked by `workstation\shortcuts\workstation-status.ps1 -Locks`.
