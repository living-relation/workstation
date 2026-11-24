# Manual Cursor worker: command line, folder pick, stop list, health lines.
# No real worker is started. Usage: pwsh -NoProfile -File workstation/cursor-worker/tests/test-cursor-worker.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
$lib = Join-Path (Split-Path -Parent $here) 'cursor-worker-lib.ps1'
$start = Join-Path (Split-Path -Parent $here) 'start-cursor-worker.ps1'
$stop = Join-Path (Split-Path -Parent $here) 'stop-cursor-worker.ps1'
$pwsh = @(Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { 'FAIL powershell not found'; exit 1 }
$fail = 0
function Check([string]$What, $Got, $Want) {
    if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("cw-" + [guid]::NewGuid().ToString('N'))
$active = Join-Path (Join-Path $root 'projects') 'active'
$local = Join-Path $root 'local'
New-Item -ItemType Directory -Path (Join-Path $active 'widget'), (Join-Path $active 'other'), $local -Force | Out-Null
Set-Content (Join-Path $root 'agent.cmd') '@echo off'
$env:WORKSTATION_PROJECTS_ROOT = Join-Path $root 'projects'
$env:WORKSTATION_FAKE_AGENT = Join-Path $root 'agent.cmd'
$env:WORKSTATION_FAKE_PROCS = 'none'
$env:WORKSTATION_FAKE_AUTOSTART = 'none'
$env:WORKSTATION_FAKE_RESTART = 'none'
$env:LOCALAPPDATA = $local

. $lib
Check 'active dir is detected' (Get-ActiveProjectsDir) $active
Check 'not the hard-coded DansPC root' ($active -eq 'C:\projects\active') False
Check 'two folders' @(Get-ActiveFolders).Count 2
Check 'plain folder has no origin' (Test-FolderOrigin (Join-Path $active 'widget')) False
$line = Format-FolderChoice 1 (Get-Item (Join-Path $active 'widget')) ''
Check 'menu marks no git remote' ($line -match 'no git remote') True

$slugW = Get-WorkerSlug (Join-Path $active 'widget')
$slugO = Get-WorkerSlug (Join-Path $active 'other')
Check 'slugs differ' ($slugW -ne $slugO) True
$name = Get-WorkerDisplayName (Join-Path $active 'widget')
Check 'name is safe' ($name -match '^[A-Za-z0-9._-]+$') True
Check 'name contains folder' ($name -match 'widget') True

$data = Get-WorkerDataDir (Join-Path $active 'widget')
$args = @(Get-CursorWorkerArgList -Name 'pc-widget' -Folder (Join-Path $active 'widget') -DataDir $data -MgmtAddr '127.0.0.1:8791')
$cmd = Format-CmdLine $args
$expect = 'worker --name pc-widget --worker-dir ' + (Format-CmdArg (Join-Path $active 'widget')) + ' --data-dir ' + (Format-CmdArg $data) + ' --management-addr 127.0.0.1:8791 --idle-release-timeout 0 --label workstation=manual start'
Check 'worker command' $cmd $expect
Check 'quotes a path with a space' (Format-CmdArg 'C:\My Projects') '"C:\My Projects"'
Check 'options before start' ($cmd.TrimEnd().EndsWith('start')) True
Check 'no pool flag' ($cmd -match '--pool') False
$port2 = Get-WorkerMgmtPort @(8791)
Check 'second port skips the used one' (($port2 -ge 8792) -and ($port2 -le 8810)) True

$ours = 'agent worker --name pc-widget --worker-dir ' + (Join-Path $active 'widget') + ' --data-dir ' + $data + ' --management-addr 127.0.0.1:8791 --idle-release-timeout 0 --label workstation=manual start'
$child = 'node worker --data-dir ' + $data + ' --label workstation=manual'
$hand = 'agent worker --worker-dir ' + (Join-Path $active 'other') + ' start'
$env:WORKSTATION_FAKE_PROCS = (@(
    @{ ProcessId = 7; ParentProcessId = 1; Name = 'Cursor'; CommandLine = 'Cursor.exe' },
    @{ ProcessId = 42; ParentProcessId = 1; Name = 'agent'; CommandLine = $ours },
    @{ ProcessId = 43; ParentProcessId = 42; Name = 'node'; CommandLine = $child },
    @{ ProcessId = 50; ParentProcessId = 1; Name = 'agent'; CommandLine = $hand },
    @{ ProcessId = 9; ParentProcessId = 1; Name = 'powershell'; CommandLine = 'powershell -File start-cursor-worker.ps1' }
) | ConvertTo-Json -Compress)
$rows = @(Get-CursorWorkerRows)
Check 'one worker after folding the child' $rows.Count 1
Check 'stop target is the outer process' $rows[0].Pid 42
Check 'cursor app not listed' @($rows | Where-Object { $_.Name -eq 'Cursor' }).Count 0
Check 'hand-started worker not listed' @($rows | Where-Object { $_.Pid -eq 50 }).Count 0
Check 'menu script not listed' @($rows | Where-Object { $_.Pid -eq 9 }).Count 0

$oursOnly = (@(
    @{ ProcessId = 7; ParentProcessId = 1; Name = 'Cursor'; CommandLine = 'Cursor.exe' },
    @{ ProcessId = 42; ParentProcessId = 1; Name = 'agent'; CommandLine = $ours },
    @{ ProcessId = 43; ParentProcessId = 42; Name = 'node'; CommandLine = $child },
    @{ ProcessId = 9; ParentProcessId = 1; Name = 'powershell'; CommandLine = 'powershell -File start-cursor-worker.ps1' }
) | ConvertTo-Json -Compress)
$env:WORKSTATION_FAKE_PROCS = $oursOnly
$lines = @(Get-CursorWorkerHealthLines)
Check 'running is run' $lines[0].Level 'RUN'
Check 'running line names the pid' ($lines[0].Text -match 'pid 42') True
Check 'running line names the folder' ($lines[0].Text -match 'widget') True
Check 'no autostart warn' @($lines | Where-Object { $_.Level -eq 'WARN' }).Count 0

$appCmd = 'cursor-agent worker start --worker-dir ' + (Join-Path $active 'other') + ' --api-key sample-key-value --endpoint https://example.test'
$withApp = (@(
    @{ ProcessId = 42; ParentProcessId = 1; Name = 'agent'; CommandLine = $ours },
    @{ ProcessId = 77; ParentProcessId = 1; Name = 'cursor-agent'; CommandLine = $appCmd },
    @{ ProcessId = 50; ParentProcessId = 1; Name = 'agent'; CommandLine = $hand }
) | ConvertTo-Json -Compress)
$env:WORKSTATION_FAKE_PROCS = $withApp
$outRows = @(Get-OutsideCursorWorkerRows)
Check 'outside workers counted' $outRows.Count 2
Check 'our rows ignore the app worker' @(Get-CursorWorkerRows).Count 1
Check 'outside row drops the command' (@($outRows | Where-Object { "$($_.CommandLine)" -match 'sample-key-value' }).Count) 0
$olines = @(Get-CursorWorkerHealthLines)
$warnText = (@($olines | Where-Object { $_.Level -eq 'WARN' } | ForEach-Object { $_.Text }) -join ' ')
Check 'outside warns' ($warnText -match 'started outside our script') True
Check 'outside names the app pid' ($warnText -match 'pid 77') True
Check 'outside names the folder' ($warnText -match 'other') True
Check 'outside hides the key' ($warnText -match 'sample-key-value') False
Check 'outside hides the api-key flag' ($warnText -match '--api-key') False

$env:WORKSTATION_FAKE_PROCS = 'none'
$idle = @(Get-CursorWorkerHealthLines)
Check 'not running is stop' $idle[0].Level 'STOP'
Check 'not running is not a warn' @($idle | Where-Object { $_.Level -eq 'WARN' }).Count 0
Check 'idle text' ($idle[0].Text -match 'not running') True
Check 'idle startup line' (@($idle | Where-Object { $_.Text -match 'no Windows startup entry' -and $_.Level -eq 'RUN' }).Count) 1

$env:WORKSTATION_FAKE_AUTOSTART = '["Task:Cursor-Worker","Run:CursorWorker"]'
$auto = @(Get-CursorWorkerHealthLines)
Check 'autostart warns' @($auto | Where-Object { $_.Level -eq 'WARN' }).Count 1
Check 'still not a missing-worker warn' ($auto[0].Level) 'STOP'
$env:WORKSTATION_FAKE_AUTOSTART = 'none'
$env:WORKSTATION_FAKE_RESTART = '["cursor-agent-worker-abc.restart.json"]'
$re = @(Get-CursorWorkerHealthLines)
Check 'restart.json warns' @($re | Where-Object { $_.Level -eq 'WARN' -and $_.Text -match 'restart.json' }).Count 1
Check 'restart does not claim the app is off' @($re | Where-Object { $_.Text -match 'does not start at' }).Count 0
Check 'no windows startup entry still shown' @($re | Where-Object { $_.Level -eq 'RUN' -and $_.Text -match 'no Windows startup entry' }).Count 1
$env:WORKSTATION_FAKE_RESTART = 'none'
$env:WORKSTATION_FAKE_PROCS = 'none'

$deadDir = Join-Path (Join-Path (Join-Path $local 'Workstation') 'cursor-worker') 'instances/deadone'
New-Item -ItemType Directory -Path $deadDir -Force | Out-Null
Set-Content (Join-Path $deadDir 'worker.json') '{"pid":4242,"folder":"widget"}'
Set-Content (Join-Path $deadDir 'worker.err.log') 'Authentication required for worker mode. Please run agent login'
$dead = @(Get-CursorWorkerHealthLines)
Check 'dead worker is fail' @($dead | Where-Object { $_.Level -eq 'FAIL' -and $_.Text -match 'pid 4242' -and $_.Text -match 'agent login' }).Count 1
Check 'dead line has no command' ((@($dead | ForEach-Object { $_.Text }) -join ' ') -match '--api-key|sample-key') False
Remove-Item -LiteralPath $deadDir -Recurse -Force

$orphans = Join-Path (Join-Path $repo 'workstation\health') 'orphans.ps1'
. $orphans
$one = @(
    [pscustomobject]@{ ProcessId = 42; ParentProcessId = 1; Name = 'agent'; CommandLine = $ours; CreationDate = '2026-01-01T00:00:00Z'; HasConsole = $true },
    [pscustomobject]@{ ProcessId = 15; ParentProcessId = 1; Name = 'python'; CommandLine = 'python workstation/dashboard/server.py'; CreationDate = '2026-01-01T00:00:00Z'; HasConsole = $true }
)
$cands = @(Get-OrphanCandidates $one)
Check 'worker is not an orphan' @($cands | Where-Object { $_.Pid -eq 42 }).Count 0
Check 'old web server still listed' @($cands | Where-Object { $_.Pid -eq 15 }).Count 1

function Run-Script([string]$Script, [string[]]$ArgList) {
    $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $Script @ArgList 2>&1
    return @{ code = $LASTEXITCODE; out = ($out -join "`n") }
}
$what = Run-Script $start @('-Folder', 'widget', '-WhatIf', '-NoPause')
Check 'whatif exit' $what.code 0
Check 'whatif command' ($what.out -match 'WOULD\|agent worker --name .+ --worker-dir .+ --data-dir .+ --management-addr 127\.0\.0\.1:\d+ --idle-release-timeout 0 --label workstation=manual start') True
Check 'whatif does not schedule' ($what.out -match 'Register-ScheduledTask|schtasks') False

$env:WORKSTATION_FAKE_PROCS = (@(
    @{ ProcessId = 42; ParentProcessId = 1; Name = 'agent'; CommandLine = $ours }
) | ConvertTo-Json -Compress)
$again = Run-Script $start @('-Folder', 'widget', '-WhatIf', '-NoPause')
Check 'second start of same folder does not launch' $again.code 0
Check 'says already running' ($again.out -match 'Already running') True
Check 'no second would' ($again.out -match 'WOULD\|') False

$env:WORKSTATION_FAKE_PROCS = 'none'
$other = Run-Script $start @('-Folder', 'other', '-WhatIf', '-NoPause')
Check 'other folder would start' ($other.out -match 'WOULD\|agent worker ') True
Check 'other folder data dir differs' ($other.out -match [regex]::Escape($slugO)) True

$bad = Run-Script $start @('-Folder', 'missing', '-NoPause')
Check 'unknown folder fails' $bad.code 1

$env:WORKSTATION_FAKE_AGENT = 'missing'
$nocli = Run-Script $start @('-Folder', 'widget', '-NoPause')
Check 'missing cli fails' $nocli.code 1
Check 'missing cli tells login' ($nocli.out -match 'agent login') True
$env:WORKSTATION_FAKE_AGENT = Join-Path $root 'agent.cmd'

$die = Join-Path $root 'die-agent.ps1'
Set-Content -LiteralPath $die -Value "[Console]::Error.WriteLine('Authentication required for worker mode. Please run agent login')`r`nexit 1`r`n"
$sleeper = Join-Path $root 'sleep-agent.ps1'
Set-Content -LiteralPath $sleeper -Value "Start-Sleep -Seconds 30`r`n"
$env:WORKSTATION_FAKE_PROCS = 'none'
$env:WORKSTATION_FAKE_AGENT = $die
$env:WORKSTATION_START_WAIT_SEC = '3'
Remove-Item Env:WORKSTATION_FAKE_START_ALIVE -ErrorAction SilentlyContinue
$authStart = Run-Script $start @('-Folder', 'other', '-NoPause')
Check 'auth death fails' $authStart.code 1
Check 'auth death says login' ($authStart.out -match '\[FAIL\].*agent login') True
Check 'auth death does not say started' ($authStart.out -match '\[ OK \] Started') False
$startLog = Join-Path (Join-Path (Join-Path $local 'Workstation') 'cursor-worker') 'start.log'
$logText = ''
if (Test-Path -LiteralPath $startLog) { $logText = [IO.File]::ReadAllText($startLog) }
Check 'auth death is not logged as started' ($logText -match 'started pid') False
Check 'auth death is logged as failed' ($logText -match 'start FAILED') True
$env:WORKSTATION_FAKE_AGENT = $sleeper
$env:WORKSTATION_START_WAIT_SEC = '0'
$live = Run-Script $start @('-Folder', 'widget', '-NoPause')
Check 'live start exit' $live.code 0
Check 'live start says started' ($live.out -match '\[ OK \] Started') True
$logText2 = ''
if (Test-Path -LiteralPath $startLog) { $logText2 = [IO.File]::ReadAllText($startLog) }
Check 'live start is logged' ($logText2 -match 'started pid') True
$psOut = & ps -eo pid,args
foreach ($pl in @($psOut)) {
    if ("$pl" -match 'sleep-agent\.ps1' -and "$pl" -match '^\s*(\d+)') {
        Stop-Process -Id ([int]$Matches[1]) -Force -ErrorAction SilentlyContinue
    }
}
Remove-Item Env:WORKSTATION_START_WAIT_SEC -ErrorAction SilentlyContinue
$env:WORKSTATION_FAKE_AGENT = Join-Path $root 'agent.cmd'

$env:WORKSTATION_FAKE_PROCS = (@(
    @{ ProcessId = 42; ParentProcessId = 1; Name = 'agent'; CommandLine = $ours }
) | ConvertTo-Json -Compress)
$stopOut = Run-Script $stop @('-All', '-WhatIf', '-NoPause')
Check 'stop whatif exit' $stopOut.code 0
Check 'stop whatif names pid' ($stopOut.out -match 'WOULD\|stop pid 42') True
$env:WORKSTATION_FAKE_PROCS = 'none'
$none = Run-Script $stop @('-All', '-NoPause')
Check 'stop with none is ok' $none.code 0
Check 'stop says none' ($none.out -match 'No Cursor workers') True

$scripts = @($lib, $start, $stop, (Join-Path $repo 'install.ps1'), (Join-Path $repo 'cleanup-legacy.ps1'), (Join-Path $repo 'preflight.ps1'))
foreach ($f in $scripts) {
    $tokens = $null; $parseErr = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$parseErr)
    Check ("parses " + (Split-Path $f -Leaf)) @($parseErr).Count 0
    $bytes = [IO.File]::ReadAllBytes($f)
    $high = @($bytes | Where-Object { $_ -gt 127 }).Count
    if ($f -like '*cursor-worker*') { Check ("ascii " + (Split-Path $f -Leaf)) $high 0 }
}
$raw = (Get-Content -LiteralPath $start -Raw) + (Get-Content -LiteralPath $stop -Raw) + (Get-Content -LiteralPath $lib -Raw)
Check 'no scheduled task' ($raw -match 'Register-ScheduledTask|schtasks|New-ScheduledTask') False
Check 'no run key write' ($raw -match 'Set-ItemProperty|New-ItemProperty|Remove-ItemProperty') False

$cleanup = Join-Path $repo 'cleanup-legacy.ps1'
$state = Join-Path $root 'state'
$old = Join-Path $state 'cursor-worker'
$kept = Join-Path $root 'state2'
$newDir = Join-Path (Join-Path $kept 'cursor-worker') 'instances'
New-Item -ItemType Directory -Path (Join-Path $old 'logs'), $newDir -Force | Out-Null
Set-Content (Join-Path $old 'logs\old.txt') 'old'
Set-Content (Join-Path $newDir 'worker.json') '{}'
$user = Join-Path $root 'home'
New-Item -ItemType Directory -Path (Join-Path $user '.claude') -Force | Out-Null
Set-Content (Join-Path $user '.claude\settings.json') '{}'
$env:WORKSTATION_FAKE_PROCS = 'none'
& $pwsh -NoProfile -File $cleanup -UserHome $user -StateDir $state -CloneRoot $root | Out-Null
Check 'old cursor-worker archived' (Test-Path -LiteralPath $old) False
& $pwsh -NoProfile -File $cleanup -UserHome $user -StateDir $kept -CloneRoot $root | Out-Null
Check 'manual instances kept' (Test-Path -LiteralPath (Join-Path $newDir 'worker.json')) True

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
