# Tests for protected-files-guard.ps1 (PreToolUse, Claude Code and Cursor). Temp repo + fake store only.
# Usage: powershell -NoProfile -File hooks/tests/test-state-protected-files-guard.ps1  (WORKSTATION_STATE_TOOLS = scripts/state)
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir 'protected-files-guard.ps1'
$t = New-TestRoot 'state-guard'
$store = Join-Path $t 'store'
$repo = New-TestRepo $t 'guard-repo'
$project = Join-Path $store 'guard-repo'
Write-TestFile (Join-Path $project 'STATE.md') (Get-GoodState 'main' 'GOAL' 0)
Write-TestFile (Join-Path $repo 'SPEC.md') "# Spec`n"
Write-TestFile (Join-Path $repo 'docs\out.txt') "verified`n"
Write-TestFile (Join-Path $repo 'VERIFIED.lock') '{"docs/out.txt": "0000000000000000000000000000000000000000000000000000000000000000"}'
Write-TestFile (Join-Path $repo '.claude\protected-paths.txt') "# owner-approved edits only`ndocs/harness/MASTER-wirelist.csv`nsot/**`n"
[void](Invoke-Git $repo checkout -q -b feat/x)
$claude = @{ WORKSTATION_MEMORY_STORE = $store }
$cursor = @{ WORKSTATION_MEMORY_STORE = $store; CURSOR_VERSION = '1.7.0' }
function Edit-File([string]$Path, [hashtable]$Env, [string]$Tool = 'Edit') {
  Invoke-StateHook $hook @{ hook_event_name = 'PreToolUse'; tool_name = $Tool; cwd = $repo; tool_input = @{ file_path = $Path; old_string = 'a'; new_string = 'b' } } $Env
}
function Run-Shell([string]$Command, [hashtable]$Env) {
  Invoke-StateHook $hook @{ hook_event_name = 'PreToolUse'; tool_name = 'Bash'; cwd = $repo; tool_input = @{ command = $Command } } $Env
}
function Get-Decision($Result) {
  $lines = Get-OutLines $Result.Out
  if ($lines.Count -ne 1) { return $null }
  try { return ($lines[0] | ConvertFrom-Json) } catch { return $null }
}
function Test-Asks($Result) { $d = Get-Decision $Result; return ($Result.Code -eq 0 -and $d -and $d.hookSpecificOutput.permissionDecision -eq 'ask' -and $d.hookSpecificOutput.hookEventName -eq 'PreToolUse') }
function Test-Denies($Result) { $d = Get-Decision $Result; return ($Result.Code -eq 0 -and $d -and $d.hookSpecificOutput.permissionDecision -eq 'deny') }
function Test-Silent($Result) { return ($Result.Code -eq 0 -and $Result.Out.Trim() -eq '') }

Check 'SPEC.md edit asks' (Test-Asks (Edit-File (Join-Path $repo 'SPEC.md') $claude))
Check 'SPEC.md by relative path asks' (Test-Asks (Edit-File 'SPEC.md' $claude 'Write'))
Check 'docs/SPEC-api.md asks' (Test-Asks (Edit-File (Join-Path $repo 'docs\SPEC-api.md') $claude 'Write'))
Check 'VERIFIED.lock file asks' (Test-Asks (Edit-File (Join-Path $repo 'docs\out.txt') $claude))
Check 'protected-paths exact entry asks' (Test-Asks (Edit-File (Join-Path $repo 'docs\harness\MASTER-wirelist.csv') $claude))
Check 'protected-paths sot/** asks (nested)' (Test-Asks (Edit-File (Join-Path $repo 'sot\a\channels.csv') $claude 'Write'))
Check 'ordinary file is silent (normal permission flow)' (Test-Silent (Edit-File (Join-Path $repo 'docs\notes.md') $claude))
Check 'SPECIAL.md is not a SPEC file' (Test-Silent (Edit-File (Join-Path $repo 'SPECIAL.md') $claude 'Write'))
Check 'file outside any repo is silent' (Test-Silent (Edit-File (Join-Path $t 'loose.md') $claude 'Write'))

Check 'deliverable_lock unlock command asks' (Test-Asks (Run-Shell 'python scripts/state/deliverable_lock.py unlock docs/out.txt --confirm 00000000' $claude))
Check 'deliverable_lock --repo . unlock asks' (Test-Asks (Run-Shell 'py -3 deliverable_lock.py --repo . unlock x --confirm 1' $claude))
Check 'deliverable_lock verify is silent' (Test-Silent (Run-Shell 'python scripts/state/deliverable_lock.py verify' $claude))
Check 'other shell command is silent' (Test-Silent (Run-Shell 'git status' $claude))

Check "other branch's STATE-<slug>.md is denied" (Test-Denies (Edit-File (Join-Path $project 'STATE-feat-y.md') $claude 'Write'))
Check "another project's STATE-<slug>.md is denied" (Test-Denies (Edit-File (Join-Path $store 'other-proj\STATE-feat-x.md') $claude 'Write'))
Check 'own STATE-feat-x.md is allowed' (Test-Silent (Edit-File (Join-Path $project 'STATE-feat-x.md') $claude 'Write'))
Check 'root STATE.md is not judged here' (Test-Silent (Edit-File (Join-Path $project 'STATE.md') $claude))
Check 'archives\STATE-old.md is allowed' (Test-Silent (Edit-File (Join-Path $project 'archives\STATE-feat-y-20261118.md') $claude 'Write'))
Check 'STATE-x.md inside a repo is not a store file' (Test-Silent (Edit-File (Join-Path $repo 'notes\STATE-feat-y.md') $claude 'Write'))

$r = Edit-File (Join-Path $repo 'docs\notes.md') $cursor
Check 'cursor: allow prints exactly one {"permission":"allow"} line' ($r.Code -eq 0 -and (Get-OutLines $r.Out).Count -eq 1 -and $r.Out.Trim() -eq '{"permission":"allow"}')
$r = Edit-File (Join-Path $repo 'SPEC.md') $cursor
$d = Get-Decision $r
Check 'cursor: ask prints exactly one permission line (ask)' ($d -and $d.permission -eq 'ask' -and (Get-OutLines $r.Out).Count -eq 1)
$r = Edit-File (Join-Path $project 'STATE-feat-y.md') $cursor 'Write'
$d = Get-Decision $r
Check 'cursor: deny prints exactly one permission line (deny)' ($d -and $d.permission -eq 'deny' -and (Get-OutLines $r.Out).Count -eq 1)
$r = Run-Shell 'git status' $cursor
Check 'cursor: shell allow prints exactly one line' ($r.Out.Trim() -eq '{"permission":"allow"}')
$r = Invoke-StateHook $hook $null $cursor
Check 'cursor: empty input still prints the allow line' ($r.Out.Trim() -eq '{"permission":"allow"}' -and $r.Code -eq 0)

Remove-TestRoot $t
Complete-StateTest
