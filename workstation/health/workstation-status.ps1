#Requires -Version 5.1
# Health check (read-only): memory, hooks, skills, app locks, the phone remote,
# and the manual Cursor worker. A worker that is not running is normal.
# -NoPause never prompts. -Locks runs only the app-lock check.
# Exit 1 if any app-lock item fails.
param([switch]$NoPause, [switch]$Locks)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

if ($Locks) {
    Write-Title 'App locks'
    $lockFails = Show-AppLocks
    if ($lockFails) { exit 1 }
    exit 0
}

Write-Title 'Health check'
Show-MemoryAndHooks
Show-Skills
Show-DcRemote
Show-DcAutostart
Show-CursorWorker
Show-Orphans
Write-Host ''
$lockFails = Show-AppLocks
Wait-BridgeClose -NoPause:$NoPause
if ($lockFails) { exit 1 }
exit 0
