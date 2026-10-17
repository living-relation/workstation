#Requires -Version 5.1
# Workstation Status: one line per bridge piece, project branches, automations (read-only),
# then git status of every active\ project. Interactive runs (no -NoPause) offer to turn
# switched-off startup apps back on, asking per app; -NoPause never prompts or changes anything.
param([switch]$NoPause)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

Write-Title 'Workstation Status'
Show-BridgeStatus
Show-BranchStatus
Show-Automations
if (-not $NoPause) { Invoke-StartupFixOffer }
Write-Host ''
& (Join-Path $BridgeRoot 'repo-status.ps1')
Wait-BridgeClose -NoPause:$NoPause
