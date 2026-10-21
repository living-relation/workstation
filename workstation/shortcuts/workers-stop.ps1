#Requires -Version 5.1
# Workers Stop: write the stop flag, then stop watch-pull, the Cursor worker supervisor + agent worker,
# and Claude remote control. Only positively matched processes are stopped; Grok Bot, the Cursor app
# and other Claude sessions are never touched.
param([switch]$NoPause)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

Write-Title 'Workers Stop'

Set-Content -LiteralPath $BridgeStopFlag -Value "stopped $(Get-Date -Format o) by workers-stop.ps1" -Encoding ASCII
Write-Ok "stop flag written ($BridgeStopFlag)"

# taskkill /T /F with its output and exit code logged when it fails. Returns $true when the process is gone.
function Invoke-TreeKill([int]$ProcId, [string]$what) {
    $out = (& taskkill.exe /T /F /PID $ProcId 2>&1) | Out-String
    $code = $LASTEXITCODE
    Start-Sleep -Milliseconds 400
    if ($code -ne 0) { Write-Warn "taskkill /T /F /PID $ProcId ($what) exit $code`: $($out.Trim())" }
    -not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue)
}

function Stop-Matched($procs, [string]$what) {
    foreach ($p in @($procs)) {
        if ($null -eq $p) { continue }
        if (-not (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue)) { continue }
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            Write-Ok "stopped $what (pid $($p.ProcessId) $($p.Name))"
        } catch { Write-Bad "could not stop $what pid $($p.ProcessId): $($_.Exception.Message)" }
    }
}

$procs = Get-ProcSnapshot

# 1. watch-pull: the powershell loop first, then its wscript launcher
$wp = Get-WatchPullProcs $procs
if ($wp) {
    Stop-Matched (@($wp | Where-Object { $_.Name -ne 'wscript.exe' })) 'watch-pull'
    Stop-Matched (@($wp | Where-Object { $_.Name -eq 'wscript.exe' })) 'watch-pull launcher'
} else { Write-Off 'watch-pull was not running' }

# 2. Cursor worker: supervisor tree (same taskkill /T /F the health check uses), then leftovers
$sup = Get-SupervisorProcs $procs
$supIds = @($sup | ForEach-Object { $_.ProcessId })
$agents = Get-AgentWorkerProcs $procs $supIds
$launchers = Get-SupervisorLaunchers $procs
if ($sup -or $agents -or $launchers) {
    foreach ($s in $sup) {
        if (-not (Invoke-TreeKill $s.ProcessId 'Cursor worker supervisor')) {
            Stop-Matched @($s) 'Cursor worker supervisor'
        } else { Write-Ok "stopped Cursor worker supervisor and its child processes (pid $($s.ProcessId))" }
    }
    Stop-Matched $agents 'agent worker'
    Stop-Matched $launchers 'supervisor launcher (wscript)'
} else { Write-Off 'Cursor worker was not running' }

# 3. Claude remote control: named sessions, then their processes. The `claude.exe daemon run` is shared with every
#    other `claude --bg` session, so it is stopped only when nothing but remote control was using it (the session
#    list was read, no other active session and no other PTY host remain); otherwise it is left running.
$all = @(Get-ClaudeBgSessions)
$rcs = @(Get-RemoteControlSessions (Get-ProcSnapshot) $all)
$rcIds = @($rcs | ForEach-Object { "$($_.id)" })
foreach ($s in $rcs) {
    $out = (& $ClaudeExe stop $s.id 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { Write-Ok "stopped Claude remote-control session $($s.id)" }
    else {
        Write-Warn "claude stop $($s.id) failed (exit $LASTEXITCODE): $($out.Trim()); tree-killing it"
        if ($s.pid) { if (Invoke-TreeKill ([int]$s.pid) "remote-control session $($s.id)") { Write-Ok "stopped remote-control session $($s.id) (pid $($s.pid))" } }
    }
}
# Leftover --remote-control processes / PTY hosts (a host may still be exiting: short retry).
$rc = @()
for ($try = 0; $try -lt 3; $try++) {
    $rc = @(Get-RemoteControlProcs (Get-ProcSnapshot))
    if (-not $rc) { break }
    if ($try -lt 2) { Start-Sleep -Milliseconds 700 } else { Stop-Matched $rc 'Claude remote control' }
}
$after = Get-ProcSnapshot
$daemons = @($after | Where-Object { $_.Name -eq 'claude.exe' -and "$($_.CommandLine)" -match '\bdaemon run\b' })
if ($daemons -and ($rcs -or $rc)) {
    $others = @($all | Where-Object { $rcIds -notcontains "$($_.id)" })   # every session except the one(s) we stopped
    $rcLeft = @(Get-RemoteControlProcs $after | ForEach-Object { $_.ProcessId })
    $otherHosts = @($after | Where-Object { "$($_.CommandLine)" -match '--bg-pty-host' -and $rcLeft -notcontains $_.ProcessId })
    $kept = $true
    if (-not $script:ClaudeAgentsOk) { Write-Warn "left the Claude daemon running (pid $(Format-Pids $daemons)): couldn't read 'claude agents --json' to check it is unused" }
    elseif ($others -or $otherHosts) { Write-Ok "left the shared Claude daemon running (pid $(Format-Pids $daemons)): $($others.Count) other session(s), $($otherHosts.Count) other PTY host(s) use it" }
    else {
        $kept = $false
        foreach ($d in $daemons) {
            if (Invoke-TreeKill $d.ProcessId 'Claude daemon') { Write-Ok "stopped the Claude daemon, only remote control used it (pid $($d.ProcessId))" }
            else { Stop-Matched @($d) 'Claude daemon' }
        }
    }
    if ($kept) {
        Start-Sleep -Seconds 3
        $back = @(Get-RemoteControlProcs (Get-ProcSnapshot))
        if ($back) { Write-Warn "Claude remote control respawned by the shared daemon (pid $(Format-Pids $back)); stop it from Claude or stop the daemon by hand" }
    }
}
if (-not (Get-RemoteControlProcs (Get-ProcSnapshot))) { Remove-Item -LiteralPath $RemoteControlStateFile -ErrorAction SilentlyContinue }
if (-not $rcs -and -not $rc) { Write-Off 'Claude remote control was not running' }

Write-Host ''
Start-Sleep -Seconds 2
Write-Title 'Status'
Show-BridgeStatus
Wait-BridgeClose -NoPause:$NoPause
