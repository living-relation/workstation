# PostToolUse nudge (2026-10-28): after a shell call that ran `gh pr create` and printed a
# PR URL, or a GitHub-MCP create_pull_request, tell the agent to run the pr-closeout skill
# (state file on the same PR branch; memory only for preferences, rules and
# cross-project facts; hygiene). One script for Claude Code
# (tools Bash / PowerShell) and Cursor (postToolUse, tool Shell). Never blocks. Prints "{}" when it has nothing to say, because
# Cursor treats an empty reply as invalid JSON. -- Claude Code, 2026-10-28
# Delivery: the workstation-core plugin runs it with -FromPlugin (hooks/hooks.json PostToolUse, and
# hooks/cursor-hooks.json postToolUse). Install no longer copies or wires it (decision
# D-2026-11-26-hooks-in-plugin). With -FromPlugin it prints {} when ~\.claude\settings.json still wires an
# older copy for PostToolUse (that copy runs instead; Cursor also runs those hooks), so it never nudges twice.
param([switch]$FromPlugin)
$ErrorActionPreference = 'Stop'
function Exit-Quiet { [Console]::Out.WriteLine('{}'); exit 0 }
try { $in = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { Exit-Quiet }
if ($FromPlugin) {
  $wired = $false
  try {
    $h = $env:USERPROFILE; if (-not $h) { $h = $HOME }
    $us = Get-Content -LiteralPath (Join-Path (Join-Path $h '.claude') 'settings.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($us.hooks) {
      foreach ($pp in $us.hooks.PSObject.Properties) {
        if ($pp.Name -ieq 'PostToolUse' -and (($pp.Value | ConvertTo-Json -Depth 20 -Compress) -match 'pr-closeout-nudge\.ps1')) { $wired = $true }
      }
    }
  } catch { }
  if ($wired) { Exit-Quiet }
}
$tool = "$($in.tool_name)"
$cursor = ($in.PSObject.Properties.Name -contains 'cursor_version') -or ($tool -eq 'Shell')
# Claude sends tool_response (object); Cursor sends tool_output (a JSON string).
$resp = if ($cursor) { "$($in.tool_output)" } else { $in.tool_response | ConvertTo-Json -Depth 6 -Compress }

if ($tool -in 'Bash', 'PowerShell', 'Shell') {
  if ("$($in.tool_input.command)" -notmatch '(?i)\bgh\s+pr\s+create\b') { Exit-Quiet }
} elseif ($tool -notmatch '(?i)create_pull_request$') { Exit-Quiet }

$m = [regex]::Match("$resp", 'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')
if (-not $m.Success) { Exit-Quiet }   # the command ran but no PR was created

$ctx = "A pull request was just opened: $($m.Value). Run the pr-closeout skill now: live state (status, next step, PR and branch state) goes in this branch's STATE file in the repo (STATE-<branch-slug>.md, committed on this branch), later work in BACKLOG.md, decisions in DECISIONS, via state-closeout; the last commit before merge archives the state file (state_manager.py archive-branch); the PR body gets a State: line. Memory notes (INDEX.md) get only preferences, rules and cross-project facts, each fact once, signed. Run the repo's gates, and report in a few lines. Skip any step that does not apply."
if ($cursor) {
  @{ additional_context = $ctx } | ConvertTo-Json -Compress
} else {
  @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $ctx } } | ConvertTo-Json -Compress
}
exit 0
