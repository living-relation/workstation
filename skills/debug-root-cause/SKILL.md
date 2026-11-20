---
name: debug-root-cause
description: >-
  Use when a bug or failing test has an unknown cause: reproduce it, trace the cause, then fix that cause. Not a session start, feature plan, commit checklist, or pull-request closeout.
---
# Debug root cause

**In one line:** find why it fails, then fix that cause. No guesses.

## When to use
A bug, a failing test, a build failure, or behavior you did not expect, and you do not yet know the cause. That includes a failure under time pressure, a quick fix that already failed, and a bug that looks small.

## When not to use
- Starting a chat or reading project state. That is **session-start**, and only when the user asks for it.
- Planning a feature or a multi-file refactor. That is **wizard**.
- The checklist before a commit or push. That is **safe-repo-preflight**. Follow it when this skill changes a repo. Do not run it instead of finding the cause.
- After a pull request opens, or when the user says close out. That is **pr-closeout**.
- A deliverable that passed before, and `VERIFIED.lock` or a check now says it is broken. That is **regression-restore**: stop and restore. Do not invent a new fix.

## Hard rules
- No fix until the cause is known. A change that only hides the symptom is a failed investigation.
- One hypothesis at a time, tested with the smallest change. Do not stack fixes.
- If three fixes fail, stop and ask the user whether the design is wrong. Do not try a fourth fix on your own.
- Repo edits follow **safe-repo-preflight**: the repo's `AGENTS.md`, decisions, `CONTRIBUTING.md`, hooks, and CI; a branch and a pull request; no `--no-verify`; no force-push.
- Say when you do not understand something. Do not pretend a guess is a cause.

## Steps
1. **Read the failure.** The full message, stack, file, and line. Do not skip warnings.
2. **Reproduce.** Exact steps. If it is not reliable, gather more evidence. Do not guess.
3. **Recent changes.** `git log` and `git diff` for what just changed: code, config, dependencies, environment.
4. **Where it breaks.** At each boundary, record what goes in and what comes out. Trace a bad value back to the line that first produced it. Fix that source.
5. **Compare with working code.** Find a similar path that works. List every difference. Read the working path fully before copying a pattern.
6. **One hypothesis.** Write "The cause is X because Y." Test it with the smallest change. If it fails, drop it and form a new one. Do not add another change on top.
7. **Fix the cause.** Add the smallest failing check that proves the cause, then the one change that makes it pass. No drive-by refactor. Run the repo's checks (**safe-repo-preflight**, its check step) before calling it fixed. If the check stays red, return to step 1. After three failed fixes, stop and ask the user.
8. **Report** the cause, the evidence, and the change. If the failure is environmental or depends on timing, say what you ruled out and what handling you added.

## Stop and go back to step 1
- "Quick fix now, investigate later."
- Changing several things, then running tests.
- Skipping the failing check.
- "It is probably X."
- Listing fixes before tracing the failure.
- "One more try" after two failures.

## License
Adapted from the MIT-licensed debugging skill in [obra/superpowers](https://github.com/obra/superpowers).

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
