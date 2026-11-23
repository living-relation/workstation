# Tests for state-lint-stop.ps1 (Stop). Temp repo only; live state sits at the repo root.
# Usage: powershell -NoProfile -File hooks/tests/test-state-lint-stop.ps1  (WORKSTATION_STATE_TOOLS = scripts/state)
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir 'state-lint-stop.ps1'
$t = New-TestRoot 'state-stop'
$repo = New-TestRepo $t 'stop-repo'
$project = $repo
$root = Join-Path $project 'STATE.md'
$envOk = @{}
function Stop-Session([hashtable]$Extra, [hashtable]$Env) {
  $payload = @{ hook_event_name = 'Stop'; cwd = $repo; stop_hook_active = $false }
  if ($Extra) { foreach ($k in $Extra.Keys) { $payload[$k] = $Extra[$k] } }
  Invoke-StateHook $hook $payload $Env
}

Write-TestFile $root (Get-GoodState 'main' 'GOAL' 0)
$r = Stop-Session $null $envOk
Check 'good STATE: exit 0, quiet' ($r.Code -eq 0 -and $r.Err.Trim() -eq '' -and $r.Out.Trim() -eq '')

Write-TestFile $root (Get-GoodState 'main' 'GOAL' 10)
Check 'fixture is 31 lines' (@([IO.File]::ReadAllLines($root)).Count -eq 31)
$r = Stop-Session $null $envOk
Check '31-line STATE: exit 2' ($r.Code -eq 2)
Check '31-line STATE: problem on stderr' ($r.Err -match '31 lines' -and $r.Err -match 'state-lint-stop')
Check '31-line STATE: nothing on stdout' ($r.Out.Trim() -eq '')

$r = Stop-Session @{ stop_hook_active = $true } $envOk
Check 'stop_hook_active: exit 0 (no loop)' ($r.Code -eq 0 -and $r.Err.Trim() -eq '')

Write-TestFile $root ((Get-GoodState 'main' 'GOAL' 0) -replace '\[NEXT\] Do', '[NEXT] (carried 2) Do')
$r = Stop-Session $null $envOk
Check '2-run rule: exit 2' ($r.Code -eq 2 -and $r.Err -match 'carried 2')

$r = Stop-Session $null @{ WORKSTATION_MEMORY_STORE = (Join-Path $t 'no-such-store') }
Check 'notes store unreachable: the repo STATE is still linted' ($r.Code -eq 2)

Remove-Item -LiteralPath $root -Force
$r = Stop-Session $null $envOk
Check 'repo has no STATE.md (not migrated): exit 0' ($r.Code -eq 0 -and $r.Err.Trim() -eq '')

Write-TestFile (Join-Path $project 'STATE-someone-else.md') (Get-GoodState 'someone/else' 'X' 12)
Write-TestFile $root (Get-GoodState 'main' 'GOAL' 0)
$r = Stop-Session $null $envOk
Check "another branch's bad file does not block this session" ($r.Code -eq 0)

[void](Invoke-Git $repo checkout -q -b feat/lint)
Write-TestFile (Join-Path $project 'STATE-feat-lint.md') (Get-GoodState 'feat/lint' 'GOAL' 10)
$r = Stop-Session $null $envOk
Check 'branch: its own STATE-feat-lint.md is linted (exit 2)' ($r.Code -eq 2 -and $r.Err -match 'STATE-feat-lint\.md')

$r = Stop-Session @{ hook_event_name = 'stop'; status = 'completed'; loop_count = 0 } @{ CURSOR_VERSION = '1.7.0' }
$lines = Get-OutLines $r.Out
$obj = $null
try { $obj = $lines[0] | ConvertFrom-Json } catch { }
Check 'cursor: violation prints one followup_message line, exit 0' ($r.Code -eq 0 -and $lines.Count -eq 1 -and $obj.followup_message -match '31 lines')
$r = Stop-Session @{ hook_event_name = 'stop'; status = 'completed'; loop_count = 1 } @{ CURSOR_VERSION = '1.7.0' }
Check 'cursor: loop_count 1 stays quiet' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')

$plain = Join-Path $t 'plain'
New-Item -ItemType Directory -Force -Path $plain | Out-Null
$r = Invoke-StateHook $hook @{ hook_event_name = 'Stop'; cwd = $plain } $envOk
Check 'not a git repo: exit 0' ($r.Code -eq 0)

Remove-TestRoot $t
Complete-StateTest
