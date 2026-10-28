#Requires -Version 5.1
# Stop the Claude remote-control session for one project folder.
# The session id changes every launch (--bg ignores --session-id), so this finds the session
# by its folder and the name rc-<folder>, then falls back to that process command line.
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [switch]$NoPause
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'workstation-common.ps1')
. (Join-Path $PSScriptRoot 'rc-lib.ps1')

$repoPath = Normalize-RcPath $Repo
$leaf = Split-Path $repoPath -Leaf
$name = Get-RcSessionName $leaf
Write-Title "Close RC $leaf"

if (-not $repoPath -or -not (Test-Path -LiteralPath $repoPath -PathType Container)) {
    Write-Bad "project folder not found: $Repo"
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}

$stopped = 0
if ($ClaudeExe) {
    try {
        $json = (& $ClaudeExe agents --json 2>$null) | Out-String
        if ($LASTEXITCODE -eq 0) {
            foreach ($s in @(Select-RcSessions (ConvertFrom-RcAgentsJson $json) $repoPath $name)) {
                $id = Get-RcStopId $s
                if (-not $id) { continue }
                $out = (& $ClaudeExe stop $id 2>&1) | Out-String
                if ($LASTEXITCODE -eq 0) { Write-Ok "stopped Claude remote-control session $id ($name)"; $stopped++ }
                else { Write-Warn "claude stop $id failed (exit $LASTEXITCODE): $($out.Trim())" }
            }
        } else { Write-Warn "could not read 'claude agents --json' (exit $LASTEXITCODE); closing by process name" }
    } catch { Write-Warn "could not read 'claude agents --json': $($_.Exception.Message)" }
} else { Write-Warn 'Claude Code CLI not found; closing by process name only' }

if ($stopped) { Start-Sleep -Milliseconds 700 }
$left = @(Select-RcProcs (Get-ProcSnapshot) $name)
foreach ($root in @(Get-RcKillRoots $left)) {
    $out = (& taskkill.exe /T /F /PID $root.ProcessId 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { Write-Ok "stopped $name process tree (pid $($root.ProcessId))" }
    else { Write-Warn "taskkill /T /F /PID $($root.ProcessId) ($name) exit $LASTEXITCODE`: $($out.Trim())" }
}
if ($left) { Start-Sleep -Milliseconds 400 }
$still = @(Select-RcProcs (Get-ProcSnapshot) $name)
if ($still) {
    Write-Bad "$name still running (pid $(Format-Pids $still))"
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}
if (-not $stopped -and -not $left) { Write-Off "$name was not running" }
else { Write-Ok "$name is stopped" }
Wait-BridgeClose -NoPause:$NoPause
exit 0
