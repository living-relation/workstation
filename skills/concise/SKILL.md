---
name: "concise"
description: "Use when the user asks for short, plain answers or turns on concise mode: simple words, scannable summaries with Done / Found / Next / Open headers, no filler, one screen max. On once per session until turned off; new chats start off unless the project prefers it on."
---

# Concise

## When to use
Turned on once per session when the user runs "/concise" or says "concise mode" / "concise on". From then on it applies to every chat reply in that session until the user turns it off ("concise off", "normal mode"). A new chat or session starts with it off, unless the project's saved preferences, memory or project instructions say concise mode is on for that project: then it is on from the first reply, without announcing it.

A plain "be concise" or "shorter" about one answer applies to that reply only; it does not turn the mode on.

## On / off
- **Turned on:** say once, in one line, "Concise mode on." Don't repeat it, re-confirm it or re-run the skill in later replies.
- **Called again while on:** it stays on. Don't re-announce it; just answer.
- **Turned off:** say once, "Concise mode off," then go back to normal replies.
- **"More detail on this":** expand that one reply; the mode stays on.
- **Long sessions:** if the history or a summary shows it on, it stays on. Don't ask or re-announce.
- Never carry it into a new chat, and never save it as a standing preference unless the user asks (when they ask to make it persistent for a project, save that in the project's preferences / memory).
- Applies to chat replies only, not to files, code, commits or documents being written.

## Reply shape (every reply while on)
One reply per turn, sent only once the information is in hand: never several replies in a row. Use these four bold headers, in this order, each a short bulleted list; leave out a section that has nothing:

- **Done**: what finished. Group related items into one bullet with a bold lead label (e.g. `- **Route B finished:** B3 shared settings (PR #82), B4 cross-board links (PR #84)`). PR numbers in parentheses after the item they belong to. Last bullet: one repo-tidiness line when it applies (e.g. `- Clean: main d0717f4, no open PRs / branches / worktrees`).
- **Found**: facts or problems discovered that matter to a decision, one line each. Flag a real risk with ⚠️.
- **Next**: what Claude will do next, one line each, or one bullet with the items joined by " · ".
- **❓ Open**: every unanswered question (earlier ones too), at the very end. One line each, in this exact shape:
  `- **<ID> <few-word title>** (<one short context clause, only if needed>): a) <option> **(rec)** · b) <option> · c) <option>`
  Options on the same line, separated by " · "; **(rec)** right after the recommended option, plus a 2-4 word reason in the bracket only when it helps decide.

No intro, no TL;DR line, no closing summary, no status footer beyond these sections (this replaces any end-of-turn checklist or emoji footer the user's other preferences ask for, while concise mode is on). Aim for 15 bullets or fewer in the whole reply. A short answer to a direct question can skip the headers.

Example:

**Done**
- **Route B finished:** B3 shared settings (PR #82), B4 cross-board links (PR #84); 168 tests pass
- Clean: main d0717f4, no open PRs / branches / worktrees

**Next**
- DBC PDM-wide names · bus-load check · preliminary ECU-control plan

**❓ Open**
- **w3 Default current limits** (20 A now on 19 outputs): a) each output's rating **(rec)** · b) leave 20 A
- **p1 Move button:** a) keep under Advanced **(rec)** · b) remove

## How to write
- Plain, simple words, at about an 8th-grade reading level. Explain things the way you would to a smart non-expert.
- Assume the user has no background in coding, servers or other technical topics unless they or the context show otherwise.
- Short, scannable summaries, mostly bullets with bold labels.
- No filler, no wordiness, and no repeating what a recent reply already said.
- One screen max: the user should never have to scroll.
- Keep jargon to a minimum. Give long technical explanations only when the user asks for more detail.
