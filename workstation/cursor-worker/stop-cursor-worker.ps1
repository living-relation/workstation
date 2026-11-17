#Requires -Version 5.1
# Manual Stop. Lists Cursor workers this tool started and stops the one you pick, or all.
# Does not stop the Cursor app, a worker you started by hand, or Claude.
# No scheduled task, no Startup item, no Run key.
param([string]$Pick, [switch]$All, [switch]$WhatIf, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'cursor-worker-lib.ps1')

function Write-Ok([string]$m)  { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Off([string]$m) { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Write-Bad([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Wait-Close {
    if ($NoPause) { return }
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}

function Test-StillOurWorker([int]$ProcId) {
    $p = @(Get-CwProcesses | Where-Object { [int]$_.ProcessId -eq $ProcId }) | Select-Object -First 1
    if (-not $p) { return $false }
    $cmd = "$($p.CommandLine)"
    if ($cmd) { return (Test-OurWorkerCommand $cmd) }
    return (Test-WorkerHostName "$($p.Name)")
}

function Stop-CwPid([int]$ProcId) {
    if ($env:WORKSTATION_FAKE_PROCS) { return $true }
    if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
        & taskkill.exe /T /F /PID $ProcId *> $null
        Start-Sleep -Milliseconds 300
    } else {
        try { Stop-Process -Id $ProcId -Force -ErrorAction Stop } catch { return $false }
    }
    return -not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue)
}

function Remove-WorkerNote($Row) {
    if (-not $Row.DataDir) { return }
    $data = [string]$Row.DataDir
    $prefix = Join-Path (Get-CursorWorkerRoot) 'instances'
    if (-not $data.TrimEnd('\', '/').ToLowerInvariant().StartsWith($prefix.TrimEnd('\', '/').ToLowerInvariant())) { return }
    $json = Join-Path $data 'worker.json'
    if (Test-Path -LiteralPath $json) { Remove-Item -LiteralPath $json -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host '==== Stop Cursor worker ====' -ForegroundColor Cyan
$rows = @(Get-CursorWorkerRows)
if ($rows.Count -eq 0) {
    Write-Off 'No Cursor workers from this tool are running.'
    Wait-Close
    exit 0
}

$chosen = @()
if ($All -or $Pick -eq 'a') { $chosen = @($rows) }
elseif ($Pick) {
    $n = 0
    if (-not [int]::TryParse($Pick.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $rows.Count) {
        Write-Bad 'Not a number on the list.'
        Wait-Close
        exit 1
    }
    $chosen = @($rows[$n - 1])
} else {
    Write-Host 'Workers this tool started:'
    $i = 1
    foreach ($r in @($rows)) {
        $nm = $r.DisplayName; if (-not $nm) { $nm = 'worker' }
        $folder = $r.Folder; if (-not $folder) { $folder = '(folder not recorded)' }
        Write-Host ('  {0}. {1}  pid {2}  {3}' -f $i, $nm, $r.Pid, $folder)
        $i++
    }
    Write-Host '  a. all'
    Write-Host '  q. quit'
    $ans = ''
    try { $ans = Read-Host 'Number, a, or q' } catch { $ans = '' }
    if (-not $ans -or $ans -eq 'q') { Write-Off 'quit'; Wait-Close; exit 0 }
    if ($ans -eq 'a') {
        $yes = ''
        try { $yes = Read-Host "Stop all $($rows.Count)? y or n" } catch { $yes = '' }
        if ($yes -ne 'y') { Write-Off 'left them running'; Wait-Close; exit 0 }
        $chosen = @($rows)
    } else {
        $n = 0
        if (-not [int]::TryParse($ans.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $rows.Count) {
            Write-Bad 'Not a number on the list.'
            Wait-Close
            exit 1
        }
        $chosen = @($rows[$n - 1])
    }
}

$failed = 0
foreach ($r in @($chosen)) {
    $nm = $r.DisplayName; if (-not $nm) { $nm = 'worker' }
    if (-not (Test-StillOurWorker $r.Pid)) {
        Write-Off "pid $($r.Pid) is not our worker anymore. Left it alone."
        continue
    }
    if ($WhatIf) {
        Write-Host "WOULD|stop pid $($r.Pid) $nm $($r.Folder)"
        continue
    }
    if (Stop-CwPid $r.Pid) {
        Remove-WorkerNote $r
        Write-Ok "stopped $nm (pid $($r.Pid))"
    } else {
        Write-Bad "could not stop pid $($r.Pid)"
        $failed++
    }
}
Wait-Close
if ($failed) { exit 1 }
exit 0
