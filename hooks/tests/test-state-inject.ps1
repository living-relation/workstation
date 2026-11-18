# Tests for state-inject.ps1 (SessionStart). Temp repo + fake store only.
# Usage: powershell -NoProfile -File hooks/tests/test-state-inject.ps1  (WORKSTATION_STATE_TOOLS = scripts/state)
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir 'state-inject.ps1'
$t = New-TestRoot 'state-inject'
$store = Join-Path $t 'store'
$repo = New-TestRepo $t 'Inject Repo'
$project = Join-Path $store (Get-TestSlug 'Inject Repo')
Write-TestFile (Join-Path $project 'STATE.md') (Get-GoodState 'main' 'MAIN-GOAL' 0)
Write-TestFile (Join-Path $project 'STATE-feat-x.md') (Get-GoodState 'feat/x' 'BRANCH-GOAL' 0)
$envOk = @{ WORKSTATION_MEMORY_STORE = $store }
function Start-Session([string]$Cwd, [hashtable]$Env) { Invoke-StateHook $hook @{ hook_event_name = 'SessionStart'; cwd = $Cwd } $Env }

$r = Start-Session $repo $envOk
Check 'main: prints root STATE.md' ($r.Out -match 'MAIN-GOAL' -and $r.Out -match 'STATE\.md')
Check 'main: does not print the branch file' ($r.Out -notmatch 'BRANCH-GOAL')
Check 'main: asks for the 3-line confirmation' ($r.Out -match 'confirm in 3 lines' -and $r.Out -match 'Last_Verified_SHA')
Check 'main: exit 0' ($r.Code -eq 0)

[void](Invoke-Git $repo checkout -q -b feat/x)
$r = Start-Session $repo $envOk
Check 'branch: prints STATE-feat-x.md' ($r.Out -match 'BRANCH-GOAL' -and $r.Out -match 'STATE-feat-x\.md')
Check 'branch: does not print root STATE.md' ($r.Out -notmatch 'MAIN-GOAL')

$sub = Join-Path $repo 'docs'
New-Item -ItemType Directory -Force -Path $sub | Out-Null
$r = Start-Session $sub $envOk
Check 'branch: works from a subfolder' ($r.Out -match 'BRANCH-GOAL')

[void](Invoke-Git $repo checkout -q -b feat/new-thing)
$r = Start-Session $repo $envOk
Check 'branch without its file: falls back to STATE.md with a note' ($r.Out -match 'MAIN-GOAL' -and $r.Out -match 'No STATE-feat-new-thing\.md')

$r = Start-Session $repo @{ WORKSTATION_MEMORY_STORE = (Join-Path $t 'no-such-store') }
Check 'store unreachable: silent exit 0' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$plain = Join-Path $t 'not-a-repo'
New-Item -ItemType Directory -Force -Path $plain | Out-Null
$r = Start-Session $plain $envOk
Check 'not a git repo: silent exit 0' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$other = New-TestRepo $t 'unmigrated'
$r = Start-Session $other $envOk
Check 'repo with no project folder: silent exit 0' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$r = Invoke-StateHook $hook $null $envOk
Check 'empty stdin: exit 0' ($r.Code -eq 0)

Remove-TestRoot $t
Complete-StateTest
