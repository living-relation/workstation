# Bot profile file format (`*.profile.json`, schema 1)

One JSON file per bot (UTF-8, no BOM). It holds **only** what you'd type into the bot's own setup in Grok Bot.
It never holds secrets, server or account ids, memory, chats, routines or attachments.

| Field | Type | Meaning |
|---|---|---|
| `schema` | number | Always `1`. |
| `name` | string | Bot name. It also identifies the bot: an existing bot with the same name (case-insensitive) is the same bot. |
| `title` | string | The short title shown under the name (may be empty). |
| `description` | string | What the bot is for (may be empty). |
| `rules` | string[] | One rule per entry, in order. Duplicates are found by normalized text (lowercase, whitespace collapsed, trailing punctuation dropped). Two rules **conflict** when they start with the same label (the text before the first `:`, up to 40 characters) but say different things. |
| `avatarShape`, `avatarColor` | string | Optional avatar settings (may be empty). |

Any other key (for example `serverId`, `harness`, `memory`, `chats`, `routines`) is dropped with a warning.

`merge-bot-profile.ps1` is generic. It works on any folder of these files and isn't tied to any repo, so other repos
may vendor it next to their own profiles.
