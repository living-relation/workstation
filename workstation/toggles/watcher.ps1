#Requires -Version 5.1
# Watcher On / Off / Status (manual only, off by default; no scheduled task, nothing starts it at sign-in).
#   on     : starts watcher.py --loop 15 hidden (pythonw). Checks the toggles that are on and the processes
#            every 15 minutes and shows a toast on problems. Runs until Watcher Off or sign-out.
#   off    : stops it. Also removes the old scheduled task Workstation-Watcher if an older install left it
#            (that part needs an admin window; otherwise it prints the command).
#   status : prints on or off.
param([ValidateSet('on', 'off', 'status')][string]$Action = 'status', [int]$Minutes = 15, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'python.ps1')
$state = Join-Path $env:LOCALAPPDATA 'Workstation\dashboard'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$pidFile = Join-Path $state 'watcher.pid'
$script = Join-Path $PSScriptRoot 'watcher.py'

function Get-WatcherProcs {
    @(Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'watcher\.py' -and $_.CommandLine -match '--loop' })
}
function Done([int]$code) {
    if (-not $NoPause) { Write-Host 'Closing in 5 s.' -ForegroundColor DarkGray; Start-Sleep -Seconds 5 }
    exit $code
}

$running = Get-WatcherProcs
switch ($Action) {
    'status' {
        if ($running.Count) { Write-Host "Watcher is ON (pid $($running.ProcessId -join ', '))" } else { Write-Host 'Watcher is OFF' }
        Done 0
    }
    'on' {
        if ($running.Count) { Write-Host "Watcher already ON (pid $($running.ProcessId -join ', '))" -ForegroundColor Green; Done 0 }
        $pyw = Find-Python313 -Windowless
        if (-not $pyw) { Write-Host '[FAIL] Python 3.13 was not found; Watcher not started.' -ForegroundColor Red; Done 1 }
        $p = Start-Process -FilePath $pyw -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru `
            -ArgumentList @("`"$script`"", '--loop', "$Minutes")
        Set-Content -LiteralPath $pidFile -Value $p.Id -Encoding ascii
        Write-Host "Watcher ON (every $Minutes min, pid $($p.Id)). Use Watcher Off to stop it." -ForegroundColor Green
        Done 0
    }
    'off' {
        foreach ($r in $running) { Stop-Process -Id $r.ProcessId -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        if ($running.Count) { Write-Host 'Watcher OFF (stopped).' -ForegroundColor Green } else { Write-Host 'Watcher was already OFF.' }
        if (Get-ScheduledTask -TaskName 'Workstation-Watcher' -ErrorAction SilentlyContinue) {
            try {
                Unregister-ScheduledTask -TaskName 'Workstation-Watcher' -Confirm:$false -ErrorAction Stop
                Write-Host 'Removed the old scheduled task Workstation-Watcher.' -ForegroundColor Green
            } catch {
                Write-Host "[WARN] The old task Workstation-Watcher is still there (needs admin). In an admin PowerShell: Unregister-ScheduledTask -TaskName 'Workstation-Watcher' -Confirm:`$false" -ForegroundColor Yellow
            }
        }
        Done 0
    }
}
