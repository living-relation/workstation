# cleanup-legacy removes one settings flag and one allow rule, and leaves hooks alone.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$script = Join-Path $repo 'cleanup-legacy.ps1'
$rule = 'Merging pull requests in Daniel''s own GitHub repos (github.com/living-relation/*) is allowed without the user typing an explicit merge instruction, as long as the PR''s required checks have passed or are queued via gh pr merge --auto (via gh pr merge or the GitHub MCP merge tool). This does NOT allow --admin, bypassing branch protection or required checks, force-pushing, --no-verify, or deleting anything other than the merged PR''s own head branch.'
$root = Join-Path ([IO.Path]::GetTempPath()) ("cl-" + [guid]::NewGuid().ToString('N'))
$userDir = Join-Path $root 'home'
$state = Join-Path $root 'state'
New-Item -ItemType Directory -Path (Join-Path $userDir '.claude'), $state, (Join-Path $state 'dashboard') | Out-Null
Set-Content (Join-Path $state 'dashboard\keep.txt') 'x'
$settings = @{
    remoteControlAtStartup = $false
    hooks = @{ Stop = @(@{ hooks = @(@{ command = 'context-guard.ps1' }) }) }
    statusLine = @{ command = 'context-guard.ps1 statusline' }
    autoMode = @{ allow = @('$defaults', $rule, 'keep this other rule') }
}
($settings | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $userDir '.claude\settings.json')
& pwsh -NoProfile -File $script -UserHome $userDir -StateDir $state -CloneRoot $root | Out-Null
if ($LASTEXITCODE -ne 0) { 'FAIL cleanup exit'; exit 1 }
$s = Get-Content (Join-Path $userDir '.claude\settings.json') -Raw | ConvertFrom-Json
$fail = 0
function Check([string]$What, $Got, $Want) { if ("$Got" -eq "$Want") { "PASS $What" } else { "FAIL $What (got '$Got', want '$Want')"; $script:fail++ } }
Check 'flag gone' ($s.PSObject.Properties.Name -contains 'remoteControlAtStartup') False
Check 'other rule kept' (@($s.autoMode.allow) -contains 'keep this other rule') True
Check 'merge rule gone' (@($s.autoMode.allow) -contains $rule) False
Check 'hook kept' ($s.hooks.Stop[0].hooks[0].command) 'context-guard.ps1'
Check 'statusLine kept' $s.statusLine.command 'context-guard.ps1 statusline'
Check 'old folder archived' (Test-Path (Join-Path $state 'dashboard')) False

# Windows PowerShell 5.1 Join-Path accepts only two path arguments.
$tokens = $null; $parseErr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErr)
Check 'cleanup parses' @($parseErr).Count 0
$badJoins = 0
$joins = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Join-Path' }, $true))
foreach ($cmd in $joins) {
    $pos = 0
    $els = @($cmd.CommandElements | Select-Object -Skip 1)
    for ($i = 0; $i -lt $els.Count; $i++) {
        if ($els[$i] -is [System.Management.Automation.Language.CommandParameterAst]) {
            if (($i + 1) -lt $els.Count -and -not ($els[$i + 1] -is [System.Management.Automation.Language.CommandParameterAst])) { $i++ }
            continue
        }
        $pos++
    }
    if ($pos -gt 2) { $badJoins++ }
}
Check 'no three-arg Join-Path' $badJoins 0

function New-CleanupRoot {
    $r = Join-Path ([IO.Path]::GetTempPath()) ("cl-" + [guid]::NewGuid().ToString('N'))
    $u = Join-Path $r 'home'
    $s = Join-Path $r 'state'
    New-Item -ItemType Directory -Path (Join-Path $u '.claude'), $s | Out-Null
    return @{ Root = $r; User = $u; State = $s }
}
$env:WORKSTATION_FAKE_PROCS = 'none'
$w = New-CleanupRoot
$dash = Join-Path $w.State 'dashboard'
New-Item -ItemType Directory -Path $dash | Out-Null
Set-Content (Join-Path $dash 'keep.txt') 'ok'
$locked = Join-Path $dash 'server.log'
Set-Content $locked 'log'
# Hold an exclusive lock so Get-FileHash in the child process fails ("file in use")
# on both Windows and Linux. chmod a-r is not available on Windows and does not
# model a file-in-use skip.
$lockStream = [IO.File]::Open($locked, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try {
  $what = & pwsh -NoProfile -File $script -UserHome $w.User -StateDir $w.State -CloneRoot $w.Root -WhatIf 2>&1
  $whatText = $what -join "`n"
  Check 'whatif exits 0' $LASTEXITCODE 0
  Check 'whatif says not running' ($whatText -match 'not running') True
  Check 'whatif does not invent a stop' ($whatText -match 'WOULD stop') False
  Check 'whatif skips locked log' ($whatText -match 'skipped hash') True
  Check 'whatif leaves dashboard' (Test-Path $dash) True
} finally {
  $lockStream.Close()
}

$dashScript = Join-Path $w.Root 'workstation\dashboard\server.py'
$env:WORKSTATION_FAKE_PROCS = (@{ ProcessId = 42; CommandLine = "python $dashScript" } | ConvertTo-Json -Compress)
$what2 = & pwsh -NoProfile -File $script -UserHome $w.User -StateDir $w.State -CloneRoot $w.Root -WhatIf 2>&1
Check 'whatif names the running server' (($what2 -join "`n") -match 'WOULD stop pid 42') True

$env:WORKSTATION_FAKE_PROCS = 'none'
$m = New-CleanupRoot
$lnkDir = Join-Path $m.Root 'shortcuts\rc'
New-Item -ItemType Directory -Path $lnkDir -Force | Out-Null
Set-Content (Join-Path $lnkDir 'old.lnk') 'x'
& pwsh -NoProfile -File $script -UserHome $m.User -StateDir $m.State -CloneRoot $m.Root | Out-Null
Check 'lnk archive exits 0' $LASTEXITCODE 0
Check 'lnk moved' (Test-Path (Join-Path $lnkDir 'old.lnk')) False
$archived = @(Get-ChildItem -LiteralPath (Join-Path $m.State 'backups') -Recurse -Filter 'old.lnk' -ErrorAction SilentlyContinue)
Check 'lnk archived' $archived.Count 1
Remove-Item Env:WORKSTATION_FAKE_PROCS -ErrorAction SilentlyContinue

if ($fail) { "FAILED: $fail"; exit 1 } else { 'ALL PASS'; exit 0 }
