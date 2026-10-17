# Supervisor: keeps `agent worker start` running. Restarts it whenever it exits.
# Only one supervisor can run at a time (named mutex).
. "$PSScriptRoot\config.ps1"

$mutex = New-Object System.Threading.Mutex($false, 'Local\CursorWorkerSupervisor')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) {
    Write-Log 'supervisor already running; exiting'
    exit 0
}

Set-Content -Path $PidFile -Value $PID
Write-Log "supervisor started (pid $PID)"

try {
    $delay = 5
    while ($true) {
        & "$PSScriptRoot\repair-sqlite.ps1"

        $started = Get-Date
        $dirs = Get-WorkerDirs
        Set-Content -Path $DirsSigFile -Value (Get-DirsSignature)
        $workerArgs = @('worker')
        foreach ($d in $dirs) { $workerArgs += @('--worker-dir', $d) }
        $workerArgs += @('--management-addr', $MgmtAddr, '--name', $WorkerName, 'start')
        Write-Log "starting worker '$WorkerName' with $($dirs.Count) dirs: $($dirs -join '; ')"
        & $AgentPs1 @workerArgs 2>&1 |
            ForEach-Object { "$_" } |
            Out-File -FilePath $WorkerLog -Append -Encoding utf8
        $code = $LASTEXITCODE
        $secs = [int]((Get-Date) - $started).TotalSeconds
        Write-Log "worker exited (code $code) after $secs s"

        if ((Test-Path $WorkerLog) -and ((Get-Item $WorkerLog).Length -gt 5MB)) {
            Move-Item $WorkerLog "$WorkerLog.old" -Force
        }

        if ($secs -gt 120) { $delay = 5 } else { $delay = [Math]::Min($delay * 2, 120) }
        Write-Log "restarting in $delay s"
        Start-Sleep -Seconds $delay
    }
} finally {
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex()
}
