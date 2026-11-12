#Requires -Version 5.1
# Tests for rc-lib.ps1. Does not call the live claude CLI and does not write the real shortcut folder.
# Shortcut writes go through a fake shell. Usage:
# powershell -NoProfile -ExecutionPolicy Bypass -File workstation/shortcuts/tests/test-rc-shortcuts.ps1
$ErrorActionPreference = 'Stop'
if (-not $env:TEMP) { $env:TEMP = [IO.Path]::GetTempPath().TrimEnd('\', '/') }
# Windows always has SystemRoot. A stand-in keeps Join-Path working where it is unset.
if (-not $env:SystemRoot) { $env:SystemRoot = $env:TEMP }
. (Join-Path $PSScriptRoot '..\rc-lib.ps1')

$fail = 0
function Check([string]$What, $Got, $Want) {
    if ("$Got" -eq "$Want") { "PASS $What" }
    else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}

# Shortcut folders: a .git directory counts. A plain folder, a worktree (.git is a file),
# a dot-folder, and a loose file do not.
$active = Join-Path $env:TEMP ("rc-test-active-" + [guid]::NewGuid().ToString('n'))
$links = Join-Path $env:TEMP ("rc-test-links-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path (Join-Path $active 'plain-folder') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active 'has-git') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active 'has-git\.git') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active 'second-repo') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $active 'second-repo\.git') -Force | Out-Null
$wt = Join-Path $active 'sample-wt'
New-Item -ItemType Directory -Path $wt -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $wt '.git'), "gitdir: /src/main/.git/worktrees/sample-wt`n")
New-Item -ItemType Directory -Path (Join-Path $active '.cursor') -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $active 'notes.txt') -Force | Out-Null
$names = @((Get-RcProjectFolders $active) | ForEach-Object { $_.Name }) -join ','
Check 'only git repos, plain folder and worktree skipped' $names 'has-git,second-repo'
Check 'worktree .git is a file' (Test-Path -LiteralPath (Join-Path $wt '.git') -PathType Leaf) 'True'
Check 'repo .git is a directory' (Test-RcGitRepoDirectory (Join-Path $active 'has-git')) 'True'
Check 'plain folder is not a repo' (Test-RcGitRepoDirectory (Join-Path $active 'plain-folder')) 'False'
Check 'worktree is not a repo directory' (Test-RcGitRepoDirectory $wt) 'False'
Check 'missing active dir is empty' (@(Get-RcProjectFolders (Join-Path $active 'nope')).Count) '0'

Check 'session name' (Get-RcSessionName 'plain-folder') 'rc-plain-folder'
Check 'session name keeps case' (Get-RcSessionName 'PowerTuneDigitalOfficial') 'rc-PowerTuneDigitalOfficial'
Check 'session name slug' (Get-RcSessionName 'my project') 'rc-my-project'
Check 'open link name' (Get-RcOpenLinkName 'my project') 'Start Claude remote - my project.lnk'
Check 'close link name' (Get-RcCloseLinkName 'my project') 'Stop Claude remote - my project.lnk'

function Norm([string]$Path) { return ("$Path" -replace '\\', '/') }
$scriptRoot = 'D:\box\active\workstation\workstation\shortcuts'
$defs = Get-RcDefaults -ScriptRoot $scriptRoot -ConfigPath ''
Check 'default active dir' (Norm $defs.ActiveDir) 'D:/box/active'
Check 'default link dir' (Norm $defs.LinkDir) 'D:/box/active/workstation/shortcuts/rc'
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

