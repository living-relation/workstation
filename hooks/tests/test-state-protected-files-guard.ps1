# Tests for protected-files-guard.ps1 (PreToolUse, Claude Code and Cursor). Temp repos only; live state sits at each worktree root.
# Usage: powershell -NoProfile -File hooks/tests/test-state-protected-files-guard.ps1  (WORKSTATION_STATE_TOOLS = scripts/state)
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir 'protected-files-guard.ps1'
$t = New-TestRoot 'state-guard'
$repo = New-TestRepo $t 'guard-repo'
$project = $repo
Write-TestFile (Join-Path $project 'STATE.md') (Get-GoodState 'main' 'GOAL' 0)
Write-TestFile (Join-Path $repo 'SPEC.md') "# Spec`n"
Write-TestFile (Join-Path $repo 'docs\out.txt') "verified`n"
Write-TestFile (Join-Path $repo 'VERIFIED.lock') '{"docs/out.txt": "0000000000000000000000000000000000000000000000000000000000000000", "_history": [{"date": "2026-01-01T00:00:00Z", "action": "lock", "path": "docs/out.txt"}]}'
Write-TestFile (Join-Path $repo '.claude\protected-paths.txt') "# owner-approved edits only`ndocs/harness/MASTER-wirelist.csv`nsot/**`n"
[void](Invoke-Git $repo checkout -q -b feat/x)
$claude = @{}
$cursor = @{ CURSOR_VERSION = '1.7.0' }
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
Check 'VERIFIED.lock _history key is not a locked path' (Test-Silent (Edit-File (Join-Path $repo '_history') $claude 'Write'))
Check 'ordinary file is silent (normal permission flow)' (Test-Silent (Edit-File (Join-Path $repo 'docs\notes.md') $claude))
Check 'SPECIAL.md is not a SPEC file' (Test-Silent (Edit-File (Join-Path $repo 'SPECIAL.md') $claude 'Write'))
Check 'file outside any repo is silent' (Test-Silent (Edit-File (Join-Path $t 'loose.md') $claude 'Write'))

Check 'deliverable_lock unlock command asks' (Test-Asks (Run-Shell 'python scripts/state/deliverable_lock.py unlock docs/out.txt --owner-phrase "yes unlock it"' $claude))
Check 'deliverable_lock --repo . unlock asks' (Test-Asks (Run-Shell 'py -3 deliverable_lock.py --repo . unlock x --owner-phrase ok' $claude))
Check 'deliverable_lock unlock without a phrase still asks' (Test-Asks (Run-Shell 'python deliverable_lock.py unlock docs/out.txt' $claude))
Check 'deliverable_lock verify is silent' (Test-Silent (Run-Shell 'python scripts/state/deliverable_lock.py verify' $claude))
Check 'other shell command is silent' (Test-Silent (Run-Shell 'git status' $claude))

Check "other branch's STATE-<slug>.md is denied" (Test-Denies (Edit-File (Join-Path $project 'STATE-feat-y.md') $claude 'Write'))
$otherRepo = New-TestRepo $t 'other-proj'
Check "another repo's STATE-<slug>.md is not this guard's (silent)" (Test-Silent (Edit-File (Join-Path $otherRepo 'STATE-feat-z.md') $claude 'Write'))
$wt = Join-Path $t 'guard-wt'
[void](Invoke-Git $repo worktree add -q -b feat/w (($wt) -replace '\\', '/'))
Check "a sibling worktree's STATE-<slug>.md is denied" (Test-Denies (Edit-File (Join-Path $wt 'STATE-feat-w.md') $claude 'Write'))
Check "a sibling worktree's root STATE.md asks" (Test-Asks (Edit-File (Join-Path $wt 'STATE.md') $claude))
Check 'own STATE-feat-x.md is allowed' (Test-Silent (Edit-File (Join-Path $project 'STATE-feat-x.md') $claude 'Write'))
Check 'branch session: root STATE.md asks (one writer)' (Test-Asks (Edit-File (Join-Path $project 'STATE.md') $claude))
Check 'VERIFIED.lock itself asks (Edit)' (Test-Asks (Edit-File (Join-Path $repo 'VERIFIED.lock') $claude))
Check 'VERIFIED.lock itself asks (Write, relative path)' (Test-Asks (Edit-File 'VERIFIED.lock' $claude 'Write'))
$r = Edit-File (Join-Path $repo 'SPEC.md') $claude
Check 'claude: ask JSON has no Cursor keys' ($r.Out -notmatch '"permission"' -and $r.Out -notmatch 'user_message')
$plainRepo = New-TestRepo $t 'unmigrated-repo'
Write-TestFile (Join-Path $plainRepo 'SPEC.md') "# Spec`n"
Check 'unmigrated repo: SPEC.md edit is silent' (Test-Silent (Invoke-StateHook $hook @{ hook_event_name = 'PreToolUse'; tool_name = 'Edit'; cwd = $plainRepo; tool_input = @{ file_path = (Join-Path $plainRepo 'SPEC.md'); old_string = 'a'; new_string = 'b' } } $claude))
[void](Invoke-Git $repo checkout -q main)
Check 'trunk session: root STATE.md is allowed' (Test-Silent (Edit-File (Join-Path $project 'STATE.md') $claude))
[void](Invoke-Git $repo checkout -q feat/x)
Check 'archives\STATE-old.md is allowed' (Test-Silent (Edit-File (Join-Path $project 'archives\STATE-feat-y-20261118.md') $claude 'Write'))
Check 'STATE-x.md in a repo subfolder is not a state file' (Test-Silent (Edit-File (Join-Path $repo 'notes\STATE-feat-y.md') $claude 'Write'))

