# Decision logic for the Fusion add-in updater (dirty, branch, upstream, behind).
# Usage: pwsh -NoProfile -File workstation/fusion-addins/tests/test-fusion-addins.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$fusionDir = Split-Path -Parent $here
$repo = Split-Path -Parent (Split-Path -Parent $fusionDir)
$lib = Join-Path $fusionDir 'fusion-addins-lib.ps1'
$updater = Join-Path $fusionDir 'update-fusion-addins.ps1'
$readme = Join-Path $fusionDir 'README.md'
$rootReadme = Join-Path $repo 'README.md'
$pwsh = @(Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwsh) { 'FAIL powershell not found'; exit 1 }
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$env:GIT_AUTHOR_NAME = 'Test'
$env:GIT_AUTHOR_EMAIL = 'test@example.com'
$env:GIT_COMMITTER_NAME = 'Test'
$env:GIT_COMMITTER_EMAIL = 'test@example.com'
$fail = 0
function Check([string]$What, $Got, $Want) {
    if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ }
}
. $lib

$plans = @(
    @{ Name = 'dirty wins'; Dirty = $true; Branch = 'feature'; Default = 'main'; Up = $false; Counted = $true; Ahead = 1; Behind = 1; Action = 'skip'; Reason = 'dirty' }
    @{ Name = 'other branch'; Dirty = $false; Branch = 'feature'; Default = 'main'; Up = $true; Counted = $false; Ahead = 0; Behind = 0; Action = 'skip'; Reason = 'not-default-branch' }
    @{ Name = 'default unknown'; Dirty = $false; Branch = 'main'; Default = ''; Up = $true; Counted = $false; Ahead = 0; Behind = 0; Action = 'skip'; Reason = 'default-branch-unknown' }
    @{ Name = 'no upstream'; Dirty = $false; Branch = 'main'; Default = 'main'; Up = $false; Counted = $false; Ahead = 0; Behind = 0; Action = 'skip'; Reason = 'no-upstream' }
    @{ Name = 'eligible fetches first'; Dirty = $false; Branch = 'main'; Default = 'main'; Up = $true; Counted = $false; Ahead = 0; Behind = 4; Action = 'fetch'; Reason = 'eligible' }
    @{ Name = 'behind pulls'; Dirty = $false; Branch = 'main'; Default = 'main'; Up = $true; Counted = $true; Ahead = 0; Behind = 3; Action = 'pull'; Reason = 'behind' }
    @{ Name = 'even does not pull'; Dirty = $false; Branch = 'main'; Default = 'main'; Up = $true; Counted = $true; Ahead = 0; Behind = 0; Action = 'none'; Reason = 'not-behind' }
    @{ Name = 'ahead does not pull'; Dirty = $false; Branch = 'main'; Default = 'main'; Up = $true; Counted = $true; Ahead = 2; Behind = 0; Action = 'none'; Reason = 'ahead' }
    @{ Name = 'diverged does not pull'; Dirty = $false; Branch = 'main'; Default = 'main'; Up = $true; Counted = $true; Ahead = 1; Behind = 1; Action = 'skip'; Reason = 'diverged' }
)
foreach ($p in $plans) {
    $got = Get-FusionRepoPlan -Dirty:([bool]$p.Dirty) -Branch $p.Branch -DefaultBranch $p.Default -HasUpstream:([bool]$p.Up) -Ahead $p.Ahead -Behind $p.Behind -Counted:([bool]$p.Counted)
    Check ("plan " + $p.Name) ($got.Action + '/' + $got.Reason) ($p.Action + '/' + $p.Reason)
}
Check 'name SRBom' (ConvertTo-AddInDisplayName 'SRBom') 'SR BOM'
Check 'name SRDrawingPDF' (ConvertTo-AddInDisplayName 'SRDrawingPDF') 'SR Drawing PDF'
Check 'name SRExport' (ConvertTo-AddInDisplayName 'SRExport') 'SR Export'
Check 'name SRFastener' (ConvertTo-AddInDisplayName 'SRFastener') 'SR Fastener'