# Shortcut files use a fake shell so this never needs WScript.Shell or a live claude.
# Stale pairs for a plain folder and a worktree are removed on regenerate.
function New-RcFakeShell {
    $saved = @{}
    $shell = New-Object PSObject
    $shell | Add-Member -NotePropertyName Saved -NotePropertyValue $saved
    $shell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
        param($path)
        $key = "$path".ToLower()
        if (-not $this.Saved.ContainsKey($key)) {
            $rec = New-Object PSObject
            $rec | Add-Member -NotePropertyName Path -NotePropertyValue "$path"
            foreach ($n in @('TargetPath', 'Arguments', 'WorkingDirectory', 'Description', 'IconLocation')) {
                $rec | Add-Member -NotePropertyName $n -NotePropertyValue ''
            }
            $rec | Add-Member -NotePropertyName WindowStyle -NotePropertyValue 1
            $rec | Add-Member -MemberType ScriptMethod -Name Save -Value {
                $dir = Split-Path -Parent $this.Path
                if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                [IO.File]::WriteAllText($this.Path, 'lnk')
            }
            $this.Saved[$key] = $rec
        }
        return $this.Saved[$key]
    }
    return $shell
}
$openScript = Join-Path $PSScriptRoot '..\rc-open.ps1'
$closeScript = Join-Path $PSScriptRoot '..\rc-close.ps1'
New-Item -ItemType Directory -Path $links -Force | Out-Null
foreach ($stale in @(
    'RC gone.lnk', 'Close RC gone.lnk', 'Start Claude remote - gone.lnk',
    'RC plain-folder.lnk', 'Close RC has-git.lnk',
    'Start Claude remote - plain-folder.lnk', 'Stop Claude remote - plain-folder.lnk',
    'Start Claude remote - sample-wt.lnk', 'Stop Claude remote - sample-wt.lnk'
)) { [IO.File]::WriteAllText((Join-Path $links $stale), 'stale') }
[IO.File]::WriteAllText((Join-Path $links 'notes.txt'), 'keep')
$fakeShell = New-RcFakeShell
$written = Write-RcShortcuts -ActiveDir $active -LinkDir $links -OpenScript $openScript -CloseScript $closeScript -Shell $fakeShell
Check 'write ok' $written.Ok 'True'
Check 'two repos' $written.Projects '2'
Check 'four links created' $written.Created '4'
Check 'stale plain, worktree, and old-named links removed' $written.Removed '9'
Check 'old open name gone' (Test-Path -LiteralPath (Join-Path $links 'RC plain-folder.lnk')) 'False'
Check 'plain folder start link removed' (Test-Path -LiteralPath (Join-Path $links 'Start Claude remote - plain-folder.lnk')) 'False'
Check 'plain folder stop link removed' (Test-Path -LiteralPath (Join-Path $links 'Stop Claude remote - plain-folder.lnk')) 'False'
Check 'worktree start link removed' (Test-Path -LiteralPath (Join-Path $links 'Start Claude remote - sample-wt.lnk')) 'False'
Check 'worktree stop link removed' (Test-Path -LiteralPath (Join-Path $links 'Stop Claude remote - sample-wt.lnk')) 'False'
Check 'notes kept' (Test-Path -LiteralPath (Join-Path $links 'notes.txt')) 'True'
function Get-FakeLink($Shell, [string]$LinkPath) { return $Shell.Saved["$LinkPath".ToLower()] }
$lnk = Get-FakeLink $fakeShell (Join-Path $links 'Start Claude remote - has-git.lnk')
Check 'open link runs rc-open' ($lnk.Arguments -like '*rc-open.ps1*') 'True'
Check 'open link repo arg' ($lnk.Arguments -like ('*' + (Join-Path $active 'has-git') + '*')) 'True'
Check 'open link working directory' $lnk.WorkingDirectory (Join-Path $active 'has-git')
$closeLnk = Get-FakeLink $fakeShell (Join-Path $links 'Stop Claude remote - second-repo.lnk')
Check 'close link runs rc-close' ($closeLnk.Arguments -like '*rc-close.ps1*') 'True'
Check 'no plain-folder link kept' ($null -eq (Get-FakeLink $fakeShell (Join-Path $links 'Start Claude remote - plain-folder.lnk'))) 'True'
Check 'no worktree link kept' ($null -eq (Get-FakeLink $fakeShell (Join-Path $links 'Start Claude remote - sample-wt.lnk'))) 'True'
Check 'no dot-folder link' (Test-Path -LiteralPath (Join-Path $links 'Start Claude remote - .cursor.lnk')) 'False'
$again = Write-RcShortcuts -ActiveDir $active -LinkDir $links -OpenScript $openScript -CloseScript $closeScript -Shell $fakeShell
Check 'second run updates' $again.Updated '4'
Check 'second run creates none' $again.Created '0'
Check 'second run removes none' $again.Removed '0'

