# Instructions for Claude and Cursor (paste by hand)

Three texts, pasted by hand ONCE per account. They follow the account to every PC and hold no PC paths.
install.ps1 never edits them; it only checks the Cowork one on disk and prints a TODO if it is missing.

| File | Paste into | Applies to |
|---|---|---|
| `instructions-for-claude.md` | Claude desktop > Settings > account **Instructions for Claude** | regular chats and Cowork |
| `cowork-global-instructions.md` | Claude desktop > Cowork settings > **Global instructions** | Cowork only |
| `cursor-user-rules.md` (only the text inside its code block) | Cursor > Settings > Rules > **User Rules** | every Cursor Agent chat, all projects |

How:
1. Open the file in a text editor (Notepad is fine), select all, copy.
2. Paste it into the box named above, replacing what is there, and save.
3. Do the other files the same way. For `cursor-user-rules.md`, copy only the text inside the code block.

The `## Working memory` paragraph of `cowork-global-instructions.md` is the memory rule for Cowork. It uses
`%USERPROFILE%\.claude\working-memory`, a link install.ps1 creates to the shared memory store, so the same text
works on every PC.

After pasting the Cowork text, remove any old per-project Cowork memory lines from your Cowork projects'
instructions. They repeat the global rule, and the old ones may point at a path that only existed on one PC.

Claude Code is set up separately (install.ps1 and the per-project pointer lines); these texts do not replace it.

`cursor-user-rules.md` holds behavior only: no memory rules (Cursor's memory rule is `claude-shared-memory.mdc`, written by
install.ps1) and no repo rules beyond pointing at each repo's `AGENTS.md`. Cursor stores User Rules in the account, not on disk,
so install.ps1 cannot check them.

`repo-rules.mdc` is the Cursor user-rule version of the repo-rules section (copy to `~/.cursor/rules/`).
