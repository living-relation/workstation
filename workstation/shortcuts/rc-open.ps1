#Requires -Version 5.1
# Start a Claude Code remote-control session for one project folder.
# No prompt: the session stays up until rc-close.ps1 stops it.
# --bg assigns the session id itself and ignores --session-id, so this session is named rc-<folder>.
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
Write-Title "RC $leaf"

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

$safe = ($name -replace '[^\w.-]', '-')
$outFile = Join-Path $env:TEMP "rc-open-$safe.out.txt"
$errFile = Join-Path $env:TEMP "rc-open-$safe.err.txt"
try {
    $p = Start-Process -FilePath $ClaudeExe -ArgumentList @('--bg', '--remote-control', '--name', $name) `
        -WorkingDirectory $repoPath -WindowStyle Hidden -PassThru -ErrorAction Stop `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $exited = $p.WaitForExit(30000)
    $outText = ''
    $errText = ''
    if (Test-Path -LiteralPath $outFile) { $outText = [IO.File]::ReadAllText($outFile) }
    if (Test-Path -LiteralPath $errFile) { $errText = [IO.File]::ReadAllText($errFile) }
    foreach ($line in (($outText + "`n" + $errText) -split "`r?`n")) {
        if ($line.Trim()) { Write-Info $line }
    }
    if (-not $exited) {
        Write-Warn "claude --bg --remote-control still running after 30 s (left running, name $name)"
    } elseif ($p.ExitCode -ne 0) {
        Write-Bad "claude exited $($p.ExitCode) before the session stayed up (name $name)"
        Wait-BridgeClose -NoPause:$NoPause
        exit 1
    } else {
        $id = Get-RcBackgroundId $outText
        if ($id) { Write-Ok "started Claude remote control in $repoPath (name $name, session $id)" }
        else { Write-Ok "started Claude remote control in $repoPath (name $name)" }
    }
} catch {
    Write-Bad "could not start Claude remote control: $($_.Exception.Message)"
    Wait-BridgeClose -NoPause:$NoPause
    exit 1
}
Wait-BridgeClose -NoPause:$NoPause
exit 0
