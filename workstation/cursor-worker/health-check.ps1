# Health checker: run every 30 minutes by a scheduled task.
# - Supervisor not running      -> start it.
# - Worker health URL failing   -> after 2 failed checks in a row, restart everything.
. "$PSScriptRoot\config.ps1"

# Bridge Stop (desktop shortcut) writes _workstation\shortcuts\.bridge-stopped. While it exists, do nothing:
# no revive, no restart. Bridge Start removes the flag.
$BridgeStopFlag = Join-Path (Split-Path -Parent $PSScriptRoot) 'shortcuts\.bridge-stopped'
if (Test-Path -LiteralPath $BridgeStopFlag) {
    Write-Log 'bridge stop flag present -> skipping health check' $HealthLog
    exit 0
}

function Log([string]$m) { Write-Log $m $HealthLog }

function Test-Health {
    try {
        $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

$sup = Get-SupervisorProcess
if (-not $sup) {
    $how = Start-Supervisor
    Log "supervisor was not running -> started it ($how)"
    Remove-Item $FailFile -ErrorAction SilentlyContinue
    exit 0
}

if (Test-Health) {
    if (Test-Path $FailFile) { Log 'healthy again'; Remove-Item $FailFile -ErrorAction SilentlyContinue }

    # New/changed projects: restart the worker so it registers them, but never mid-session.
    $old = if (Test-Path $DirsSigFile) { (Get-Content $DirsSigFile -Raw).Trim() } else { '' }
    if ($old -ne (Get-DirsSignature)) {
        if ((Get-SessionActive) -eq 0) {
            Log 'project list changed and worker is idle -> restarting to register projects'
            & taskkill.exe /T /F /PID $sup.Id *> $null
            Start-Sleep -Seconds 3
            $how = Start-Supervisor
            Log "restarted ($how)"
        } else {
            Log 'project list changed but a session is active (or unknown); will retry next check'
        }
    }
    exit 0
}

# Give a freshly started supervisor a few minutes to connect before judging it.
$ageMin = ((Get-Date) - $sup.StartTime).TotalMinutes
if ($ageMin -lt 3) {
    Log ('health check failed but supervisor is only {0:N1} min old; waiting' -f $ageMin)
    exit 0
}

$fails = 1
if (Test-Path $FailFile) { $fails = [int](Get-Content $FailFile | Select-Object -First 1) + 1 }
Set-Content -Path $FailFile -Value $fails
Log "health check failed ($fails in a row)"

if ($fails -ge 2) {
    Log "restarting supervisor (pid $($sup.Id)) and worker"
    & taskkill.exe /T /F /PID $sup.Id *> $null
    Start-Sleep -Seconds 3
    $how = Start-Supervisor
    Log "restarted ($how)"
    Remove-Item $FailFile -ErrorAction SilentlyContinue
}
