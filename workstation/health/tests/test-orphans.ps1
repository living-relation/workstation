# Leftover-process classification for Health check and kill-orphans.ps1. No real processes are touched.
# Usage: pwsh -NoProfile -File workstation/health/tests/test-orphans.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'orphans.ps1')
$fail = 0
function Check([string]$What, $Got, $Want) { if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
function P($Id, $Parent, $Name, $Cmd) { [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; Name = $Name; CommandLine = $Cmd } }
$term = P 1 0 'claude' 'claude'
$cursor = P 13 0 'Cursor' 'Cursor --remote-control'
$fusion = P 14 0 'Fusion360' 'Fusion360'
$web = P 15 1 'python' 'python workstation/dashboard/server.py'
$watch = P 16 1 'python' 'python workstation/toggles/watcher.py'
$rcDead = P 17 99 'claude' 'claude --bg --remote-control'
$rcLive = P 18 1 'claude' 'claude --remote-control'
$node = P 19 1 'node' 'node some-mcp-server remote'

Check 'nothing to list in a clean set' @(Get-OrphanCandidates @($term, $rcLive, $node)).Count 0
$warn = @(Get-HealthOrphanWarnings @($term, $cursor, $fusion, $web, $watch, $rcDead, $rcLive, $node))
Check 'web, watcher and dead session are listed' $warn.Count 3
Check 'old web server kind' @($warn | Where-Object { $_.Pid -eq 15 }).Kind 'old-web-server'
Check 'old watcher kind' @($warn | Where-Object { $_.Pid -eq 16 }).Kind 'old-watcher'
Check 'dead remote-control session kind' @($warn | Where-Object { $_.Pid -eq 17 }).Kind 'claude-remote'
Check 'live remote-control session stays' @($warn | Where-Object { $_.Pid -eq 18 }).Count 0
Check 'Cursor and Fusion are never listed' @($warn | Where-Object { $_.Pid -eq 13 -or $_.Pid -eq 14 }).Count 0
Check 'other processes are not listed' @($warn | Where-Object { $_.Pid -eq 19 }).Count 0
$env:WORKSTATION_FAKE_PROCS = 'none'
Check 'fake empty process list' @(Get-TrackedProcesses).Count 0
Check 'Stop-TrackedPid never stops with a fake list' (Stop-TrackedPid 15) False
Remove-Item Env:WORKSTATION_FAKE_PROCS

if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
