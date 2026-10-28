#Requires -Version 5.1
# Tests for rc-lib.ps1. Does not call the live claude CLI and does not write the real shortcut folder.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File workstation/shortcuts/tests/test-rc-shortcuts.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\rc-lib.ps1')

$fail = 0
function Check([string]$What, $Got, $Want) {
    if ("$Got" -eq "$Want") { "PASS $What" }
    else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}

# Project folders: plain folders count. Dot-folders and files do not.
$active = Join-Path $env:TEMP ("rc-test-active-" + [guid]::NewGuid().ToString('n'))
$links = Join-Path $env:TEMP ("rc-test-links-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path (Join-Path $active 'plain-folder') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active 'has-git') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active 'has-git\.git') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active '.cursor') -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $active 'notes.txt') -Force | Out-Null
$names = @((Get-RcProjectFolders $active) | ForEach-Object { $_.Name }) -join ','
Check 'plain and git folders, dot folder skipped' $names 'has-git,plain-folder'
Check 'missing active dir is empty' (@(Get-RcProjectFolders (Join-Path $active 'nope')).Count) '0'

Check 'session name' (Get-RcSessionName 'plain-folder') 'rc-plain-folder'
Check 'session name keeps case' (Get-RcSessionName 'PowerTuneDigitalOfficial') 'rc-PowerTuneDigitalOfficial'
Check 'session name slug' (Get-RcSessionName 'my project') 'rc-my-project'
Check 'open link name' (Get-RcOpenLinkName 'my project') 'RC my project.lnk'
Check 'close link name' (Get-RcCloseLinkName 'my project') 'Close RC my project.lnk'

$scriptRoot = 'D:\box\active\workstation\workstation\shortcuts'
$defs = Get-RcDefaults -ScriptRoot $scriptRoot -ConfigPath ''
Check 'default active dir' $defs.ActiveDir 'D:\box\active'
Check 'default link dir' $defs.LinkDir 'D:\box\active\workstation\shortcuts\rc'
$cfg = Join-Path $env:TEMP ("rc-test-cfg-" + [guid]::NewGuid().ToString('n') + '.json')
$cfgRoot = Join-Path $env:TEMP ("rc-test-root-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $cfgRoot -Force | Out-Null
[IO.File]::WriteAllText($cfg, (@{ projectsRoot = $cfgRoot } | ConvertTo-Json))
$defs2 = Get-RcDefaults -ScriptRoot $scriptRoot -ConfigPath $cfg
Check 'config projects root' $defs2.ActiveDir (Join-Path $cfgRoot 'active')

$json = "notice`n" + '[{"id":"aaa111","cwd":"C:\\work\\plain-folder\\","name":"rc-plain-folder","state":"blocked","sessionId":"aaa111-full"},{"id":"bbb222","cwd":"C:\\work\\plain-folder","name":"dashboard-hand-off","state":"blocked"},{"id":"ccc333","cwd":"C:\\work\\other","name":"rc-plain-folder","state":"blocked"},{"id":"ddd444","cwd":"C:\\work\\plain-folder","name":"rc-plain-folder","state":"stopped"}]' + "`ntail"
$sessions = @(ConvertFrom-RcAgentsJson $json)
Check 'parsed session count' $sessions.Count '4'
$hit = @(Select-RcSessions $sessions 'C:\work\plain-folder' 'rc-plain-folder')
Check 'one live match' $hit.Count '1'
Check 'match id' (Get-RcStopId $hit[0]) 'aaa111'
$wrapped = '{"agents":[{"id":"eee555","cwd":"C:\\work\\plain-folder","name":"rc-plain-folder","state":"running"}]}'
$wrapHit = @(Select-RcSessions (ConvertFrom-RcAgentsJson $wrapped) 'C:\work\plain-folder' 'rc-plain-folder')
Check 'wrapped agents list' (Get-RcStopId $wrapHit[0]) 'eee555'
Check 'background id' (Get-RcBackgroundId "backgrounded * b4e02f32 * rc-plain-folder") 'b4e02f32'
Check 'no background id' (Get-RcBackgroundId 'still starting') ''

Check 'command matches name' (Test-RcProcessCommandLine 'claude.exe --bg --remote-control --name rc-plain-folder' 'rc-plain-folder') 'True'
Check 'name equals form' (Test-RcProcessCommandLine 'claude.exe --remote-control --name=rc-plain-folder' 'rc-plain-folder') 'True'
Check 'longer name does not match' (Test-RcProcessCommandLine 'claude.exe --remote-control --name rc-plain-folder-extra' 'rc-plain-folder') 'False'
Check 'other session name does not match' (Test-RcProcessCommandLine 'claude.exe --remote-control --name workstation-remote-control' 'rc-workstation') 'False'
Check 'daemon does not match' (Test-RcProcessCommandLine 'claude.exe daemon run' 'rc-plain-folder') 'False'

$hostProc = [pscustomobject]@{ Name = 'claude.exe'; ProcessId = 10; ParentProcessId = 1; CommandLine = 'claude.exe --bg-pty-host -- claude.exe --remote-control --name rc-plain-folder' }
$childProc = [pscustomobject]@{ Name = 'claude.exe'; ProcessId = 11; ParentProcessId = 10; CommandLine = 'claude.exe --remote-control --name rc-plain-folder' }
$otherProc = [pscustomobject]@{ Name = 'claude.exe'; ProcessId = 12; ParentProcessId = 1; CommandLine = 'claude.exe --remote-control --name workstation-remote-control' }
$matched = @(Select-RcProcs @($hostProc, $childProc, $otherProc) 'rc-plain-folder')
Check 'two processes for this name' $matched.Count '2'
$roots = @(Get-RcKillRoots $matched)
Check 'kill the host once' $roots.Count '1'
Check 'kill root pid' $roots[0].ProcessId '10'

# Shortcut files: a temp active folder, a stale link, and an unrelated file.
$openScript = Join-Path $PSScriptRoot '..\rc-open.ps1'
$closeScript = Join-Path $PSScriptRoot '..\rc-close.ps1'
New-Item -ItemType Directory -Path $links -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $links 'RC gone.lnk'), 'stale')
[IO.File]::WriteAllText((Join-Path $links 'Close RC gone.lnk'), 'stale')
[IO.File]::WriteAllText((Join-Path $links 'notes.txt'), 'keep')
$written = Write-RcShortcuts -ActiveDir $active -LinkDir $links -OpenScript $openScript -CloseScript $closeScript
Check 'write ok' $written.Ok 'True'
Check 'two projects' $written.Projects '2'
Check 'four links created' $written.Created '4'
Check 'two stale links removed' $written.Removed '2'
Check 'notes kept' (Test-Path -LiteralPath (Join-Path $links 'notes.txt')) 'True'
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut((Join-Path $links 'RC plain-folder.lnk'))
Check 'open link runs rc-open' ($lnk.Arguments -like '*rc-open.ps1*') 'True'
Check 'open link repo arg' ($lnk.Arguments -like ('*' + (Join-Path $active 'plain-folder') + '*')) 'True'
Check 'open link working directory' $lnk.WorkingDirectory (Join-Path $active 'plain-folder')
$closeLnk = $wsh.CreateShortcut((Join-Path $links 'Close RC has-git.lnk'))
Check 'close link runs rc-close' ($closeLnk.Arguments -like '*rc-close.ps1*') 'True'
Check 'no dot-folder link' (Test-Path -LiteralPath (Join-Path $links 'RC .cursor.lnk')) 'False'
$again = Write-RcShortcuts -ActiveDir $active -LinkDir $links -OpenScript $openScript -CloseScript $closeScript
Check 'second run updates' $again.Updated '4'
Check 'second run creates none' $again.Created '0'
Check 'second run removes none' $again.Removed '0'

