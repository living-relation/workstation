# Classification tests for the phone remote. No real processes are touched.
# Usage: pwsh -NoProfile -File workstation/desktop-commander-remote/tests/test-dc-remote.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'dc-remote-lib.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'health\orphans.ps1')
$fail = 0
function Check([string]$What, $Got, $Want) { if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
function P($Id, $Parent, $Name, $Cmd, $Start, $Console) {
    [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; Name = $Name; CommandLine = $Cmd; CreationDate = $Start; HasConsole = $Console }
}
$term = P 1 0 'claude' 'claude' '2026-01-01T00:00:00Z' $true
$healthy = P 10 1 'node' 'node npx desktop-commander remote' '2026-01-02T00:00:00Z' $true
$older = P 9 1 'node' 'node desktop-commander remote' '2026-01-01T01:00:00Z' $true
$stale = P 11 99 'node' 'node desktop-commander remote' '2026-01-03T00:00:00Z' $false
$mcp = P 12 1 'node' 'node desktop-commander' '2026-01-01T00:00:00Z' $true
$cursor = P 13 0 'Cursor' 'Cursor' '2026-01-01T00:00:00Z' $true
$fusion = P 14 0 'Fusion360' 'Fusion360' '2026-01-01T00:00:00Z' $true
$web = P 15 1 'python' 'python workstation/dashboard/server.py' '2026-01-01T00:00:00Z' $true
$watch = P 16 1 'python' 'python workstation/toggles/watcher.py' '2026-01-01T00:00:00Z' $true
$rcDead = P 17 99 'claude' 'claude --bg --remote-control' '2026-01-01T00:00:00Z' $false
$rcLive = P 18 1 'claude' 'claude --remote-control' '2026-01-01T00:00:00Z' $true

$one = @($term, $healthy, $mcp, $cursor, $fusion, $rcLive)
$rows = @(Get-DcRemoteRows $one)
Check 'mcp is not a remote' @($rows | Where-Object { $_.Pid -eq 12 }).Count 0
Check 'one healthy is online' @($rows | Where-Object { $_.Verdict -eq 'online' }).Count 1
Check 'stop list empty when one healthy' @(Get-DcRemoteStopList $rows).Count 0
Check 'health warns none' @(Get-HealthOrphanWarnings $one).Count 0

$two = @($term, $older, $healthy)
$rows2 = @(Get-DcRemoteRows $two)
Check 'newest healthy kept' (Get-DcRemoteKeep $rows2).Pid 10
Check 'older is duplicate' @($rows2 | Where-Object { $_.Pid -eq 9 }).Verdict 'duplicate'
Check 'one extra to stop' @(Get-DcRemoteStopList $rows2).Count 1
Check 'health warns on the extra only' @(Get-HealthOrphanWarnings $two).Count 1

$dead = @($stale)
$rows3 = @(Get-DcRemoteRows $dead)
Check 'stale verdict' $rows3[0].Verdict 'stale'
Check 'stale is on the stop list' @(Get-DcRemoteStopList $rows3).Count 1
Check 'single copy is not a health warning' @(Get-HealthOrphanWarnings $dead).Count 0

$mixed = @($term, $healthy, $web, $watch, $rcDead, $rcLive, $mcp)
$warn = @(Get-HealthOrphanWarnings $mixed)
Check 'web and watcher and dead session' $warn.Count 3
Check 'live remote-control session stays' @($warn | Where-Object { $_.Pid -eq 18 }).Count 0
Check 'cursor not listed' @($warn | Where-Object { $_.Name -eq 'Cursor' }).Count 0

if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
