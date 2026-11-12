#Requires -Version 5.1
# Start a Claude Code remote-control session for one project folder.
# No prompt: the session stays up until rc-close.ps1 stops it.
# --bg assigns the session id itself and ignores --session-id, so this session is named rc-<folder>.
# Success means the named session is listed by `claude agents --json`, not merely that
# `claude --bg` printed "backgrounded". A cold start otherwise loses the session when
# Claude updates claude.exe and the background service restarts for that upgrade.
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
Write-Title "Start Claude remote - $leaf"

if (-not $repoPath -or -not (Test-Path -LiteralPath $repoPath -PathType Container)) {
    Write-Bad "project folder not found: $Repo"
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}

$procs = @(Select-RcProcs (Get-ProcSnapshot) $name)
$agents = @()
if ($ClaudeExe) {
    try {
        $json = (& $ClaudeExe agents --json 2>$null) | Out-String
        if ($LASTEXITCODE -eq 0) { $agents = @(Select-RcSessions (ConvertFrom-RcAgentsJson $json) $repoPath $name) }
        else { Write-Warn "could not read 'claude agents --json' (exit $LASTEXITCODE); checked running processes only" }
    } catch { Write-Warn "could not read 'claude agents --json': $($_.Exception.Message)" }
}
if ($procs -or $agents) {
    $bits = @()
    if ($procs) { $bits += "pid $(Format-Pids $procs)" }
    if ($agents) { $bits += 'session ' + ((@($agents) | ForEach-Object { Get-RcStopId $_ } | Where-Object { $_ }) -join ', ') }
    Write-Ok "already running ($name; $($bits -join '; '))"
    Wait-BridgeClose -NoPause:$NoPause
    exit 0
}
if (-not $ClaudeExe) {
    Write-Bad 'Claude Code CLI (claude.exe) not found on PATH or in the usual install folders'
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}

try {
    $launch = Invoke-RcRemoteLaunch -InvokeCli (New-RcClaudeInvoker -ClaudeExe $ClaudeExe -RepoPath $repoPath) `
        -RepoPath $repoPath -SessionName $name -GetBinaryStamp { Get-RcBinaryStamp $ClaudeExe }
} catch {
    Write-Bad "could not start Claude remote control: $($_.Exception.Message)"
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}
foreach ($line in @($launch.Log)) { if ($line) { Write-Info $line } }
foreach ($line in ("$($launch.Output)" -split "`r?`n")) { if ($line.Trim()) { Write-Info $line.Trim() } }
if (-not $launch.Ok) {
    Write-Bad "$($launch.Detail)"
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}
if ($launch.Starts -eq 0) {
    Write-Ok "already running ($name)"
} elseif ($launch.SessionId) {
    Write-Ok "started Claude remote control in $repoPath (name $name, session $($launch.SessionId))"
} else {
    Write-Ok "started Claude remote control in $repoPath (name $name)"
}
Wait-BridgeClose -NoPause:$NoPause
exit 0
