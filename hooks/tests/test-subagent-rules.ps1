# Tests for subagent-rules.ps1 (Claude Code SubagentStart). Temp folders only.
# Usage: powershell -NoProfile -File hooks/tests/test-subagent-rules.ps1
. (Join-Path $PSScriptRoot 'state-test-support.ps1')
$hook = Join-Path $script:HooksDir 'subagent-rules.ps1'
$repoRoot = (Resolve-Path (Join-Path $script:HooksDir '..')).Path
$payload = @{ hook_event_name = 'SubagentStart'; cwd = $repoRoot; agent_id = 'agent-1'; agent_type = 'general-purpose' }

$r = Invoke-StateHook $hook $payload @{}
$lines = @(Get-OutLines $r.Out)
$d = $null
try { $d = $lines[0] | ConvertFrom-Json } catch { $d = $null }
$ctx = "$($d.hookSpecificOutput.additionalContext)"
Check 'exit 0 and one JSON line' ($r.Code -eq 0 -and $lines.Count -eq 1 -and $d)
Check 'hookEventName is SubagentStart' ($d.hookSpecificOutput.hookEventName -eq 'SubagentStart')
Check 'no systemMessage when the rules loaded' (-not $d.PSObject.Properties['systemMessage'])
Check 'header is rules-inject' ($ctx.StartsWith('rules-inject:'))
Check 'short memory-store rule' ($ctx -match 'notes only' -and $ctx -match 'STATE\.md' -and $ctx -match 'INDEX\.md' -and $ctx -match 'state-closeout')
Check 'short harness.design lock rule' ($ctx -match 'harness\.design' -and $ctx -match 'acquire' -and $ctx -match 'check in' -and $ctx -match 'release' -and $ctx -match 'Never delete the lock file')
Check 'short Fusion Desktop lock rule' ($ctx -match 'fusion-desktop' -and $ctx -notmatch '27182' -and $ctx -notmatch 'Fusion[^\n]*MCP')
Check 'short form has no unfilled placeholder' ($ctx -notmatch '\{\{')
Check 'short form is not the full memory template' ($ctx -notmatch 'autoMemoryDirectory' -and $ctx -notmatch 'shared-memory:v1')

$failLine = 'WORKSTATION RULES NOT LOADED: boom'
$failTell = "Open your reply with this exact line: $failLine"
$r = Invoke-StateHook $hook $payload @{ WORKSTATION_INJECT_FAIL = 'boom' }
$d = $null; try { $d = $r.Out.Trim() | ConvertFrom-Json } catch { }
Check 'error: loud fail names SubagentStart' ($r.Code -eq 0 -and $d.systemMessage -eq $failLine -and $d.hookSpecificOutput.hookEventName -eq 'SubagentStart' -and $d.hookSpecificOutput.additionalContext -eq $failTell)

$hooksJson = Get-Content -LiteralPath (Join-Path $script:HooksDir 'hooks.json') -Raw | ConvertFrom-Json
$subCmd = ''
foreach ($entry in @($hooksJson.hooks.SubagentStart)) {
  foreach ($item in @($entry.hooks)) { if ($item.command -match 'subagent-rules\.ps1') { $subCmd = [string]$item.command } }
}
Check 'hooks.json SubagentStart runs through run-ps.sh' ($subCmd -match '^sh "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/run-ps\.sh" ' -and $subCmd -match 'subagent-rules\.ps1')
$cursorText = Get-Content -LiteralPath (Join-Path $script:HooksDir 'cursor-hooks.json') -Raw
Check 'cursor hooks have no subagent rules hook' ($cursorText -notmatch 'subagent-rules' -and $cursorText -notmatch 'subagentStart')

$paste = "If you don't see a 'rules-inject:' header at the start, say so first."
foreach ($name in @('instructions-for-claude.md', 'cowork-global-instructions.md')) {
  $text = Get-Content -LiteralPath (Join-Path (Join-Path $repoRoot 'instructions') $name) -Raw
  Check "paste check is in $name" ($text.Contains($paste))
}

Complete-StateTest