$work = Join-Path ([IO.Path]::GetTempPath()) ("fa-" + [guid]::NewGuid().ToString('N'))
$logs = Join-Path $work 'logs'
$toast = Join-Path $logs 'toast.txt'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$savedPath = $env:PATH
$savedAddins = $env:WORKSTATION_FUSION_ADDINS
$savedLog = $env:WORKSTATION_FUSION_LOG_DIR
$savedToast = $env:WORKSTATION_FUSION_TOAST_SINK
$savedFake = $env:WORKSTATION_FUSION_FAKE_TASK

function Run-Git([string]$Repo, [string[]]$GitArgs) {
    $out = & git -C $Repo @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($GitArgs -join ' ') + " failed: " + (($out | ForEach-Object { "$_" }) -join ' ')) }
    return $out
}
function New-Pair([string]$Name) {
    $dir = Join-Path $work $Name
    $origin = Join-Path $dir 'origin.git'
    $clone = Join-Path $dir 'clone'
    New-Item -ItemType Directory -Path (Join-Path $clone 'SRBom') -Force | Out-Null
    Run-Git $clone @('init', '-b', 'main') | Out-Null
    Run-Git $clone @('config', 'user.email', 'test@example.com') | Out-Null
    Run-Git $clone @('config', 'user.name', 'Test') | Out-Null
    Run-Git $clone @('config', 'commit.gpgsign', 'false') | Out-Null
    Run-Git $clone @('config', 'core.hooksPath', (Join-Path $clone '.git\hooks')) | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'SRBom\addin.py') "print('ok')"
    Run-Git $clone @('add', 'SRBom/addin.py') | Out-Null
    Run-Git $clone @('commit', '-m', 'add add-in') | Out-Null
    & git init --bare -b main $origin | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bare init failed: $origin" }
    Run-Git $clone @('remote', 'add', 'origin', $origin) | Out-Null
    Run-Git $clone @('push', '-u', 'origin', 'main') | Out-Null
    Run-Git $clone @('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main') | Out-Null
    return @{ Origin = $origin; Clone = $clone; Dir = $dir }
}
function Add-RemoteFile($Pair, [string]$Rel, [string]$Content) {
    $other = Join-Path $Pair.Dir 'other'
    if (Test-Path -LiteralPath $other) { Remove-Item -LiteralPath $other -Recurse -Force }
    Run-Git $Pair.Dir @('clone', $Pair.Origin, $other) | Out-Null
    Run-Git $other @('config', 'user.email', 'test@example.com') | Out-Null
    Run-Git $other @('config', 'user.name', 'Test') | Out-Null
    Run-Git $other @('config', 'commit.gpgsign', 'false') | Out-Null
    Run-Git $other @('config', 'core.hooksPath', (Join-Path $other '.git\hooks')) | Out-Null
    $dest = $other
    foreach ($part in ($Rel -split '/')) { $dest = Join-Path $dest $part }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $dest $Content
    Run-Git $other @('add', '--', $Rel) | Out-Null
    Run-Git $other @('commit', '-m', 'remote change') | Out-Null
    Run-Git $other @('push', 'origin', 'HEAD:main') | Out-Null
}
function Add-LocalFile([string]$Clone, [string]$Rel, [string]$Content) {
    $dest = $Clone
    foreach ($part in ($Rel -split '/')) { $dest = Join-Path $dest $part }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $dest $Content
    Run-Git $Clone @('add', '--', $Rel) | Out-Null
    Run-Git $Clone @('commit', '-m', 'local change') | Out-Null
}
function Head-Of([string]$Repo) { return ((& git -C $Repo rev-parse HEAD).Trim()) }
function New-AddIns { $d = Join-Path $work ("addins-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $d | Out-Null; return $d }
function Add-Link([string]$AddIns, [string]$Name, [string]$Target) {
    New-Item -ItemType SymbolicLink -Path (Join-Path $AddIns $Name) -Target $Target | Out-Null
}
function Invoke-Update([string]$AddIns) {
    if (Test-Path -LiteralPath $toast) { Remove-Item -LiteralPath $toast -Force }
    $env:WORKSTATION_FUSION_ADDINS = $AddIns
    $env:WORKSTATION_FUSION_LOG_DIR = $logs
    $env:WORKSTATION_FUSION_TOAST_SINK = $toast
    $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $updater 2>&1
    $text = @($out | ForEach-Object { "$_" }) -join "`n"
    $last = $null
    $lastPath = Join-Path $logs 'fusion-addins-last.json'
    if (Test-Path -LiteralPath $lastPath) { $last = Get-Content -LiteralPath $lastPath -Raw | ConvertFrom-Json }
    return @{ code = $LASTEXITCODE; out = $text; last = $last }
}
function Repo-Rows($Last) {
    if (-not $Last -or -not $Last.PSObject.Properties['repos'] -or $null -eq $Last.repos) { return @() }
    return @($Last.repos)
}

try {
    $threw = $false
    try { Invoke-FusionGit -Root $repo -GitArgs @('reset', '--hard') } catch { $threw = $true }
    Check 'refuses reset' $threw True
    $threw = $false
    try { Invoke-FusionGit -Root $repo -GitArgs @('pull', '--quiet') } catch { $threw = $true }
    Check 'refuses pull without ff-only' $threw True

    $pair = New-Pair 'behind'
    $before = Head-Of $pair.Clone
    Add-RemoteFile $pair 'more.txt' 'from-remote'
    New-Item -ItemType Directory -Path (Join-Path $pair.Clone 'user_scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pair.Clone 'user_scripts\keep.txt') 'keep-me'
    $addins = New-AddIns
    Add-Link $addins 'SRBom' (Join-Path $pair.Clone 'SRBom')
    Add-Link $addins 'ExtraLink' $pair.Clone
    $plain = Join-Path $addins 'NotALink'
    New-Item -ItemType Directory -Path $plain | Out-Null
    Set-Content -LiteralPath (Join-Path $plain 'ignore.txt') 'no'
    $ran = Invoke-Update $addins
    Check 'behind exit' $ran.code 0
    Check 'behind moved' ((Head-Of $pair.Clone) -ne $before) True
    Check 'untracked kept' (Get-Content -LiteralPath (Join-Path $pair.Clone 'user_scripts\keep.txt') -Raw).Trim() 'keep-me'
    Check 'remote file arrived' (Test-Path -LiteralPath (Join-Path $pair.Clone 'more.txt')) True
    $toastText = ''
    if (Test-Path -LiteralPath $toast) { $toastText = (Get-Content -LiteralPath $toast -Raw).Trim() }
    Check 'toast once' $toastText 'Fusion add-ins updated: Extra Link, SR BOM. Restart Fusion to load them.'
    $rows = @(Repo-Rows $ran.last)
    Check 'one repo row' $rows.Count 1
    Check 'row updated' $rows[0].action 'updated'
    Check 'root is clone' ($rows[0].root -eq $pair.Clone) True
    Check 'log says updated once' (@($ran.out -split "`n" | Where-Object { $_ -match 'updated Extra Link, SR BOM' }).Count) 1

    $pairD = New-Pair 'dirty'
    $dirtyHead = Head-Of $pairD.Clone
    Add-RemoteFile $pairD 'later.txt' 'later'
    Set-Content -LiteralPath (Join-Path $pairD.Clone 'SRBom\addin.py') 'changed'
    $bad = Join-Path $work 'missing-remote-dirty'
    Run-Git $pairD.Clone @('remote', 'set-url', 'origin', $bad) | Out-Null
    $ad = New-AddIns
    Add-Link $ad 'SRBom' (Join-Path $pairD.Clone 'SRBom')
    $ranD = Invoke-Update $ad
    Check 'dirty exit' $ranD.code 0
    Check 'dirty head unchanged' (Head-Of $pairD.Clone) $dirtyHead
    Check 'dirty did not fetch the new file' (Test-Path -LiteralPath (Join-Path $pairD.Clone 'later.txt')) False
    Check 'dirty reason' (@(Repo-Rows $ranD.last)[0].reason) 'dirty'
    Check 'dirty has no toast' (Test-Path -LiteralPath $toast) False

    $pairB = New-Pair 'branch'
    Run-Git $pairB.Clone @('checkout', '-b', 'feature') | Out-Null
    Run-Git $pairB.Clone @('remote', 'set-url', 'origin', (Join-Path $work 'missing-remote-branch')) | Out-Null
    $ab = New-AddIns
    Add-Link $ab 'SRExport' $pairB.Clone
    $ranB = Invoke-Update $ab
    Check 'branch exit' $ranB.code 0
    Check 'branch reason' (@(Repo-Rows $ranB.last)[0].reason) 'not-default-branch'
    Check 'branch no toast' (Test-Path -LiteralPath $toast) False

    $pairU = New-Pair 'upstream'
    Run-Git $pairU.Clone @('branch', '--unset-upstream') | Out-Null
    Run-Git $pairU.Clone @('remote', 'set-url', 'origin', (Join-Path $work 'missing-remote-upstream')) | Out-Null
    $au = New-AddIns
    Add-Link $au 'SRFastener' $pairU.Clone
    $ranU = Invoke-Update $au
    Check 'upstream exit' $ranU.code 0
    Check 'upstream reason' (@(Repo-Rows $ranU.last)[0].reason) 'no-upstream'

    $pairH = New-Pair 'head'
    Run-Git $pairH.Clone @('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD') | Out-Null
    Run-Git $pairH.Clone @('remote', 'set-url', 'origin', (Join-Path $work 'missing-remote-head')) | Out-Null
    $ah = New-AddIns
    Add-Link $ah 'SRDrawingPDF' $pairH.Clone
    $ranH = Invoke-Update $ah
    Check 'default unknown exit' $ranH.code 0
    Check 'default unknown reason' (@(Repo-Rows $ranH.last)[0].reason) 'default-branch-unknown'

    $pairV = New-Pair 'diverged'
    $divHead = Head-Of $pairV.Clone
    Add-RemoteFile $pairV 'remote-only.txt' 'remote'
    Add-LocalFile $pairV.Clone 'local-only.txt' 'local'
    $localHead = Head-Of $pairV.Clone
    $av = New-AddIns
    Add-Link $av 'SRBom' $pairV.Clone
    $ranV = Invoke-Update $av
    Check 'diverged exit' $ranV.code 0
    Check 'diverged reason' (@(Repo-Rows $ranV.last)[0].reason) 'diverged'
    Check 'diverged head stays' (Head-Of $pairV.Clone) $localHead
    Check 'diverged did not take remote file' (Test-Path -LiteralPath (Join-Path $pairV.Clone 'remote-only.txt')) False
    Check 'diverged kept local file' (Test-Path -LiteralPath (Join-Path $pairV.Clone 'local-only.txt')) True
    Check 'diverged no toast' (Test-Path -LiteralPath $toast) False
    if ($divHead -eq $localHead) { Check 'diverged setup moved' False True }

    $pairA = New-Pair 'ahead'
    Add-LocalFile $pairA.Clone 'only-local.txt' 'mine'
    $aheadHead = Head-Of $pairA.Clone
    $aa = New-AddIns
    Add-Link $aa 'SRBom' $pairA.Clone
    $ranA = Invoke-Update $aa
    Check 'ahead exit' $ranA.code 0
    Check 'ahead reason' (@(Repo-Rows $ranA.last)[0].reason) 'ahead'
    Check 'ahead head stays' (Head-Of $pairA.Clone) $aheadHead
    Check 'ahead no toast' (Test-Path -LiteralPath $toast) False

    $pairE = New-Pair 'even'
    $evenHead = Head-Of $pairE.Clone
    $ae = New-AddIns
    Add-Link $ae 'SRBom' $pairE.Clone
    $ranE = Invoke-Update $ae
    Check 'even exit' $ranE.code 0
    Check 'even reason' (@(Repo-Rows $ranE.last)[0].reason) 'not-behind'
    Check 'even head stays' (Head-Of $pairE.Clone) $evenHead
    Check 'even no toast' (Test-Path -LiteralPath $toast) False

    $pairC = New-Pair 'conflict'
    Add-RemoteFile $pairC 'conflict.txt' 'from-remote'
    Set-Content -LiteralPath (Join-Path $pairC.Clone 'conflict.txt') 'local-keep'
    $ac = New-AddIns
    Add-Link $ac 'SRBom' $pairC.Clone
    $ranC = Invoke-Update $ac
    Check 'conflict exit' $ranC.code 1
    Check 'conflict reason' (@(Repo-Rows $ranC.last)[0].reason) 'pull-failed'
    Check 'conflict file kept' (Get-Content -LiteralPath (Join-Path $pairC.Clone 'conflict.txt') -Raw).Trim() 'local-keep'
    Check 'conflict no toast' (Test-Path -LiteralPath $toast) False

    $empty = Join-Path $work 'empty-target'
    New-Item -ItemType Directory -Path $empty | Out-Null
    $an = New-AddIns
    Add-Link $an 'Notes' $empty
    $ranN = Invoke-Update $an
    Check 'not a repo exit' $ranN.code 0
    Check 'not a repo reason' (@(Repo-Rows $ranN.last)[0].reason) 'not-a-git-repo'

    $missing = Join-Path $work 'no-addins-dir'
    $ranM = Invoke-Update $missing
    Check 'missing folder exit' $ranM.code 0
    Check 'missing folder note' ($ranM.out -match 'AddIns folder not found') True
    Check 'missing folder no toast' (Test-Path -LiteralPath $toast) False

    $env:PATH = $logs
    $ranG = Invoke-Update $ae
    Check 'missing git exit' $ranG.code 0
    Check 'missing git note' ($ranG.out -match 'git not found') True
    $env:PATH = $savedPath

    $env:WORKSTATION_FUSION_FAKE_TASK = 'missing'
    $env:WORKSTATION_FUSION_LOG_DIR = (Join-Path $work 'empty-logs')
    New-Item -ItemType Directory -Path $env:WORKSTATION_FUSION_LOG_DIR | Out-Null
    $cleanLines = @(Get-FusionAddinHealthLines)
    Check 'no task is ok' $cleanLines[0].Level 'OK'
    Check 'no task says manual only' ($cleanLines[0].Text -match 'manual only') True
    Check 'clean has no warn' @($cleanLines | Where-Object { $_.Level -eq 'WARN' }).Count 0

    $env:WORKSTATION_FUSION_FAKE_TASK = '{"present":true,"lastResult":0,"lastRun":"2026-11-19T00:00:00Z"}'
    $autoTask = @(Get-FusionAddinHealthLines)
    Check 'a task warns even with result 0' $autoTask[0].Level 'WARN'
    Check 'task warning names the task' ($autoTask[0].Text -match 'Workstation-UpdateFusionAddins') True
    Check 'task warning says it starts on its own' ($autoTask[0].Text -match 'starts on its own') True

    $env:WORKSTATION_FUSION_FAKE_TASK = '{"present":true,"lastResult":267011,"lastRun":""}'
    $never = @(Get-FusionAddinHealthLines)
    Check 'a never-run task still warns' $never[0].Level 'WARN'

    $dirtyJson = Join-Path $env:WORKSTATION_FUSION_LOG_DIR 'fusion-addins-last.json'
    @{ time = '2026-11-19T00:00:00Z'; exitCode = 0; note = ''; updated = @(); repos = @(
        @{ name = 'SR BOM'; root = 'C:\clone'; action = 'skip'; reason = 'dirty'; ahead = 0; behind = 0 }
        @{ name = 'SR Export'; root = 'C:\other'; action = 'skip'; reason = 'diverged'; ahead = 1; behind = 2 }
        @{ name = 'SR Fastener'; root = 'C:\third'; action = 'skip'; reason = 'not-default-branch'; ahead = 0; behind = 0 }
    ) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dirtyJson
    $env:WORKSTATION_FUSION_FAKE_TASK = 'missing'
    $skipLines = @(Get-FusionAddinHealthLines)
    Check 'dirty skip warns' @($skipLines | Where-Object { $_.Text -match 'skipped \(dirty\): SR BOM' -and $_.Level -eq 'WARN' }).Count 1
    Check 'behind warns' @($skipLines | Where-Object { $_.Text -match 'left behind: SR Export' -and $_.Level -eq 'WARN' }).Count 1
    Check 'other branch is not a warn' @($skipLines | Where-Object { $_.Text -match 'not on the default branch' -and $_.Level -eq 'OK' }).Count 1

    $env:WORKSTATION_FUSION_FAKE_TASK = 'missing'
    $env:WORKSTATION_FUSION_LOG_DIR = $logs
    $status = Join-Path $repo 'workstation\health\workstation-status.ps1'
    $statusOut = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $status -NoPause 2>&1
    $statusText = @($statusOut | ForEach-Object { "$_" }) -join "`n"
    Check 'status says manual only' ($statusText -match 'Fusion add-in updater is manual only') True

    $registerRx = '(?<!Un)Register-ScheduledTask|(?<!Un)Register-FusionAddinTask|New-ScheduledTaskTrigger|schtasks'
    Check 'lib has no register function' ([bool](Get-Command Register-FusionAddinTask -ErrorAction SilentlyContinue)) False

    $global:FakeExisting = $null
    $global:Unregistered = $null
    function global:Get-ScheduledTask {
        param($TaskName, $ErrorAction)
        return $global:FakeExisting
    }
    function global:Unregister-ScheduledTask { param($TaskName, [switch]$Confirm) $global:Unregistered = $TaskName }
    $none = Unregister-FusionAddinTask
    Check 'no task to remove is ok' $none.Ok True
    Check 'no task to remove is missing' $none.Missing True
    Check 'no task removes nothing' ($null -eq $global:Unregistered) True
    $global:FakeExisting = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = 'powershell.exe'; Arguments = '-File "C:\other\someone-else.ps1"' }) }
    $foreign = Unregister-FusionAddinTask
    Check 'a foreign task of that name is left alone' $foreign.Ok False
    Check 'foreign task not removed' ($null -eq $global:Unregistered) True
    $global:FakeExisting = [pscustomobject]@{ Actions = @([pscustomobject]@{ Execute = 'powershell.exe'; Arguments = ('-NoProfile -WindowStyle Hidden -File "' + $updater + '"') }) }
    $removed = Unregister-FusionAddinTask
    Check 'old own task removed ok' $removed.Ok True
    Check 'old own task removed by name' $global:Unregistered 'Workstation-UpdateFusionAddins'
    Remove-Item Function:\global:Get-ScheduledTask, Function:\global:Unregister-ScheduledTask -ErrorAction SilentlyContinue

    $install = Get-Content -LiteralPath (Join-Path $repo 'install.ps1') -Raw
    $uninstall = Get-Content -LiteralPath (Join-Path $repo 'uninstall.ps1') -Raw
    $pre = Get-Content -LiteralPath (Join-Path $repo 'preflight.ps1') -Raw
    $installCode = [regex]::Replace($install, '(?s)<#.*?#>', '')
    $installCode = [regex]::Replace($installCode, '(?m)^\s*#.*$', '')
    Check 'install must not register a task' ($installCode -match $registerRx) False
    Check 'install removes an old task' ($installCode -match 'Unregister-FusionAddinTask') True
    Check 'install reads the task read-only on a dry run' ($installCode -match 'Get-FusionAddinTaskStatus') True
    Check 'install skips the task in test mode' ($installCode -match 'not checking scheduled task') True
    Check 'uninstall calls unregister' ($uninstall -match 'Unregister-FusionAddinTask') True
    Check 'uninstall does not register' ($uninstall -match $registerRx) False
    Check 'preflight knows the task' ($pre -match "Workstation-UpdateFusionAddins") True
    Check 'preflight no longer expects the task' ($pre -match "(?s)knownTasks\s*=\s*@\{[^}]*Workstation-UpdateFusionAddins") False
    $plugins = Get-Content -LiteralPath (Join-Path $repo 'install-plugins.ps1') -Raw
    Check 'plugin installer does not schedule' ($plugins -match 'Register-ScheduledTask|Unregister-ScheduledTask') False

    $tk = Import-PowerShellDataFile -LiteralPath (Join-Path $repo 'toolkit.psd1')
    $sc = @($tk.Shortcuts | Where-Object { $_.Name -eq 'Update Fusion add-ins' })
    Check 'one Update Fusion add-ins shortcut' $sc.Count 1
    Check 'shortcut runs the updater' $sc[0].Script 'fusion-addins\update-fusion-addins.ps1'
    Check 'shortcut pauses so the result stays on screen' $sc[0].Args '-Pause'
    $updaterText = Get-Content -LiteralPath $updater -Raw
    Check 'updater has a Pause switch' ($updaterText -match '\[switch\]\$Pause') True

    $libText = Get-Content -LiteralPath $lib -Raw
    $codeOnly = [regex]::Replace($libText, '(?m)^\s*#.*$', '')
    Check 'lib does not register a task' ($codeOnly -match $registerRx) False
    Check 'no git reset call' ($codeOnly -match '(?i)\bgit\b[^\r\n]{0,40}\breset\b') False
    Check 'allow list is the only git verbs' ($libText -match "'status', 'rev-parse', 'symbolic-ref', 'rev-list', 'fetch', 'pull'") True
    foreach ($f in @($lib, $updater, (Join-Path $repo 'install.ps1'), (Join-Path $repo 'uninstall.ps1'), $readme, $rootReadme)) {
        $bytes = [IO.File]::ReadAllBytes($f)
        $high = @($bytes | Where-Object { $_ -gt 127 }).Count
        Check ("ascii " + (Split-Path $f -Leaf)) $high 0
        $text = [IO.File]::ReadAllText($f)
        Check ("no DansPC active path in " + (Split-Path $f -Leaf)) ($text.Contains('C:\projects\active')) False
        Check ("no work-PC active path in " + (Split-Path $f -Leaf)) ($text.Contains('C:\Users\Administrator\projects\active')) False
    }

    function Get-Fences([string]$Text) {
        $blocks = @()
        $lines = $Text -split "`n"
        $i = 0
        while ($i -lt $lines.Count) {
            $line = $lines[$i]
            if ($line.StartsWith('```')) {
                $lang = $line.Substring(3).Trim()
                $body = New-Object System.Collections.Generic.List[string]
                $i++
                while ($i -lt $lines.Count -and -not $lines[$i].StartsWith('```')) { $body.Add($lines[$i]); $i++ }
                $blocks += [pscustomobject]@{ Lang = $lang; Body = @($body) }
            }
            $i++
        }
        return @($blocks)
    }
    function Section-Text([string]$Text, [string]$Heading) {
        $lines = $Text -split "`n"
        $on = $false
        $buf = New-Object System.Collections.Generic.List[string]
        foreach ($line in $lines) {
            if ($line.StartsWith('## ')) {
                if ($on) { break }
                if ($line.Trim() -eq $Heading) { $on = $true; continue }
            } elseif ($on) { $buf.Add($line) }
        }
        return ($buf -join "`n")
    }
    $doc = [IO.File]::ReadAllText($readme)
    foreach ($h in @('## 1. Installer', '## 2. Commands', '## 3. Agent prompt', '## 4. Manual steps')) {
        Check ("readme has " + $h) ($doc.Contains($h)) True
        $sec = Section-Text $doc $h
        Check ($h + ' names the terminal') ($sec -match 'Terminal:') True
        Check ($h + ' names the mode') ($sec -match 'Mode:') True
        Check ($h + ' is not admin') ($sec -match 'not admin') True
        Check ($h + ' has the cd line') ($sec.Contains('cd ((Get-ChildItem')) True
    }
    $psFences = @(Get-Fences $doc | Where-Object { $_.Lang -eq 'powershell' })
    Check 'readme has powershell fences' ($psFences.Count -gt 0) True
    foreach ($block in $psFences) {
        $live = @($block.Body | Where-Object { $_.Trim() })
        Check 'one command per fence' $live.Count 1
        $tokens = $null
        $parseErr = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($live[0], [ref]$tokens, [ref]$parseErr)
        Check 'fence parses' @($parseErr).Count 0
    }
    $manual = Section-Text $doc '## 4. Manual steps'
    foreach ($token in @('Unregister-ScheduledTask', 'update-fusion-addins.ps1', 'Workstation-UpdateFusionAddins')) {
        Check ("manual has " + $token) ($manual.Contains($token)) True
    }
    Check 'readme registers no task' ($doc -match $registerRx) False
    Check 'readme says manual only' ($doc -match 'manual only') True
    Check 'readme names the shortcut' ($doc.Contains('Update Fusion add-ins')) True
    $prompt = Section-Text $doc '## 3. Agent prompt'
    Check 'prompt has installer' ($prompt.Contains('powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1')) True
    Check 'prompt has uninstall' ($prompt.Contains('powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1')) True
    Check 'prompt does not restart Fusion' ($prompt -match 'not restart Fusion|does not restart Fusion') True
    Check 'readme says catalog does not register' ($doc -match 'plugin catalog does not register') True
    $rootDoc = [IO.File]::ReadAllText($rootReadme)
    $rootSec = Section-Text $rootDoc '## Fusion add-in updates'
    Check 'root readme has the section' ($rootSec.Length -gt 0) True
    Check 'root section names the terminal' ($rootSec -match 'Terminal:') True
    Check 'root section names the mode' ($rootSec -match 'Mode:') True
    Check 'root section has cd' ($rootSec.Contains('cd ((Get-ChildItem')) True
    Check 'root section has install' ($rootSec.Contains('powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1')) True
    Check 'root section has the updater' ($rootSec.Contains('powershell -NoProfile -ExecutionPolicy Bypass -File .\workstation\fusion-addins\update-fusion-addins.ps1')) True
    Check 'root section says manual only' ($rootSec -match 'manual only') True
    Check 'root readme does not promise a task' ($rootDoc -match 'every 60 minutes') False
    foreach ($block in @(Get-Fences $rootSec | Where-Object { $_.Lang -eq 'powershell' })) {
        $live = @($block.Body | Where-Object { $_.Trim() })
        Check 'root fence is one line' $live.Count 1
    }
} finally {
    $env:PATH = $savedPath
    if ($null -eq $savedAddins) { Remove-Item Env:WORKSTATION_FUSION_ADDINS -ErrorAction SilentlyContinue } else { $env:WORKSTATION_FUSION_ADDINS = $savedAddins }
    if ($null -eq $savedLog) { Remove-Item Env:WORKSTATION_FUSION_LOG_DIR -ErrorAction SilentlyContinue } else { $env:WORKSTATION_FUSION_LOG_DIR = $savedLog }
    if ($null -eq $savedToast) { Remove-Item Env:WORKSTATION_FUSION_TOAST_SINK -ErrorAction SilentlyContinue } else { $env:WORKSTATION_FUSION_TOAST_SINK = $savedToast }
    if ($null -eq $savedFake) { Remove-Item Env:WORKSTATION_FUSION_FAKE_TASK -ErrorAction SilentlyContinue } else { $env:WORKSTATION_FUSION_FAKE_TASK = $savedFake }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
