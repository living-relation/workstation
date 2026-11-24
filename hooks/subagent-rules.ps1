# SubagentStart hook (Claude Code only). SessionStart additionalContext does not reach a Task-tool
# subagent, so each subagent gets a short form of the memory-store rules and the app lock rules
# (harness.design and Fusion Desktop). Event name and output schema: https://code.claude.com/docs/en/hooks (SubagentStart).
# hookSpecificOutput.hookEventName is "SubagentStart" and additionalContext is the short text.
# Cursor's subagentStart hook can only allow or deny (https://cursor.com/docs/hooks), so this script
# is not wired in hooks/cursor-hooks.json. An unexpected error exits 0 with the loud fail. Never writes.
# Tests set WORKSTATION_INJECT_FAIL to force that path.
. (Join-Path $PSScriptRoot 'state-common.ps1')

function Get-SubagentRulesText {
  $lines = @(
    'rules-inject: workstation-core rules for this subagent (memory store and app locks).'
    'Memory store: live state stays in the repo (STATE.md, this branch''s STATE-<slug>.md, BACKLOG.md, archives/ at the repo root). The shared store holds notes only (preferences, machine facts, gotchas) listed in INDEX.md. Read the repo AGENTS.md, decisions, and STATE before asking. Do not put project status in the store or in a CLAUDE.md. At 80% context, run state-closeout. STATE-<slug>.md is the handoff.'
    'harness.design lock: before driving the harness.design desktop app, acquire the per-PC lock, check in at least every 10 min, and release when done (section 5b of instructions/projects-AGENTS.md). Never delete the lock file by hand. MCP cloud tools do not need the lock. An agent delete goes through the desktop app under the lock.'
    'Fusion Desktop lock: before using local Fusion Desktop (a script in the Fusion app, or driving or clicking the app), acquire the per-PC fusion-desktop lock (its own lock, -Name fusion-desktop), check in at least every 10 min, and release when done (section 5).'
  )
  return ($lines -join "`n")
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  $hookIn = $null
  try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
    $hookIn = Read-StateHookInput
    if ($env:WORKSTATION_INJECT_FAIL) { throw $env:WORKSTATION_INJECT_FAIL }
    $text = Get-SubagentRulesText
    $obj = [ordered]@{
      hookSpecificOutput = [ordered]@{
        hookEventName = 'SubagentStart'
        additionalContext = $text
      }
    }
    [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6))
    exit 0
  } catch {
    Write-RulesNotLoaded -HookInput $hookIn -Reason $_.Exception.Message -EventName 'SubagentStart'
    exit 0
  }
}
