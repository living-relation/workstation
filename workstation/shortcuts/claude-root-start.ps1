#Requires -Version 5.1
# Projects-root Claude remote control (part of the Phone access toggle): start `claude --bg --remote-control`
# in the projects root if it is not running. Starts nothing else (Cursor's own Remote Control covers Cursor).
# Same settle-then-check start as rc-open.ps1: a pending Claude update is applied, and the background
# service is up, before the session is created. --bg ignores --session-id, so the saved id is the one
# the CLI reports after the session is actually listed.
param([switch]$NoPause)
. (Join-Path $PSScriptRoot 'workstation-common.ps1')

Write-Title 'Start Claude remote - projects root'

$rootFailed = $false
$procs = Get-ProcSnapshot

# Claude remote control for the projects root. A per-project session is named rc-<folder>
# and must not count as this one.
$rc  = @(Select-RcProcs $procs 'workstation-remote-control')
$rcs = @(Select-ProjectsRootRcSessions (Get-RemoteControlSessions $procs) (Get-RemoteControlStateId))
if ($rc -or $rcs) {
    Write-Ok 'Claude remote control already running'
} elseif (-not $ClaudeExe) {
    Write-Bad 'Claude Code CLI (claude.exe) not found on PATH or in the usual install folders'
} else {
    try {
        $launch = Invoke-RcRemoteLaunch -InvokeCli (New-RcClaudeInvoker -ClaudeExe $ClaudeExe -RepoPath $BridgeProjects) `
            -RepoPath $BridgeProjects -SessionName 'workstation-remote-control' -GetBinaryStamp { Get-RcBinaryStamp $ClaudeExe }
    } catch {
        $launch = @{ Ok = $false; Detail = $_.Exception.Message; Log = @(); Output = ''; Starts = 0; SessionId = ''; FullId = '' }
    }
    foreach ($line in @($launch.Log)) { if ($line) { Write-Info $line } }
    foreach ($line in ("$($launch.Output)" -split "`r?`n")) { if ($line.Trim()) { Write-Info $line.Trim() } }
    if ($launch.Ok) {
        $sid = "$($launch.FullId)".Trim()
        if (-not $sid) { $sid = "$($launch.SessionId)".Trim() }
        if ($launch.Starts -eq 0) { Write-Ok 'Claude remote control already running' }
        elseif ($sid) { Write-Ok "started Claude remote control (name workstation-remote-control, session $sid)" }
        else { Write-Ok 'started Claude remote control (name workstation-remote-control)' }
        if ($sid -and $launch.Starts -gt 0) {
            try {
                New-Item -ItemType Directory -Path (Split-Path $RemoteControlStateFile) -Force | Out-Null
                [IO.File]::WriteAllText($RemoteControlStateFile, (@{ sessionId = $sid; startedAt = (Get-Date).ToString('o') } | ConvertTo-Json))
            } catch { Write-Warn "couldn't save $RemoteControlStateFile`: $($_.Exception.Message)" }
        }
    } else {
        Write-Bad "could not start Claude remote control: $($launch.Detail)"
        $rootFailed = $true
    }
}

Write-Host ''
Write-Host 'Waiting 8 s for things to come up...' -ForegroundColor DarkGray
Start-Sleep -Seconds 8
Write-Title 'Status'
Show-BridgeStatus
Wait-BridgeClose -NoPause:$NoPause
if ($rootFailed) { exit 1 }
