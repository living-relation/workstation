#Requires -Version 5.1
# Projects-root Claude remote control (part of the Phone access toggle): stop only the `claude --bg --remote-control`
# session(s) it matches. Only positively matched processes are stopped; the Cursor app, Cursor's own Remote Control,
# the per-project 'Start Claude remote - <folder>' sessions and every other Claude session are never touched.
param([switch]$NoPause)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

Write-Title 'Stop Claude remote - projects root'


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

# Only the projects-root session: named workstation-remote-control, or the session id Start saved. Per-project
# 'rc-<folder>' remotes also run with --remote-control, so the generic remote-control matchers are NOT used here.
$savedId = Get-RemoteControlStateId
function Get-RootRcProcs($procs) {
    $named = @(Select-RcProcs $procs 'workstation-remote-control')
    $byId = @()
    if ($savedId) { $byId = @($procs | Where-Object { $_.Name -in @('claude.exe', 'node.exe') -and "$($_.CommandLine)".Contains($savedId) }) }
    @(@($named) + @($byId) | Where-Object { $_ -and $_.ProcessId -ne $PID } | Sort-Object ProcessId -Unique)
}

# Sessions first, then leftover processes. The `claude.exe daemon run` is shared with every other `claude --bg`
# session, so it is stopped only when nothing else uses it (the session list was read, no other active session and
# no other PTY host remain); otherwise it is left running.
$all = @(Get-ClaudeBgSessions)
$rcs = @(Select-ProjectsRootRcSessions $all $savedId)
$rcIds = @($rcs | ForEach-Object { "$($_.id)" })
foreach ($s in $rcs) {
    $out = (& $ClaudeExe stop $s.id 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { Write-Ok "stopped Claude remote-control session $($s.id) (projects root)" }
    else {
        Write-Warn "claude stop $($s.id) failed (exit $LASTEXITCODE): $($out.Trim()); tree-killing it"
        if ($s.pid) { if (Invoke-TreeKill ([int]$s.pid) "remote-control session $($s.id)") { Write-Ok "stopped remote-control session $($s.id) (pid $($s.pid))" } }
    }
}
# Leftover projects-root --remote-control processes / PTY hosts (a host may still be exiting: short retry).
$rc = @()
for ($try = 0; $try -lt 3; $try++) {
    $rc = @(Get-RootRcProcs (Get-ProcSnapshot))
    if (-not $rc) { break }
    if ($try -lt 2) { Start-Sleep -Milliseconds 700 } else { Stop-Matched $rc 'Claude remote control (projects root)' }
}
$after = Get-ProcSnapshot
$daemons = @($after | Where-Object { $_.Name -eq 'claude.exe' -and "$($_.CommandLine)" -match '\bdaemon run\b' })
if ($daemons -and ($rcs -or $rc)) {
    $others = @($all | Where-Object { $rcIds -notcontains "$($_.id)" })   # every session except the one(s) we stopped
    $rootLeft = @(Get-RootRcProcs $after | ForEach-Object { $_.ProcessId })
    $otherHosts = @($after | Where-Object { "$($_.CommandLine)" -match '--bg-pty-host' -and $rootLeft -notcontains $_.ProcessId })
    if (-not $script:ClaudeAgentsOk) { Write-Warn "left the Claude daemon running (pid $(Format-Pids $daemons)): couldn't read 'claude agents --json' to check it is unused" }
    elseif ($others -or $otherHosts) { Write-Ok "left the shared Claude daemon running (pid $(Format-Pids $daemons)): $($others.Count) other session(s), $($otherHosts.Count) other PTY host(s) use it" }
    else {
        foreach ($d in $daemons) {
            if (Invoke-TreeKill $d.ProcessId 'Claude daemon') { Write-Ok "stopped the Claude daemon, only the projects-root remote used it (pid $($d.ProcessId))" }
            else { Stop-Matched @($d) 'Claude daemon' }
        }
    }
}
if (-not (Get-RootRcProcs (Get-ProcSnapshot))) { Remove-Item -LiteralPath $RemoteControlStateFile -ErrorAction SilentlyContinue }
if (-not $rcs -and -not $rc) { Write-Off 'Claude remote control (projects root) was not running' }

Write-Host ''
Start-Sleep -Seconds 2
Write-Title 'Status'
Show-BridgeStatus
Wait-BridgeClose -NoPause:$NoPause
