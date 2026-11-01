#Requires -Version 5.1
# Stop and start all Claude remotes: for every project folder in active\ whose per-project Claude remote
# (session rc-<folder>, started by 'Start Claude remote - <folder>') is running, stop it with rc-close.ps1,
# then start a fresh one with rc-open.ps1. Folders whose remote is not running are left alone, and nothing
# else is touched (the projects-root session from Phone access is not a per-project remote).
# Click only: the shortcut and the dashboard button run it; no scheduled or sign-in task.
# Use it after a Claude Code update so the remotes run the new version.
param([string]$ActiveDir, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'workstation-common.ps1')
. (Join-Path $PSScriptRoot 'rc-lib.ps1')

if (-not $ActiveDir) { $ActiveDir = (Get-RcDefaults -ScriptRoot $PSScriptRoot).ActiveDir }
Write-Title 'Stop and start all Claude remotes'

$sessions = @()
$agentsOk = $false
if ($ClaudeExe) {
    try {
        $json = (& $ClaudeExe agents --json 2>$null) | Out-String
        if ($LASTEXITCODE -eq 0) { $sessions = @(ConvertFrom-RcAgentsJson $json); $agentsOk = $true }
        else { Write-Warn "could not read 'claude agents --json' (exit $LASTEXITCODE); checking running processes only" }
    } catch { Write-Warn "could not read 'claude agents --json': $($_.Exception.Message)" }
}
$procs = @(Get-ProcSnapshot)

$running = @()
foreach ($p in @(Get-RcProjectFolders $ActiveDir)) {
    $name = Get-RcSessionName $p.Name
    $hit = @(Select-RcProcs $procs $name).Count + @(Select-RcSessions $sessions $p.FullName $name).Count
    if ($hit) { $running += $p }
}
if (-not $running) {
    Write-Off 'no per-project Claude remotes are running; nothing to do'
    Wait-BridgeClose -NoPause:$NoPause
    exit 0
}
Write-Info ("running: " + (($running | ForEach-Object { $_.Name }) -join ', '))

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$close = Join-Path $PSScriptRoot 'rc-close.ps1'
$open = Join-Path $PSScriptRoot 'rc-open.ps1'
$failed = @()
foreach ($p in $running) {
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $close -Repo $p.FullName -NoPause
    if ($LASTEXITCODE -ne 0) { Write-Bad "$($p.Name): stop failed (exit $LASTEXITCODE); not starting it again"; $failed += $p.Name; continue }
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $open -Repo $p.FullName -NoPause
    if ($LASTEXITCODE -ne 0) { Write-Bad "$($p.Name): start failed (exit $LASTEXITCODE)"; $failed += $p.Name }
}
Write-Host ''
if ($failed) { Write-Bad ("done with problems: " + ($failed -join ', ')) }
else { Write-Ok "stopped and started $($running.Count) Claude remote(s)" }
Wait-BridgeClose -NoPause:$NoPause
if ($failed) { exit 1 }
exit 0