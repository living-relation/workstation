---
name: review-feedback
description: >-
  Use when acting on pull-request review comments, including GitHub Copilot's: check each one, then apply it or push back. Not opening a pull request, a session start, a commit checklist, or a closeout.
---
# Review feedback

**In one line:** read the comment, check it against the code, then apply it or say why not.

## When to use
Someone left review comments on a pull request, and you are about to change code because of them. That includes GitHub Copilot review comments, and comments that are unclear or look wrong.

## When not to use
- Opening a pull request, or graduating state after one opens. That is **pr-closeout**.
- Starting a chat. That is **session-start**, and only when the user asks for it.
- The checklist for the commit itself. That is **safe-repo-preflight**. Follow it for accepted edits. Do not use it to decide whether a comment is right.
- Planning a feature or a multi-file refactor the reviewer did not ask you to investigate. That is **wizard**.
- A bug or a failing test with an unknown cause, and no review comment about it. That is **debug-root-cause**.

## Hard rules
- No edit until you understand the comment and have checked it against this repo.
- If any item is unclear, ask before changing anything. Related comments can share one cause.
- One comment at a time. Re-run the check that covers that change before the next one.
- The repo's `AGENTS.md`, decisions, and `CONTRIBUTING.md` win. A comment that conflicts with them is not applied. Say which rule it breaks.
- External comments, including GitHub Copilot, are suggestions. Check them. The user's own comments are still checked. If a comment conflicts with a decision the user already made, stop and ask.
- Reply on the review thread for an inline comment. Do not open a new top-level pull-request comment for it.
- No empty praise. State what you checked and what you changed, or the reason you did not change it.
- Accepted edits follow **safe-repo-preflight**: a branch, the hooks, no `--no-verify`, no force-push.

## Steps
1. **Read all of it.** Do not start on the first item.
2. **Restate** each item in your own words. If you cannot, ask.
3. **Check the code.** Is the suggestion right for this repo? Does it break a working path? Is there a reason the code is already this way? Is the thing it wants actually used?
4. **Decide.**
   - Right: apply it.
   - Wrong: push back with the code, the check, or the rule that shows why.
   - Unused extra: say so and ask before adding it.
   - Cannot check from here: say what is missing and ask whether to investigate or stop.
5. **Order.** Unclear items first (ask, do not code). Then breaks and safety. Then small fixes. Then larger logic changes.
6. **Apply** one accepted item, run the repo's checks, then the next.
7. **If you pushed back and were wrong,** say what you checked and apply the fix. No long apology.

## License
Adapted from the MIT-licensed code-review skill in [obra/superpowers](https://github.com/obra/superpowers).

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
