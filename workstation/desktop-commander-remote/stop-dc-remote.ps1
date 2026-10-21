#Requires -Version 5.1
# Stop Desktop Commander remote. Does not remove the Startup shortcut.
param([switch]$NoPause)
$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:LOCALAPPDATA 'Workstation\desktop-commander-remote'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$log = Join-Path $dir 'start-dc-remote.log'

function Write-Log([string]$msg) {
    Add-Content -Path $log -Value ("{0} stop: {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'), $msg) -Encoding UTF8
}

Write-Host ''
Write-Host '==== Desktop Commander Remote Stop ====' -ForegroundColor Cyan

$matches = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and
    $_.CommandLine -match 'desktop-commander' -and
    $_.CommandLine -match '\bremote\b' -and
    $_.CommandLine -notmatch 'stop-dc-remote' -and
    $_.CommandLine -notmatch 'start-dc-remote'
})

if (-not $matches) {
    Write-Host '  not running' -ForegroundColor DarkGray
    Write-Log 'not running'
} else {
    foreach ($p in $matches) {
        $null = & taskkill.exe /T /F /PID $p.ProcessId 2>&1
        if (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                Write-Host "  stopped pid $($p.ProcessId) $($p.Name)" -ForegroundColor Green
                Write-Log "stopped pid $($p.ProcessId)"
            } catch {
                Write-Host "  could not stop pid $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "FAILED pid $($p.ProcessId): $($_.Exception.Message)"
            }
        } else {
            Write-Host "  stopped pid $($p.ProcessId) $($p.Name)" -ForegroundColor Green
            Write-Log "stopped pid $($p.ProcessId)"
        }
    }
}

Write-Host ''
if (-not $NoPause) {
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
