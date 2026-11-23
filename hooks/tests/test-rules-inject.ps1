# Tests for rules-inject.ps1 (SessionStart). Temp profile + temp LOCALAPPDATA only; never the real profile.
# Usage: powershell -NoProfile -File hooks/tests/test-rules-inject.ps1
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir 'rules-inject.ps1'
$t = New-TestRoot 'rules-inject'
$home1 = Join-Path $t 'home'
$local = Join-Path $t 'local'
$projects = 'C:\Test Projects'
Write-TestFile (Join-Path $local 'Workstation\workstation.json') (@{ projectsRoot = $projects } | ConvertTo-Json)
$envBase = @{ USERPROFILE = $home1; HOME = $home1; LOCALAPPDATA = $local; WORKSTATION_PROJECTS_ROOT = $null }
function Start-Session([hashtable]$Extra, $Payload) {
  $e = @{}; foreach ($k in $envBase.Keys) { $e[$k] = $envBase[$k] }
  if ($Extra) { foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] } }
  if ($null -eq $Payload) { $Payload = @{ hook_event_name = 'SessionStart'; cwd = $t } }
  Invoke-StateHook $hook $Payload $e
}

$r = Start-Session
Check 'claude: exit 0' ($r.Code -eq 0)
Check 'claude: prints the memory section' ($r.Out -match 'shared-memory:v1' -and $r.Out -match 'Read before you ask')
Check 'claude: prints the harness.design lock rule' ($r.Out -match 'app-locks:v1' -and $r.Out -match 'acquire' -and $r.Out -match 'harness\.design')
Check 'claude: lock commands use app-lock.ps1' ($r.Out -match 'workstation\\app-lock\\app-lock\.ps1')
Check 'claude: placeholders filled from workstation.json' ($r.Out -match [regex]::Escape('C:\Test Projects\_claude') -and $r.Out -notmatch '\{\{')
Check 'claude: project key filled' ($r.Out -match 'C--Test-Projects')
Check 'claude: no Fusion MCP rule' ($r.Out -notmatch 'Fusion')

Write-TestFile (Join-Path $home1 '.claude\CLAUDE.md') "# mine`n<!-- shared-memory:v1 -->`nold`n<!-- /shared-memory:v1 -->`n"
$r = Start-Session
Check 'claude: memory part skipped when CLAUDE.md already has it' ($r.Out -notmatch 'shared-memory:v1' -and $r.Out -match 'app-locks:v1')
Write-TestFile (Join-Path $home1 '.claude\CLAUDE.md') "<!-- shared-memory:v1 -->`n<!-- /shared-memory:v1 -->`n<!-- app-locks:v1 -->`n<!-- /app-locks:v1 -->`n"
$r = Start-Session
Check 'claude: silent when CLAUDE.md has both blocks' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$cursorPayload = @{ hook_event_name = 'sessionStart'; workspace_roots = @($t) }
$r = Start-Session @{ CURSOR_VERSION = '1.7.0' } $cursorPayload
$j = $null; try { $j = $r.Out.Trim() | ConvertFrom-Json } catch { }
Check 'cursor: one additional_context JSON line' ($j -and $j.additional_context)
Check 'cursor: uses the Cursor memory text' ($j -and $j.additional_context -match 'Shared Claude memory' -and $j.additional_context -notmatch 'alwaysApply')
Check 'cursor: includes the lock rule' ($j -and $j.additional_context -match 'app-locks:v1')
Write-TestFile (Join-Path $home1 '.cursor\rules\claude-shared-memory.mdc') "---`nalwaysApply: true`n---`n<!-- shared-memory:v1 -->`nx`n<!-- /shared-memory:v1 -->`n<!-- app-locks:v1 -->`n<!-- /app-locks:v1 -->`n"
$r = Start-Session @{ CURSOR_VERSION = '1.7.0' } $cursorPayload
Check 'cursor: silent when the rule file has both blocks' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)

$r = Start-Session @{ LOCALAPPDATA = (Join-Path $t 'no-local') }
Check 'no projects root: silent exit 0' ($r.Out.Trim() -eq '' -and $r.Code -eq 0)
Remove-Item -LiteralPath (Join-Path $home1 '.claude\CLAUDE.md') -Force
$r = Start-Session @{ LOCALAPPDATA = (Join-Path $t 'no-local'); WORKSTATION_PROJECTS_ROOT = 'D:\P' }
Check 'WORKSTATION_PROJECTS_ROOT wins' ($r.Out -match [regex]::Escape('D:\P\_claude'))

Remove-TestRoot $t
Complete-StateTest
