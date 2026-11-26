#Requires -Version 5.1
# Manual tool. Lists leftover processes and asks once per item before stopping any.
# -WhatIf lists only. -Force stops the listed items without asking.
# Stopping uses taskkill /T on that process's own tree.
# Does not start anything. Log: %LOCALAPPDATA%\Workstation\kill-orphans.log
param([switch]$WhatIf, [switch]$Force, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'health\orphans.ps1')

$logDir = Join-Path $env:LOCALAPPDATA 'Workstation'
$log = Join-Path $logDir 'kill-orphans.log'
function Write-KillLog([string]$Msg) {
    if ($env:WORKSTATION_FAKE_PROCS) { return }
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) -Encoding UTF8
}

Write-Host ''
Write-Host '==== Kill orphaned remote processes ====' -ForegroundColor Cyan
$cands = @(Get-OrphanCandidates)
if (-not $cands.Count) {
    Write-Host '  nothing to stop' -ForegroundColor DarkGray
    if (-not $NoPause) {
        Write-Host ''
        Write-Host 'Press any key to close...' -ForegroundColor DarkGray
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
    }
    exit 0
}

foreach ($c in $cands) {
    Write-Host ("  pid {0}  {1}  {2}" -f $c.Pid, $c.Name, $c.Why)
    if ($WhatIf) {
        Write-Host '    WOULD stop' -ForegroundColor Cyan
        Write-KillLog ("would pid $($c.Pid) $($c.Why)")
        continue
    }
    if (-not $Force) {
        $ans = Read-Host "    Stop pid $($c.Pid)? [y/N]"
        if ($ans -notmatch '^(y|yes)$') {
            Write-Host '    left running' -ForegroundColor DarkGray
            Write-KillLog ("left pid $($c.Pid)")
            continue
        }
    }
    $ok = Stop-TrackedPid ([int]$c.Pid)
    if ($env:WORKSTATION_FAKE_PROCS) { Write-Host '    not stopped (fake process list)'; continue }
    if ($ok -or -not (Get-Process -Id $c.Pid -ErrorAction SilentlyContinue)) {
        Write-Host '    stopped' -ForegroundColor Green
        Write-KillLog ("killed pid $($c.Pid) $($c.CommandLine)")
    } else {
        Write-Host '    could not stop' -ForegroundColor Red
        Write-KillLog ("FAILED pid $($c.Pid)")
    }
}
if (-not $NoPause -and -not $WhatIf) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
exit 0