Remove-Item -LiteralPath $active -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $links -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $cfgRoot -Recurse -Force -ErrorAction SilentlyContinue

$root = 'C:\rc-status-test'
Check 'repo from cwd' (Get-RcRepoLabel 'C:\rc-status-test\active\st185-link-ecu-config' 'rc-st185-link-ecu-config' $root) 'st185-link-ecu-config'
Check 'projects root from cwd' (Get-RcRepoLabel 'C:\rc-status-test' 'workstation-remote-control' $root) 'projects root'
Check 'repo from rc name' (Get-RcRepoLabel '' 'rc-handbuilt-cad' $root) 'handbuilt-cad'
Check 'workers name is projects root' (Get-RcRepoLabel '' 'workstation-remote-control' $root) 'projects root'
Check 'active-other is not under active' (Get-RcRepoLabel 'C:\rc-status-test\active-other' '' $root) 'active-other'
$sessions = @(
    [pscustomobject]@{ id='aaa11111'; sessionId='aaa11111-1111-1111-1111-111111111111'; name='rc-st185-link-ecu-config'; cwd='C:\rc-status-test\active\st185-link-ecu-config'; state='blocked' }
    [pscustomobject]@{ id='bbb22222'; sessionId='bbb22222-2222-2222-2222-222222222222'; name='workstation-remote-control'; cwd='C:\rc-status-test'; state='blocked' }
)
$hostProc = [pscustomobject]@{ ProcessId = 10; CommandLine = 'claude.exe --bg-pty-host -- claude.exe --session-id aaa11111-1111-1111-1111-111111111111 --remote-control --name rc-st185-link-ecu-config' }
$childProc = [pscustomobject]@{ ProcessId = 11; CommandLine = 'claude.exe --session-id aaa11111-1111-1111-1111-111111111111 --remote-control --name rc-st185-link-ecu-config' }
$onlyProc = [pscustomobject]@{ ProcessId = 12; CommandLine = 'claude.exe --session-id ccc33333-3333-3333-3333-333333333333 --remote-control --name rc-resume-genie' }
$rows = @(Get-RcStatusRows $sessions @($hostProc, $childProc, $onlyProc) $root)
Check 'one row per session' $rows.Count '3'
Check 'labels by repo' ((@($rows) | ForEach-Object { $_.Label }) -join ',') 'projects root,resume-genie,st185-link-ecu-config'
$st = @($rows | Where-Object { $_.Label -eq 'st185-link-ecu-config' })[0]
Check 'st185 line names the session' ($st.Detail -like '*rc-st185-link-ecu-config*session aaa11111*blocked*') 'True'

Check 'empty JSON array is zero sessions' (@(ConvertFrom-RcAgentsJson '[]').Count) '0'
$bad = 'no throw'
try { [void](ConvertFrom-RcAgentsJson 'agents listed: none'); $bad = 'no throw' } catch { $bad = 'threw' }
Check 'non-JSON text throws' $bad 'threw'
$broken = 'no throw'
try { [void](ConvertFrom-RcAgentsJson '{not json'); $broken = 'no throw' } catch { $broken = 'threw' }
Check 'broken JSON throws' $broken 'threw'
$mix = @(
    [pscustomobject]@{ name = 'rc-foo'; sessionId = 'aaa'; id = 'aaa'; cwd = 'C:\work\foo'; state = 'blocked' }
    [pscustomobject]@{ name = 'workstation-remote-control'; sessionId = 'bbb'; id = 'bbb'; cwd = 'C:\work'; state = 'blocked' }
)
$rootOnly = @(Select-ProjectsRootRcSessions $mix '')
Check 'projects-root filter count' $rootOnly.Count '1'
Check 'projects-root filter name' $rootOnly[0].name 'workstation-remote-control'

if ($fail -gt 0) { Write-Error "$fail test(s) failed"; exit 1 }
'OK'
exit 0