# On Windows, also read one real .lnk back. Other machines have no WScript.Shell.
$com = $null
try { $com = New-Object -ComObject WScript.Shell } catch { $com = $null }
if ($null -ne $com) {
    $realLinks = Join-Path $env:TEMP ("rc-test-real-" + [guid]::NewGuid().ToString('n'))
    $real = Write-RcShortcuts -ActiveDir $active -LinkDir $realLinks -OpenScript $openScript -CloseScript $closeScript
    Check 'real shortcuts ok' $real.Ok 'True'
    $realLnk = $com.CreateShortcut((Join-Path $realLinks 'Start Claude remote - has-git.lnk'))
    Check 'real shortcut runs rc-open' ($realLnk.Arguments -like '*rc-open.ps1*') 'True'
    Check 'real shortcut has no plain-folder link' (Test-Path -LiteralPath (Join-Path $realLinks 'Start Claude remote - plain-folder.lnk')) 'False'
    Remove-Item -LiteralPath $realLinks -Recurse -Force -ErrorAction SilentlyContinue
} else { 'SKIP real shortcut read-back (no WScript.Shell)' }

Remove-Item -LiteralPath $active -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $links -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $cfgRoot -Recurse -Force -ErrorAction SilentlyContinue

$root = 'C:\rc-status-test'
Check 'repo from cwd' (Get-RcRepoLabel 'C:\rc-status-test\active\st185-link-ecu-config' 'rc-st185-link-ecu-config' $root) 'st185-link-ecu-config'
Check 'projects root from cwd' (Get-RcRepoLabel 'C:\rc-status-test' 'workstation-remote-control' $root) 'projects root'
Check 'repo from rc name' (Get-RcRepoLabel '' 'rc-handbuilt-cad' $root) 'handbuilt-cad'
Check 'Phone access session name is projects root' (Get-RcRepoLabel '' 'workstation-remote-control' $root) 'projects root'
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

# Daemon status text. The origin line also contains a pid; only the pid: field counts.
$daemonSample = @"
pid:     1391
version: 2.1.246
uptime:  57983s
origin:  transient - started on-demand by claude (pid 1378)
control.sock: reachable
bg workers:   2 running (control.sock), 2 in roster.json
              5 from a different CLI version
"@
$dst = ConvertFrom-RcDaemonStatus $daemonSample 0
Check 'daemon pid ignores origin pid' $dst.Pid '1391'
Check 'daemon version' $dst.Version '2.1.246'
Check 'daemon running' $dst.Running 'True'
Check 'worker version skew is not the supervisor' $dst.Skew 'False'
Check 'ready when the supervisor matches the CLI' (Test-RcDaemonReady $dst '2.1.246') 'True'
Check 'not ready when the supervisor is older' (Test-RcDaemonReady $dst '2.1.301') 'False'
$down = ConvertFrom-RcDaemonStatus "Couldn't reach the background service (not running)" 1
Check 'status not running' $down.Running 'False'
$badPipe = ConvertFrom-RcDaemonStatus "pid:     12`nversion: 2.1.301`ncontrol.sock: unreachable (connect ENOENT)" 0
Check 'unreachable pipe is not usable' $badPipe.Running 'False'
$warn = ConvertFrom-RcDaemonStatus "pid:     4`nversion: 2.1.301`ncontrol.sock: reachable`nsupervisor is on a different version than this CLI" 0
Check 'supervisor warning is skew' $warn.Skew 'True'
Check 'skew is not ready' (Test-RcDaemonReady $warn '2.1.301') 'False'
$wrappedCli = [System.Management.Automation.PSObject]::AsPSObject(@{ ExitCode = 3; Text = 'hi' })
Check 'wrapped cli result still counts' (Test-RcCliResult $wrappedCli) 'True'
Check 'plain text is not a cli result' (Test-RcCliResult 'backgrounded') 'False'
Check 'cli version' (Get-RcCliVersion "2.1.301 (Claude Code)`n") '2.1.301'
Check 'cli version missing' (Get-RcCliVersion 'nope') ''
Check 'missing binary stamp' (Get-RcBinaryStamp (Join-Path $env:TEMP 'no-such-claude.exe')) ''
$stampFile = Join-Path $env:TEMP ("rc-stamp-" + [guid]::NewGuid().ToString('n'))
[IO.File]::WriteAllText($stampFile, 'x')
$stampBefore = Get-RcBinaryStamp $stampFile
[IO.File]::WriteAllText($stampFile, 'xyz')
$stampAfter = Get-RcBinaryStamp $stampFile
Check 'stamp changes when the binary changes' ($stampBefore -ne $stampAfter -and $stampBefore -ne '') 'True'
Remove-Item -LiteralPath $stampFile -Force -ErrorAction SilentlyContinue

