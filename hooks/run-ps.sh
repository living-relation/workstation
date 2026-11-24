#!/bin/sh
# Portable launcher for the PowerShell hooks: sh run-ps.sh <script.ps1> [args...]
# Runs the script with powershell, else pwsh (stdin, stdout and the exit code pass through, so exit 2
# still blocks). With neither on PATH (Linux containers, WSL) it exits 0 and prints a loud fail:
# systemMessage plus additionalContext. The agent is told to open its reply with
# "WORKSTATION RULES NOT LOADED: <reason>". That phrase matches Write-RulesNotLoaded in state-common.ps1.
# hookEventName is copied from the hook payload's hook_event_name, or SessionStart when it is absent.
# Claude Code runs hook commands with sh -c on Linux and macOS and with Git Bash on Windows.
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
event=''
case $input in
  *hook_event_name*)
    rest=${input#*hook_event_name}
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
        event=${rest%%\"*}
        ;;
    esac
    ;;
esac
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
reason='PowerShell is not on PATH (powershell and pwsh both missing)'
line="WORKSTATION RULES NOT LOADED: $reason"
tell="Open your reply with this exact line: $line"
printf '%s\n' "{\"systemMessage\":\"$line\",\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":\"$tell\"}}"
exit 0
