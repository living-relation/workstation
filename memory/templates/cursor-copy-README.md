# Cursor Copy of Claude Memory

Cursor's one global copy of Claude's memory. It has three parts:

- `claude-memory\` - a mirror of Claude's memory (`_claude\Claude Projects\Working Memory\memory`).
  Only the sync writes here. Cursor reads it but never edits it.
- `cursor-notes\` - notes Cursor writes. The list is in `cursor-notes\INDEX.md`.
  Cursor signs every note and index line `-- Cursor, YYYY-MM-DD`.
- `claude-chat-summaries\` - summaries of Claude chats, written for Cursor only.

## Sync

`_claude\sync-claude-memory-to-cursor.ps1` copies Claude's memory into `claude-memory\`
every 15 minutes (scheduled task `Claude-Memory-To-Cursor-Sync`).
It only goes one way. Nothing here flows back to Claude.

## Claude

Claude may read `cursor-notes\` as extra notes from Cursor.
Claude never reads `claude-memory\` or `claude-chat-summaries\` here, and never writes in this folder.

Everything here is local only. Never commit it to git.
