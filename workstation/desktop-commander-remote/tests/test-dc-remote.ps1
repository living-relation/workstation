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

# One Windows launch is cmd -> npx node -> cmd -> node. That is one copy.
function Chain($Base, $Parent, $Start, $Console) {
    @(
        (P $Base $Parent 'cmd' 'C:\Windows\System32\cmd.exe /c npx.cmd --yes @wonderwhy-er/desktop-commander@latest remote' $Start $Console),
        (P ($Base + 1) $Base 'node' 'node C:\Program Files\nodejs\node_modules\npm\bin\npx-cli.js --yes @wonderwhy-er/desktop-commander@latest remote' $Start $Console),
        (P ($Base + 2) ($Base + 1) 'cmd' 'C:\Windows\System32\cmd.exe /d /s /c desktop-commander.cmd remote' $Start $Console),
        (P ($Base + 3) ($Base + 2) 'node' 'node C:\pkg\@wonderwhy-er\desktop-commander\dist\index.js remote' $Start $Console)
    )
}
$plugin = P 20 1 'node' 'node C:\pkg\@wonderwhy-er\desktop-commander\dist\index.js' '2026-01-01T00:00:00Z' $true
$pluginChild = P 21 20 'node' 'node C:\pkg\@wonderwhy-er\desktop-commander\dist\worker.js' '2026-01-01T00:00:00Z' $true
$chain = Chain 100 1 '2026-01-02T00:00:00Z' $true
$oneChain = @($term) + @($chain) + @($plugin, $pluginChild)
$rowsC = @(Get-DcRemoteRows $oneChain)
Check 'wrapper chain is one copy' $rowsC.Count 1
Check 'copy pid is the node remote' $rowsC[0].Pid 103
Check 'stop target is the outer cmd' $rowsC[0].StopPid 100
Check 'one chain is online' $rowsC[0].Verdict 'online'
Check 'one chain is not stopped' @(Get-DcRemoteStopList $rowsC).Count 0
Check 'one chain health is ok' @(Get-HealthOrphanWarnings $oneChain).Count 0
Check 'plugin stays unlisted' @($rowsC | Where-Object { $_.Pid -eq 20 -or $_.Pid -eq 21 }).Count 0
Check 'wrappers are not leftovers' @($(Get-OrphanCandidates $oneChain) | Where-Object { $_.Kind -eq 'dc-remote' }).Count 0

$oldChain = Chain 90 1 '2026-01-01T01:00:00Z' $true
$newChain = Chain 100 1 '2026-01-02T00:00:00Z' $true
$twoChains = @($term) + @($oldChain) + @($newChain)
$rowsT = @(Get-DcRemoteRows $twoChains)
$extra = @(Get-DcRemoteStopList $rowsT)
Check 'two chains are two copies' $rowsT.Count 2
Check 'newest chain kept' (Get-DcRemoteKeep $rowsT).Pid 103
Check 'one extra chain' $extra.Count 1
Check 'extra chain is the older remote' $extra[0].Pid 93
Check 'extra stop target is its own cmd' $extra[0].StopPid 90
Check 'health warns on the extra chain only' @(Get-HealthOrphanWarnings $twoChains).Count 1
$extraOrph = @($(Get-OrphanCandidates $twoChains) | Where-Object { $_.Kind -eq 'dc-remote' })
Check 'kill list is the extra copy' $extraOrph.Count 1
Check 'kill target is not the healthy chain' $extraOrph[0].StopPid 90

$staleChain = Chain 100 99 '2026-01-03T00:00:00Z' $false
$rowsS = @(Get-DcRemoteRows $staleChain)
Check 'stale chain is one copy' $rowsS.Count 1
Check 'stale chain verdict' $rowsS[0].Verdict 'stale'
Check 'stale chain is offered' @(Get-DcRemoteStopList $rowsS).Count 1
Check 'one stale chain is not a health warning' @(Get-HealthOrphanWarnings $staleChain).Count 0

# The launcher shell has exited. The chain is still cmd -> npx node -> cmd -> node.
# Status and health must count that as one online copy. Claude's MCP process has no remote argument.
function Q($Id, $Parent, $Name, $Cmd, $Start) {
    [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; Name = $Name; CommandLine = $Cmd; CreationDate = $Start }
}
$real = @(
    (Q 2 0 'claude.exe' 'C:\Users\dan\AppData\Local\AnthropicClaude\claude.exe' '2026-01-01T00:00:00Z'),
    (Q 3 2 'node.exe' 'C:\Program Files\nodejs\node.exe C:\Users\dan\AppData\Roaming\npm\node_modules\@wonderwhy-er\desktop-commander\dist\index.js' '2026-01-01T00:00:01Z'),
    (Q 10 50 'cmd.exe' 'C:\Windows\System32\cmd.exe /c npx.cmd --yes @wonderwhy-er/desktop-commander@latest remote' '2026-01-02T00:00:01Z'),
    (Q 11 10 'node.exe' 'C:\Program Files\nodejs\node.exe C:\Program Files\nodejs\node_modules\npm\bin\npx-cli.js --yes @wonderwhy-er/desktop-commander@latest remote' '2026-01-02T00:00:02Z'),
    (Q 12 11 'cmd.exe' 'C:\Windows\System32\cmd.exe /d /s /c desktop-commander remote' '2026-01-02T00:00:03Z'),
    (Q 13 12 'node.exe' 'C:\Program Files\nodejs\node.exe C:\Users\dan\AppData\Roaming\npm\node_modules\@wonderwhy-er\desktop-commander\dist\index.js remote' '2026-01-02T00:00:04Z')
)
$rowsR = @(Get-DcRemoteRows $real)
Check 'dead launcher chain is one copy' $rowsR.Count 1
Check 'dead launcher copy is the leaf node' $rowsR[0].Pid 13
Check 'dead launcher copy is online' $rowsR[0].Verdict 'online'
Check 'dead launcher console is alive' $rowsR[0].ConsoleAlive True
Check 'mcp without remote stays unlisted' @($rowsR | Where-Object { $_.Pid -eq 3 }).Count 0
Check 'dead launcher health is ok' @(Get-HealthOrphanWarnings $real).Count 0
Check 'dead launcher stop list empty' @(Get-DcRemoteStopList $rowsR).Count 0

$withWeb = @($term) + @($chain) + @($web)
$webWarn = @(Get-HealthOrphanWarnings $withWeb)
Check 'chain plus old server warns once' $webWarn.Count 1
Check 'that warning is the old server' $webWarn[0].Kind 'old-web-server'

if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