# Launch uses a fake CLI. No live claude. Sleep is a no-op.
function Rc-DaemonText([string]$DaemonPid, [string]$Version) {
    @"
pid:     $DaemonPid
version: $Version
uptime:  12s
origin:  transient - started on-demand by claude (pid 999)
control.sock: reachable
"@
}
$rcSessionJson = '[{"id":"abc12345","sessionId":"abc12345-1111-1111-1111-111111111111","cwd":"C:\\work\\repo","name":"rc-repo","state":"blocked"}]'
function Invoke-LaunchCase([scriptblock]$Fake) {
    $calls = New-Object System.Collections.Generic.List[string]
    $invoke = {
        param($ArgumentList)
        $cmd = @($ArgumentList) -join ' '
        $calls.Add($cmd)
        & $Fake $cmd $calls
    }.GetNewClosure()
    $noop = { param([int]$Milliseconds) }
    $result = Invoke-RcRemoteLaunch -InvokeCli $invoke -RepoPath 'C:\work\repo' -SessionName 'rc-repo' `
        -GetBinaryStamp { '' } -Sleep $noop -PollMilliseconds 0
    return @{ Result = $result; Calls = @($calls) }
}
function CallIndex($Calls, [string]$Cmd) {
    for ($i = 0; $i -lt @($Calls).Count; $i++) { if ($Calls[$i] -eq $Cmd) { return $i } }
    return -1
}
function CallCount($Calls, [string]$Prefix) { @($Calls | Where-Object { "$_" -like $Prefix }).Count }

# Cold service: update, then start the service, and only then the session. One start sticks.
$cold = @{ Warm = $false }
$coldRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'update') { return @{ ExitCode = 0; Text = 'Already up to date (2.1.301)' } }
    if ($cmd -eq 'daemon run') { $cold.Warm = $true; return @{ ExitCode = 0; Text = '' } }
    if ($cmd -eq 'daemon status') {
        if (-not $cold.Warm) { return @{ ExitCode = 1; Text = "Couldn't reach the background service (not running)" } }
        return @{ ExitCode = 0; Text = (Rc-DaemonText '5' '2.1.301') }
    }
    if ($cmd -eq 'agents --json') {
        if ((CallCount $calls '--bg*') -ge 1) { return @{ ExitCode = 0; Text = $rcSessionJson } }
        return @{ ExitCode = 0; Text = '[]' }
    }
    if ($cmd -like '--bg*') { return @{ ExitCode = 0; Text = 'backgrounded * abc12345 * rc-repo' } }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'cold start ok' $coldRun.Result.Ok 'True'
Check 'cold start once' $coldRun.Result.Starts '1'
Check 'cold session id' $coldRun.Result.SessionId 'abc12345'
Check 'cold full id' $coldRun.Result.FullId 'abc12345-1111-1111-1111-111111111111'
$coldUpdate = CallIndex $coldRun.Calls 'update'
$coldWarm = CallIndex $coldRun.Calls 'daemon run'
$coldBg = CallIndex $coldRun.Calls '--bg --remote-control --name rc-repo'
Check 'cold updates before the service' ($coldUpdate -ge 0 -and $coldWarm -gt $coldUpdate) 'True'
Check 'cold starts the session after the service' ($coldBg -gt $coldWarm) 'True'

# Warm service already on this version: no update, no extra service start, one session.
$warmRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'daemon status') { return @{ ExitCode = 0; Text = (Rc-DaemonText '5' '2.1.301') } }
    if ($cmd -eq 'agents --json') {
        if ((CallCount $calls '--bg*') -ge 1) { return @{ ExitCode = 0; Text = $rcSessionJson } }
        return @{ ExitCode = 0; Text = '[]' }
    }
    if ($cmd -like '--bg*') { return @{ ExitCode = 0; Text = 'backgrounded * abc12345 * rc-repo' } }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'warm start ok' $warmRun.Result.Ok 'True'
Check 'warm start once' $warmRun.Result.Starts '1'
Check 'warm skips update' (CallCount $warmRun.Calls 'update') '0'
Check 'warm skips daemon run' (CallCount $warmRun.Calls 'daemon run') '0'

# Supervisor is still on the old version: do not start the session until it matches.
$skew = @{ Pid = '1' }
$skewRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'update') { return @{ ExitCode = 0; Text = 'Already up to date (2.1.301)' } }
    if ($cmd -eq 'daemon status') {
        $n = CallCount $calls 'daemon status'
        if ($n -lt 3) { $skew.Pid = '1'; return @{ ExitCode = 0; Text = (Rc-DaemonText '1' '2.1.300') } }
        $skew.Pid = '2'
        return @{ ExitCode = 0; Text = (Rc-DaemonText '2' '2.1.301') }
    }
    if ($cmd -eq 'agents --json') {
        if ((CallCount $calls '--bg*') -ge 1) { return @{ ExitCode = 0; Text = $rcSessionJson } }
        return @{ ExitCode = 0; Text = '[]' }
    }
    if ($cmd -like '--bg*') {
        if ($skew.Pid -ne '2') { return @{ ExitCode = 99; Text = 'started while the service was still old' } }
        return @{ ExitCode = 0; Text = 'backgrounded * abc12345 * rc-repo' }
    }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'skew start ok' $skewRun.Result.Ok 'True'
Check 'skew start once' $skewRun.Result.Starts '1'
Check 'skew did not start early' ($skewRun.Result.Output -notlike '*still old*') 'True'

# First session is listed once, then gone (upgrade restart refused it). The second start sticks.
$drop = @{ Bg = 0; After = 0 }
$dropRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'daemon status') { return @{ ExitCode = 0; Text = (Rc-DaemonText '10' '2.1.301') } }
    if ($cmd -like '--bg*') { $drop.Bg++; $drop.After = 0; return @{ ExitCode = 0; Text = 'backgrounded * abc12345 * rc-repo' } }
    if ($cmd -eq 'agents --json') {
        $drop.After++
        if ($drop.Bg -eq 1 -and $drop.After -eq 1) { return @{ ExitCode = 0; Text = $rcSessionJson } }
        if ($drop.Bg -ge 2) { return @{ ExitCode = 0; Text = $rcSessionJson } }
        return @{ ExitCode = 0; Text = '[]' }
    }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'dropped session is started again' $dropRun.Result.Ok 'True'
Check 'dropped session took two starts' $dropRun.Result.Starts '2'
Check 'retry was logged' (($dropRun.Result.Log -join ' ') -like '*once more*') 'True'

# Agents never lists the session. Stop after the one retry. Do not claim success.
$neverRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'daemon status') { return @{ ExitCode = 0; Text = (Rc-DaemonText '5' '2.1.301') } }
    if ($cmd -eq 'agents --json') { return @{ ExitCode = 0; Text = '[]' } }
    if ($cmd -like '--bg*') { return @{ ExitCode = 0; Text = 'backgrounded * abc12345 * rc-repo' } }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'missing session is not success' $neverRun.Result.Ok 'False'
Check 'missing session stops after two starts' $neverRun.Result.Starts '2'

# Already listed: do not start another.
$liveRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'daemon status') { return @{ ExitCode = 0; Text = (Rc-DaemonText '5' '2.1.301') } }
    if ($cmd -eq 'agents --json') { return @{ ExitCode = 0; Text = $rcSessionJson } }
    if ($cmd -like '--bg*') { return @{ ExitCode = 99; Text = 'should not start' } }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'already listed ok' $liveRun.Result.Ok 'True'
Check 'already listed starts none' $liveRun.Result.Starts '0'
Check 'already listed detail' $liveRun.Result.Detail 'already running'

# Update command fails (offline). Still warm the service and start.
$offline = @{ Warm = $false }
$offlineRun = Invoke-LaunchCase ({
    param($cmd, $calls)
    if ($cmd -eq '--version') { return @{ ExitCode = 0; Text = '2.1.301 (Claude Code)' } }
    if ($cmd -eq 'update') { return @{ ExitCode = 1; Text = 'network down' } }
    if ($cmd -eq 'daemon run') { $offline.Warm = $true; return @{ ExitCode = 0; Text = '' } }
    if ($cmd -eq 'daemon status') {
        if (-not $offline.Warm) { return @{ ExitCode = 1; Text = 'not running' } }
        return @{ ExitCode = 0; Text = (Rc-DaemonText '8' '2.1.301') }
    }
    if ($cmd -eq 'agents --json') {
        if ((CallCount $calls '--bg*') -ge 1) { return @{ ExitCode = 0; Text = $rcSessionJson } }
        return @{ ExitCode = 0; Text = '[]' }
    }
    if ($cmd -like '--bg*') { return @{ ExitCode = 0; Text = 'backgrounded * abc12345 * rc-repo' } }
    return @{ ExitCode = 1; Text = "unexpected $cmd" }
}.GetNewClosure())
Check 'offline update still starts' $offlineRun.Result.Ok 'True'
Check 'offline update logged' (($offlineRun.Result.Log -join ' ') -like '*did not finish*') 'True'

if ($fail -gt 0) { Write-Error "$fail test(s) failed"; exit 1 }
'OK'
exit 0
