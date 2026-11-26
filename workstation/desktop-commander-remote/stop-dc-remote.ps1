#Requires -Version 5.1
# Manual Stop. Stops every Desktop Commander remote copy. Does not add a sign-in item.
param([switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'dc-remote-lib.ps1')
$dir = Join-Path $env:LOCALAPPDATA 'Workstation\desktop-commander-remote'
if (-not $env:WORKSTATION_FAKE_PROCS) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$log = Join-Path $dir 'start-dc-remote.log'

function Write-Log([string]$msg) {
    if ($env:WORKSTATION_FAKE_PROCS) { return }
    Add-Content -Path $log -Value ("{0} stop: {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'), $msg) -Encoding UTF8
}

Write-Host ''
Write-Host '==== Stop Desktop Commander ====' -ForegroundColor Cyan
$rows = @(Get-DcRemoteRows)
if (-not $rows.Count) {
    Write-Host '  not running' -ForegroundColor DarkGray
    Write-Log 'not running'
} else {
    foreach ($r in $rows) {
        $stopped = Stop-TrackedPid (Get-DcStopPid $r)
        if ($env:WORKSTATION_FAKE_PROCS) { Write-Host "  would stop pid $($r.Pid)"; continue }
        if ($stopped -or -not (Get-Process -Id $r.Pid -ErrorAction SilentlyContinue)) {
            Write-Host "  stopped pid $($r.Pid)" -ForegroundColor Green
            Write-Log "stopped pid $($r.Pid)"
        } else {
            Write-Host "  could not stop pid $($r.Pid)" -ForegroundColor Red
            Write-Log "FAILED pid $($r.Pid)"
        }
    }
}
Write-Host ''
if (-not $NoPause) {
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
