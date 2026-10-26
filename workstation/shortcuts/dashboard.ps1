#Requires -Version 5.1
# Opens the local project dashboard, always on the latest code:
#   1. pulls this workstation clone fast-forward only (skipped with a warning when the clone is not on main,
#      has local changes, or cannot fast-forward; never overwrites anything),
#   2. stops the running dashboard server (only python running dashboard\server.py on port 8791),
#   3. starts it again and opens the page (start-dashboard.ps1).
# Does not start or stop the workers.
$ErrorActionPreference = 'Continue'
$pkg = Split-Path -Parent $PSScriptRoot
$start = Join-Path $pkg 'dashboard\start-dashboard.ps1'
$port = 8791

$repo = (& git -C $pkg rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -eq 0 -and $repo) {
    $branch = (& git -C $repo rev-parse --abbrev-ref HEAD 2>$null)
    $dirty = (& git -C $repo status --porcelain --untracked-files=no 2>$null)
    if ($branch -ne 'main') { Write-Host "[WARN] workstation clone is on '$branch', not main: not pulled." -ForegroundColor Yellow }
    elseif ($dirty) { Write-Host '[WARN] workstation clone has local changes: not pulled.' -ForegroundColor Yellow }
    else {
        $before = (& git -C $repo rev-parse --short HEAD)
        & git -C $repo pull --ff-only --quiet 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { Write-Host '[WARN] pull --ff-only failed; starting the code already here.' -ForegroundColor Yellow }
        else {
            $after = (& git -C $repo rev-parse --short HEAD)
            if ($before -ne $after) { Write-Host "Updated $before -> $after" } else { Write-Host "Already up to date ($after)" }
        }
    }
} else { Write-Host '[WARN] not a git clone: not pulled.' -ForegroundColor Yellow }

if (-not (Test-Path -LiteralPath $start)) {
    Write-Host "Dashboard start script is not in this checkout: $start"
    exit 1
}

# Restart: stop only a python process that runs dashboard\server.py and listens on the dashboard port.
foreach ($c in @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$c.OwningProcess)" -ErrorAction SilentlyContinue
    if ($p -and $p.Name -match '^python' -and $p.CommandLine -match 'server\.py') {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped the old dashboard server (pid $($p.ProcessId))."
    } elseif ($p) { Write-Host "[WARN] port $port is used by $($p.Name) (pid $($p.ProcessId)), not the dashboard: left alone." -ForegroundColor Yellow }
}
$deadline = (Get-Date).AddSeconds(10)
while ((Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }

& $start
exit $LASTEXITCODE
