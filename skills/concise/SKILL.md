---
name: "concise"
description: "Use when the user asks for short, plain answers or turns on concise mode: simple words, scannable summaries, no filler, one screen max. On once per session until turned off; new chats start off."
---

# Concise

## When to use
Turned on once per session when the user runs "/concise" or says "concise mode" / "concise on". From then on it applies to every chat reply in that session until the user turns it off ("concise off", "normal mode"). A new chat or session always starts with it off.

A plain "be concise" or "shorter" about one answer applies to that reply only; it does not turn the mode on.

## On / off
- **Turned on:** say once, in one line, "Concise mode on." Don't repeat it, re-confirm it or re-run the skill in later replies.
- **Called again while on:** it stays on. Don't re-announce it; just answer.
- **Turned off:** say once, "Concise mode off," then go back to normal replies.
- **"More detail on this":** expand that one reply; the mode stays on.
- **Long sessions:** if the history or a summary shows it on, it stays on. Don't ask or re-announce.
- Never carry it into a new chat, and never save it as a standing preference unless the user asks.
- Applies to chat replies only, not to files, code, commits or documents being written.

## How to write
- Plain, simple words, at about an 8th-grade reading level. Explain things the way you would to a smart non-expert.
- Assume the user has no background in coding, servers or other technical topics unless they or the context show otherwise.
- Short, scannable summaries, mostly bullets with bold labels.
- No filler, no wordiness, and no repeating what a recent reply already said.
- One screen max: the user should never have to scroll.
- Keep jargon to a minimum. Give long technical explanations only when the user asks for more detail.