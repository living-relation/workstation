#Requires -Version 5.1
# Health check: one line per bridge piece, project branches, automations (read-only),
# app locks (Fusion and harness.design), then git status of every active\ project.
# Interactive runs (no -NoPause) offer to turn switched-off startup apps back on, asking per app;
# -NoPause never prompts or changes anything.
# -Locks runs only the app-lock check (read-only). PASS/FAIL per item. Exit 1 if any FAIL.
param([switch]$NoPause, [switch]$Locks)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

if ($Locks) {
    Write-Title 'App locks'
    $lockFails = Show-AppLocks
    if ($lockFails) { exit 1 }
    exit 0
}

Write-Title 'Health check'
Show-BridgeStatus
Show-BranchStatus
Show-Automations
Write-Host ''
$lockFails = Show-AppLocks
if (-not $NoPause) { Invoke-StartupFixOffer }
Write-Host ''
& (Join-Path $BridgeRoot 'repo-status.ps1')
Wait-BridgeClose -NoPause:$NoPause
if ($lockFails) { exit 1 }
