# Tests the source-of-truth hooks: sot-after-edit.ps1 (Claude PostToolUse, Cursor postToolUse),
# protected-files-guard.ps1 reading .claude/sot.json, and the git pre-commit sot_guard.py check.
# Fixture: a temp repo with a CSV SoT, a checker that fails on the value BAD, and a generated file.
# Fake store only. Usage: powershell -NoProfile -File hooks/tests/test-state-sot-hooks.ps1
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$after = Join-Path $script:HooksDir 'sot-after-edit.ps1'
$guard = Join-Path $script:HooksDir 'protected-files-guard.ps1'
$pack = Join-Path $script:HooksDir 'git'
$t = New-TestRoot 'state-sot'
$store = Join-Path $t 'store'
$saved = @{ store = $env:WORKSTATION_MEMORY_STORE; tools = $env:WORKSTATION_STATE_TOOLS }
$env:WORKSTATION_MEMORY_STORE = $store
$env:WORKSTATION_STATE_TOOLS = $script:StateTools
$claude = @{ WORKSTATION_MEMORY_STORE = $store }
$cursor = @{ WORKSTATION_MEMORY_STORE = $store; CURSOR_VERSION = '1.7.0' }
$py = (Get-Command python -CommandType Application | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1).Source
$checker = "import csv, sys`nrows = list(csv.reader(open(sys.argv[1], encoding='utf-8')))`nsys.exit(1 if any('BAD' in r for r in rows[1:]) else 0)`n"
$goodCsv = "circuit,from,to`nC1,A1,B1`nC2,A2,B2`n"

