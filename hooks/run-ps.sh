#!/bin/sh
# Portable launcher for the PowerShell hooks: sh run-ps.sh <script.ps1> [args...]
# Runs the script with powershell, else pwsh (stdin, stdout and the exit code pass through, so exit 2
# still blocks). With neither on PATH (Linux containers, WSL) it exits 0 with no output: these
# Windows guards do not apply there, and the host must not report a broken hook.
# Claude Code runs hook commands with sh -c on Linux and macOS and with Git Bash on Windows.
script="$1"
[ -n "$script" ] || exit 0
shift
for shell_name in powershell pwsh; do
  if command -v "$shell_name" >/dev/null 2>&1; then
    exec "$shell_name" -NoProfile -ExecutionPolicy Bypass -File "$script" "$@"
  fi
done
exit 0