$r = Edit-File (Join-Path $repo 'docs\notes.md') $cursor
Check 'cursor: allow prints exactly one {"permission":"allow"} line' ($r.Code -eq 0 -and (Get-OutLines $r.Out).Count -eq 1 -and $r.Out.Trim() -eq '{"permission":"allow"}')
$r = Edit-File (Join-Path $repo 'SPEC.md') $cursor
$d = Get-Decision $r
Check 'cursor: an ask is sent as allow plus a warning (no hard block), one line' ($d -and $d.permission -eq 'allow' -and "$($d.agent_message)" -match 'SPEC' -and (Get-OutLines $r.Out).Count -eq 1)
Check 'cursor: the warning asks for the owner''s explicit yes in chat' ("$($d.agent_message)" -match 'explicit yes' -and "$($d.user_message)" -match 'explicit yes')
Check 'cursor: the warning asks for a report of changed values' ("$($d.agent_message)" -match 'report every changed value')
Check 'cursor: the warning names the checks that will run' ("$($d.agent_message)" -match 'Checks: .*pre-commit')
Check 'cursor: no hookSpecificOutput key' ($r.Out -notmatch 'hookSpecificOutput')
$r = Invoke-StateHook $hook @{ hook_event_name = 'preToolUse'; tool_name = 'Delete'; cwd = $repo; tool_input = @{ path = (Join-Path $repo 'VERIFIED.lock') } } $cursor
$d = Get-Decision $r
Check 'cursor: Delete of VERIFIED.lock is allowed with a warning naming deliverable_lock verify' ($d -and $d.permission -eq 'allow' -and "$($d.agent_message)" -match 'deliverable_lock.py verify')
$r = Edit-File (Join-Path $repo 'docs\out.txt') $cursor
$d = Get-Decision $r
Check 'cursor: locked deliverable is allowed with a warning, never denied' ($d -and $d.permission -eq 'allow' -and "$($d.agent_message)" -match 'VERIFIED.lock')
$r = Edit-File (Join-Path $repo 'sot\a\channels.csv') $cursor 'Write'
$d = Get-Decision $r
Check 'cursor: protected-paths entry is allowed with a warning' ($d -and $d.permission -eq 'allow' -and "$($d.agent_message)" -match 'protected-paths.txt')
$r = Edit-File (Join-Path $project 'STATE.md') $cursor
$d = Get-Decision $r
Check 'cursor: root STATE from a branch is allowed with a warning naming state_lint' ($d -and $d.permission -eq 'allow' -and "$($d.agent_message)" -match 'state_lint')
$r = Invoke-StateHook $hook @{ hook_event_name = 'preToolUse'; tool_name = 'Shell'; cwd = $repo; tool_input = @{ command = 'python deliverable_lock.py unlock docs/out.txt --owner-phrase ok' } } $cursor
$d = Get-Decision $r
Check 'cursor preToolUse: unlock shell is allowed with a warning' ($d -and $d.permission -eq 'allow' -and "$($d.agent_message)" -match 'unlocks a verified deliverable')
$r = Invoke-StateHook $hook @{ hook_event_name = 'beforeShellExecution'; command = 'python scripts/state/deliverable_lock.py unlock docs/out.txt --owner-phrase "yes"'; cwd = $repo } $cursor
$d = Get-Decision $r
Check 'cursor beforeShellExecution: unlock asks (enforced there), one line' ($d -and $d.permission -eq 'ask' -and (Get-OutLines $r.Out).Count -eq 1 -and "$($d.user_message)" -match 'owner')
$r = Invoke-StateHook $hook @{ hook_event_name = 'beforeShellExecution'; command = 'python scripts/state/deliverable_lock.py verify'; cwd = $repo } $cursor
Check 'cursor beforeShellExecution: deliverable_lock verify is allowed' ($r.Out.Trim() -eq '{"permission":"allow"}')
$r = Edit-File (Join-Path $repo 'SPEC.md') $claude
Check 'claude: ask names the checks that will run' ($r.Out -match 'Checks: ')
$r = Edit-File (Join-Path $repo 'docs\out.txt') $claude
Check 'claude: locked deliverable asks, never denies' (Test-Asks $r)
$r = Edit-File (Join-Path $project 'STATE-feat-y.md') $cursor 'Write'
$d = Get-Decision $r
Check 'cursor: deny prints exactly one permission line (deny)' ($d -and $d.permission -eq 'deny' -and (Get-OutLines $r.Out).Count -eq 1)
$r = Run-Shell 'git status' $cursor
Check 'cursor: shell allow prints exactly one line' ($r.Out.Trim() -eq '{"permission":"allow"}')
$r = Invoke-StateHook $hook $null $cursor
Check 'cursor: empty input still prints the allow line' ($r.Out.Trim() -eq '{"permission":"allow"}' -and $r.Code -eq 0)

Remove-TestRoot $t
Complete-StateTest
