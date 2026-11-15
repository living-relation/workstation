# cleanup-legacy removes one settings flag and one allow rule, and leaves hooks alone.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$script = Join-Path $repo 'cleanup-legacy.ps1'
$rule = 'Merging pull requests in Daniel''s own GitHub repos (github.com/living-relation/*) is allowed without the user typing an explicit merge instruction, as long as the PR''s required checks have passed or are queued via gh pr merge --auto (via gh pr merge or the GitHub MCP merge tool). This does NOT allow --admin, bypassing branch protection or required checks, force-pushing, --no-verify, or deleting anything other than the merged PR''s own head branch.'
$root = Join-Path ([IO.Path]::GetTempPath()) ("cl-" + [guid]::NewGuid().ToString('N'))
$userDir = Join-Path $root 'home'
$state = Join-Path $root 'state'
New-Item -ItemType Directory -Path (Join-Path $userDir '.claude'), $state, (Join-Path $state 'desktop-commander-remote'), (Join-Path $state 'dashboard') | Out-Null
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
Check 'phone remote state kept' (Test-Path (Join-Path $state 'desktop-commander-remote')) True
Check 'old folder archived' (Test-Path (Join-Path $state 'dashboard')) False
if ($fail) { exit 1 } else { 'ALL PASS'; exit 0 }
