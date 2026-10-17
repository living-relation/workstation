# Bots (Grok Bot)

Dan wants the same Grok Bot bots on every PC. Same account owner: Dan, using his own accounts. Only the bots in the table below go to other PCs. Don't add any other bot (not Grimoire).

Each bot is carried by a shareable template link. The link brings the bot's setup, but none of Dan's private data or memories. Only two rows get links: Latch, and dr eggbot (added last, after Dan publishes it). dr eggbot fills them in; until then they say `LINK PENDING`. Grok Bot has no share link on purpose. Agent Coordinator is on hold: no link, and it is not added until Dan says go.

**Opening a card always adds a second bot. It never replaces or updates one that is already there.** So never open a card for a bot that already exists on the PC.

| Bot | What it does | Share link |
|---|---|---|
| dr eggbot | Owns this workstation setup package (builds, checks and ships it). | https://x.ai/bot/bZPYmFpgB3LIuoMMKF8Hh (added last, after Dan publishes it) |
| Latch | Keeps the Workstation toolkit (the manual Desktop shortcuts in `<Projects>\_workstation`). | https://x.ai/bot/KkCUAbqzzGb4ZvXPsozEg |
| Grok Bot | Primary router: sends tasks to the right bot and keeps the shared memory tidy. | Already on that PC; don't import a card; follow GROK-BOT-UPGRADE.md. |
| Agent Coordinator | Coordinates work between agents. | On hold, no link yet; add it only when Dan says go. |

## Steps (on the new PC)

1. Sign in to Grok Bot on this PC with Dan's own account.
2. Check which of the bots above already exist on this PC. **Skip each one that exists.** Do not open its card: that would add a second copy. Grok Bot is already there: don't import a card; give the existing one GROK-BOT-UPGRADE.md to follow.
3. Order: Latch first, dr eggbot last. Skip Agent Coordinator unless Dan has said go. For each missing bot that has a link, open its share link (signed in to Grok Bot) and add the bot.
4. Answer the bot's getting-started questions.
5. A row that still says `LINK PENDING` can't be done yet. Note it as left for later and ask dr eggbot for the link.
6. Add only the bots in the table.

## Standing rule for every bot
Follow each repo's own rules, hooks and CI gates (see `agents/projects-AGENTS.md`, section 1). Never bypass one without the owner's explicit yes.
