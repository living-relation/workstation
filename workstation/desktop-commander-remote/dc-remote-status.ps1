#Requires -Version 5.1
# DC remote status. Read-only. One copy per PC serves every chat and project.
param([switch]$NoPause)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'dc-remote-lib.ps1')

function Wait-Close([switch]$NoPause) {
    if ($NoPause) { return }
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}

Write-Host ''
Write-Host '==== DC remote status ====' -ForegroundColor Cyan
Write-Host 'one copy serves all chats'
Write-Host ''

$rows = @(Get-DcRemoteRows)
if (-not $rows.Count) {
    Write-Host '  no remote copy is running' -ForegroundColor DarkGray
    Write-Host '  Start Desktop Commander starts one if you need it. It does not start at sign-in.'
    Wait-Close -NoPause:$NoPause
    exit 0
}

if ($rows.Count -eq 1) {
    Write-Host '  OK one copy' -ForegroundColor Green
}
foreach ($r in $rows) {
    $started = if ($r.StartTime -and $r.StartTime.Year -gt 2000) { $r.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'unknown' }
    $parent = if ($r.ParentAlive) { 'parent alive' } else { 'parent gone' }
    $console = if ($r.ConsoleAlive) { 'console alive' } else { 'console gone' }
    $color = if ($r.Verdict -eq 'online') { 'Green' } else { 'Yellow' }
    Write-Host ("  pid {0}  started {1}  {2}  {3}  {4}" -f $r.Pid, $started, $parent, $console, $r.Verdict) -ForegroundColor $color
}

Write-Host ''
Write-Host 'one copy serves all chats'
Wait-Close -NoPause:$NoPause
exit 0
