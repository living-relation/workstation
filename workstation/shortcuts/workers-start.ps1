#Requires -Version 5.1
# Workers Start: clear the stop flag, start the Cursor worker supervisor (hidden) and Claude
# remote control if they are not running. Never starts watch-pull.
param([switch]$NoPause)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

Write-Title 'Workers Start'

if (Test-Path -LiteralPath $BridgeStopFlag) {
    Remove-Item -LiteralPath $BridgeStopFlag -Force
    Write-Ok 'stop flag removed'
} else { Write-Off 'no stop flag to remove' }

$procs = Get-ProcSnapshot

# 1. Cursor worker supervisor (mutex Local\CursorWorkerSupervisor also prevents a second copy)
$sup = Get-SupervisorProcs $procs
if ($sup) {
    Write-Ok "Cursor worker supervisor already running (pid $(Format-Pids $sup))"
} else {
    if (-not (Test-Path -LiteralPath $AgentPs1)) { Write-Warn "Cursor CLI not found at $AgentPs1 - the worker will fail to start (install Cursor CLI and run 'agent login')" }
    $vbs = Join-Path $BridgeWorkerDir 'run-hidden.vbs'
    $rw  = Join-Path $BridgeWorkerDir 'run-worker.ps1'
    try {
        Start-Process -FilePath 'wscript.exe' -WorkingDirectory $BridgeWorkerDir -ErrorAction Stop `
            -ArgumentList @('//B', '//Nologo', "`"$vbs`"", "`"$rw`"")
        Write-Ok 'started Cursor worker supervisor (hidden, via cursor-worker\run-hidden.vbs)'
    } catch { Write-Bad "could not start supervisor: $($_.Exception.Message)" }
}

# 2. Claude remote control for the projects root. A per-project session is named rc-<folder>
# and must not count as this one.
$rc  = @(Select-RcProcs $procs 'workstation-remote-control')
$rcs = @(Select-ProjectsRootRcSessions (Get-RemoteControlSessions $procs) (Get-RemoteControlStateId))
if ($rc -or $rcs) {
    Write-Ok 'Claude remote control already running'
} elseif (-not $ClaudeExe) {
    Write-Bad 'Claude Code CLI (claude.exe) not found on PATH or in the usual install folders'
} else {
    $outFile = Join-Path $env:TEMP 'workers-start-claude.out.txt'
    $errFile = Join-Path $env:TEMP 'workers-start-claude.err.txt'
    try {
        # A fixed session id and a name, saved to the state file, so Stop finds exactly this session.
        $sid = [guid]::NewGuid().ToString()
        $p = Start-Process -FilePath $ClaudeExe -ArgumentList @('--bg', '--remote-control', '--session-id', $sid, '--name', 'workstation-remote-control') `
            -WorkingDirectory $BridgeProjects -WindowStyle Hidden -PassThru -ErrorAction Stop `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if ($p.WaitForExit(30000)) {
            Write-Ok "started Claude remote control (claude --bg --remote-control, session $sid, exit $($p.ExitCode))"
            try {
                New-Item -ItemType Directory -Path (Split-Path $RemoteControlStateFile) -Force | Out-Null
                [IO.File]::WriteAllText($RemoteControlStateFile, (@{ sessionId = $sid; startedAt = (Get-Date).ToString('o') } | ConvertTo-Json))
            } catch { Write-Warn "couldn't save $RemoteControlStateFile`: $($_.Exception.Message)" }
        } else {
            Write-Warn 'claude --bg --remote-control still running after 30 s (left running)'
        }
        foreach ($f in @($outFile, $errFile)) {
            if (Test-Path $f) { Get-Content $f | Where-Object { $_.Trim() } | ForEach-Object { Write-Info $_ } }
        }
    } catch { Write-Bad "could not start Claude remote control: $($_.Exception.Message)" }
}

Write-Host ''
Write-Host 'Waiting 8 s for things to come up...' -ForegroundColor DarkGray
Start-Sleep -Seconds 8
Write-Title 'Status'
Show-BridgeStatus
Wait-BridgeClose -NoPause:$NoPause
