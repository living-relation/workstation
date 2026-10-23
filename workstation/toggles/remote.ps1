#Requires -Version 5.1
# Remote toggle: Desktop Commander Remote + Claude remote control + the Cursor workers, as one switch.
# start/stop reuse the same scripts as the manual shortcuts (start-dc-remote.ps1, stop-dc-remote.ps1,
# workers-start.ps1, workers-stop.ps1). status exits 0 when any part runs; health exits 0 only when all run.
param([ValidateSet('start', 'stop', 'status', 'health')][string]$Action = 'status')
$ErrorActionPreference = 'Continue'
$toolkit = Split-Path -Parent $PSScriptRoot
$dcDir = Join-Path $toolkit 'desktop-commander-remote'
$scDir = Join-Path $toolkit 'shortcuts'

switch ($Action) {
    'start' {
        & (Join-Path $dcDir 'start-dc-remote.ps1')
        & (Join-Path $scDir 'workers-start.ps1') -NoPause
        exit 0
    }
    'stop' {
        & (Join-Path $scDir 'workers-stop.ps1') -NoPause
        & (Join-Path $dcDir 'stop-dc-remote.ps1') -NoPause
        exit 0
    }
}

. (Join-Path $scDir 'workstation-common.ps1')
$procs = Get-ProcSnapshot
$dc = @(Get-DesktopCommanderRemoteProcs $procs)
$sup = @(Get-SupervisorProcs $procs)
$rc = @(Get-RemoteControlProcs $procs)
$parts = [ordered]@{
    'Desktop Commander Remote' = [bool]$dc
    'Cursor worker supervisor' = [bool]$sup
    'Claude remote control'    = [bool]$rc
}
if ($Action -eq 'status') {
    $on = @($parts.Keys | Where-Object { $parts[$_] })
    if ($on) { Write-Output "on: $($on -join ', ')"; exit 0 }
    Write-Output 'off'
    exit 1
}

$bad = 0
foreach ($k in $parts.Keys) {
    if ($parts[$k]) { Write-Output "OK   $k running" } else { Write-Output "FAIL $k not running"; $bad++ }
}
$worker = Test-WorkerHealth
if ($worker -match '^HTTP 200') { Write-Output "OK   Cursor worker health $worker" } else { Write-Output "FAIL Cursor worker health $worker"; $bad++ }
$dcCopies = @($dc | Where-Object { $_.Name -eq 'node.exe' -and "$($_.CommandLine)" -notmatch 'npx-cli' }).Count
if ($dcCopies -gt 1) { Write-Output "FAIL Desktop Commander Remote has $dcCopies copies running (expected 1)"; $bad++ }
$log = Join-Path $env:LOCALAPPDATA 'Workstation\desktop-commander-remote\remote.out.log'
if ($dc -and (Test-Path -LiteralPath $log)) {
    $tail = (Get-Content -LiteralPath $log -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
    if ($tail -match 'Status: Offline|Disconnected') { Write-Output 'WARN Desktop Commander Remote log says offline' }
}
if ($bad) { exit 1 }
exit 0