function New-SotRepo([string]$Name, [string]$HooksPath) {
  $repo = New-TestRepo $t $Name $HooksPath
  Write-TestFile (Join-Path $repo 'tools\check_csv.py') $checker
  Write-TestFile (Join-Path $repo 'data\master.csv') $goodCsv
  Write-TestFile (Join-Path $repo 'generated\list.txt') "C1`nC2`n"
  $registry = [ordered]@{ entries = @([ordered]@{
        name = 'wirelist'; paths = @('data/master.csv'); report = 'cells'
        checks = @([ordered]@{ run = "`"$py`" tools/check_csv.py data/master.csv"; fast = $true })
        regenerate = @("`"$py`" tools/build.py"); derived = @('generated/**') }) }
  Write-TestFile (Join-Path $repo '.claude\sot.json') ($registry | ConvertTo-Json -Depth 6)
  [void](Invoke-Git $repo add -A)
  [void](Invoke-Git $repo commit -q -m sot-base)
  return $repo
}

function Get-Json($Result) {
  $lines = Get-OutLines $Result.Out
  if ($lines.Count -ne 1) { return $null }
  try { return ($lines[0] | ConvertFrom-Json) } catch { return $null }
}

try {
  $repo = New-SotRepo 'sot-repo'
  $csv = Join-Path $repo 'data\master.csv'
  function After-Edit([string]$Path, [hashtable]$Env) {
    Invoke-StateHook $after @{ hook_event_name = 'PostToolUse'; tool_name = 'Edit'; cwd = $repo; tool_input = @{ file_path = $Path } } $Env
  }

  Write-TestFile $csv "circuit,from,to`nC1,A1,B9`nC2,A2,B2`n"
  $r = After-Edit $csv $claude
  $d = Get-Json $r
  $ctx = "$($d.hookSpecificOutput.additionalContext)"
  Check 'after-edit (claude): good value returns PostToolUse additionalContext' ($r.Code -eq 0 -and $d.hookSpecificOutput.hookEventName -eq 'PostToolUse' -and $ctx -match 'PASS')
  Check 'after-edit (claude): lists the changed cell' ($ctx -match "row 2 to: 'B1' -> 'B9'")
  Check 'after-edit (claude): pass has no systemMessage' (-not $d.PSObject.Properties['systemMessage'])

  Write-TestFile $csv "circuit,from,to`nC1,A1,BAD`nC2,A2,B2`n"
  $r = After-Edit $csv $claude
  $d = Get-Json $r
  Check 'after-edit (claude): bad value is loud (systemMessage) and never blocks (exit 0)' ($r.Code -eq 0 -and "$($d.systemMessage)" -match 'SOT CHECK FAILED' -and "$($d.hookSpecificOutput.additionalContext)" -match 'FAIL')
  $r = After-Edit $csv $cursor
  $d = Get-Json $r
  Check 'after-edit (cursor): result goes to additional_context' ($r.Code -eq 0 -and "$($d.additional_context)" -match 'SOT CHECK FAILED' -and $r.Out -notmatch 'hookSpecificOutput')

  Write-TestFile (Join-Path $repo 'generated\list.txt') "hand edit`n"
  $d = Get-Json (After-Edit (Join-Path $repo 'generated\list.txt') $claude)
  Check 'after-edit: hand-edited derived file warns' ("$($d.systemMessage)" -match 'SOT WARNING' -and "$($d.hookSpecificOutput.additionalContext)" -match 'build.py')
  [void](Invoke-Git $repo checkout -q -- .)

  $r = After-Edit (Join-Path $repo 'README.md') $claude
  Check 'after-edit: unlisted file is silent' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
  $r = After-Edit (Join-Path $t 'loose.txt') $claude
  Check 'after-edit: file outside a repo is silent' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')
  $r = Invoke-StateHook $after $null $claude
  Check 'after-edit: empty input is silent' ($r.Code -eq 0 -and $r.Out.Trim() -eq '')

  function Guard-Edit([string]$Path, [hashtable]$Env) {
    Invoke-StateHook $guard @{ hook_event_name = 'PreToolUse'; tool_name = 'Edit'; cwd = $repo; tool_input = @{ file_path = $Path } } $Env
  }
  $d = Get-Json (Guard-Edit $csv $claude)
  $why = "$($d.hookSpecificOutput.permissionDecisionReason)"
  Check 'guard (claude): SoT in sot.json asks' ($d.hookSpecificOutput.permissionDecision -eq 'ask' -and $why -match "entry 'wirelist'")
  Check 'guard: message names the fast check and the commit check' ($why -match 'check_csv.py' -and $why -match 'sot_guard.py check')
  $d = Get-Json (Guard-Edit $csv $cursor)
  Check 'guard (cursor): SoT is allow plus a warning' ($d.permission -eq 'allow' -and "$($d.agent_message)" -match 'explicit yes' -and "$($d.agent_message)" -match 'check_csv.py')
  $d = Get-Json (Guard-Edit (Join-Path $repo '.claude\sot.json') $claude)
  Check 'guard: the registry itself asks' ($d.hookSpecificOutput.permissionDecision -eq 'ask' -and "$($d.hookSpecificOutput.permissionDecisionReason)" -match 'lint-registry')
  $r = Guard-Edit (Join-Path $repo 'generated\list.txt') $claude
  Check 'guard: derived file is not an ask (the after-edit hook warns)' ($r.Out.Trim() -eq '')
  $r = Guard-Edit (Join-Path $repo 'README.md') $claude
  Check 'guard: unlisted file stays silent' ($r.Out.Trim() -eq '')

  $hooked = New-SotRepo 'sot-pack-repo' $pack
  function Get-Count { [int]((Invoke-Git $hooked rev-list --count HEAD).Out.Trim()) }
  Write-TestFile (Join-Path $hooked 'data\master.csv') "circuit,from,to`nC1,A1,BAD`nC2,A2,B2`n"
  [void](Invoke-Git $hooked add -A)
  $before = Get-Count
  $c = Invoke-Git $hooked commit -q -m 'bad value'
  Check 'pre-commit: a SoT that fails its check blocks the commit' ($c.Code -ne 0 -and (Get-Count) -eq $before -and $c.Out -match 'FAIL')
  Write-TestFile (Join-Path $hooked 'data\master.csv') "circuit,from,to`nC1,A1,B5`nC2,A2,B2`n"
  [void](Invoke-Git $hooked add -A)
  $c = Invoke-Git $hooked commit -q -m 'good value'
  Check 'pre-commit: a SoT that passes commits' ($c.Code -eq 0 -and (Get-Count) -eq ($before + 1))
  Write-TestFile (Join-Path $hooked 'generated\list.txt') "hand edit`n"
  [void](Invoke-Git $hooked add -A)
  $before = Get-Count
  $c = Invoke-Git $hooked commit -q -m 'hand edit of generated file'
  Check 'pre-commit: a hand-edited derived file blocks the commit' ($c.Code -ne 0 -and (Get-Count) -eq $before -and $c.Out -match 'never hand-edited')
} finally {
  $env:WORKSTATION_MEMORY_STORE = $saved.store
  $env:WORKSTATION_STATE_TOOLS = $saved.tools
  Remove-TestRoot $t
}
Complete-StateTest
