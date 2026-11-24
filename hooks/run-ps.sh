#!/bin/sh
# Portable launcher for the PowerShell hooks: sh run-ps.sh <script.ps1> [args...]
# Runs the script with powershell, else pwsh (stdin, stdout and the exit code pass through, so exit 2
# still blocks). Claude Code runs hook commands with sh -c on Linux and macOS and with Git Bash on Windows.
#
# With neither on PATH (Linux cloud sessions, containers, WSL) it always exits 0:
# - Any event other than SessionStart or SubagentStart (Stop, PreToolUse, PostToolUse, ...): no output.
#   Output on Stop would be fed back to the agent after every reply and loop the session.
# - SessionStart or SubagentStart, for rules-inject, state-inject or subagent-rules: hooks/rules_fallback.py
#   runs with python3 (else python) and prints the same rules or state text as the PowerShell hook.
#   Other scripts (agents-md-only-warn): no output.
# - If Python is missing or the fallback fails: a loud fail at most once per session and event.
#   It prints systemMessage plus additionalContext telling the agent to open its reply with
#   "WORKSTATION RULES NOT LOADED: <reason>" (the phrase in Write-RulesNotLoaded, state-common.ps1).
#   The marker is a file ${TMPDIR:-/tmp}/workstation-rules-warned-<session_id>-<event>, created with
#   noclobber so parallel hooks print it once. With no session_id in the payload it prints every time.
# hook_event_name and session_id come from the hook payload; the event is SessionStart when absent.
script="$1"
[ -n "$script" ] || exit 0
shift
for shell_name in powershell pwsh; do
  if command -v "$shell_name" >/dev/null 2>&1; then
    exec "$shell_name" -NoProfile -ExecutionPolicy Bypass -File "$script" "$@"
  fi
done
# builtins only: the no-PowerShell test (and some containers) have a PATH with no cat, sed, or head
input=''
while IFS= read -r line || [ -n "$line" ]; do
  if [ -n "$input" ]; then
    input="$input $line"
  else
    input=$line
  fi
done
# json_field <name>: sets $value to the payload's "<name>": "<value>" string, or empty
json_field() {
  value=''
  case $input in
    *"\"$1\""*)
      rest=${input#*\"$1\"}
      rest=${rest#*:}
      while :; do
        case $rest in
          ' '*) rest=${rest# } ;;
          *) break ;;
        esac
      done
      case $rest in
        \"*)
          rest=${rest#\"}
          value=${rest%%\"*}
          ;;
      esac
      ;;
  esac
}
json_field hook_event_name
event=$value
case $event in
  *[!A-Za-z0-9]*) event='' ;;
esac
case $event in
  [A-Za-z]*) ;;
  *) event='' ;;
esac
if [ -z "$event" ]; then
  event=SessionStart
fi
case $event in
  SessionStart|SubagentStart) ;;
  *) exit 0 ;;
esac
name=${script##*/}
name=${name##*\\}
name=${name%.ps1}
case $name in
  rules-inject|state-inject|subagent-rules) ;;
  *) exit 0 ;;
esac
here=${0%/*}
[ "$here" = "$0" ] && here=.
reason='PowerShell is not on PATH (powershell and pwsh both missing) and Python is missing'
for py_name in python3 python; do
  if command -v "$py_name" >/dev/null 2>&1; then
    if printf '%s\n' "$input" | "$py_name" "$here/rules_fallback.py" "$name"; then
      exit 0
    fi
    reason='PowerShell is not on PATH (powershell and pwsh both missing) and the Python fallback failed'
    break
  fi
done
json_field session_id
session=$value
case $session in
  *[!A-Za-z0-9_-]*) session='' ;;
esac
if [ -n "$session" ]; then
  marker="${TMPDIR:-/tmp}/workstation-rules-warned-$session-$event"
  if ! (set -C; : > "$marker") 2>/dev/null; then
    exit 0
  fi
fi
line="WORKSTATION RULES NOT LOADED: $reason"
tell="Open your reply with this exact line: $line"
printf '%s\n' "{\"systemMessage\":\"$line\",\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":\"$tell\"}}"
exit 0
