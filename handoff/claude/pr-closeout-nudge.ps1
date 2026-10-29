# PostToolUse nudge (Dan, 2026-10-28): after a shell call that ran `gh pr create` and printed a
# PR URL, or a GitHub-MCP create_pull_request, tell the agent to run the pr-closeout skill
# (state file on the same PR branch + memory + hygiene). One script for Claude Code
# (~\.claude\settings.json, tools Bash / PowerShell) and Cursor (~\.cursor\hooks.json
# postToolUse, tool Shell). Never blocks. Prints "{}" when it has nothing to say, because
# Cursor treats an empty reply as invalid JSON. -- Claude Code, 2026-10-28
$ErrorActionPreference = 'Stop'
function Exit-Quiet { [Console]::Out.WriteLine('{}'); exit 0 }
try { $in = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { Exit-Quiet }
$tool = "$($in.tool_name)"
$cursor = ($in.PSObject.Properties.Name -contains 'cursor_version') -or ($tool -eq 'Shell')
# Claude sends tool_response (object); Cursor sends tool_output (a JSON string).
$resp = if ($cursor) { "$($in.tool_output)" } else { $in.tool_response | ConvertTo-Json -Depth 6 -Compress }

if ($tool -in 'Bash', 'PowerShell', 'Shell') {
  if ("$($in.tool_input.command)" -notmatch '(?i)\bgh\s+pr\s+create\b') { Exit-Quiet }
} elseif ($tool -notmatch '(?i)create_pull_request$') { Exit-Quiet }

$m = [regex]::Match("$resp", 'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')
if (-not $m.Success) { Exit-Quiet }   # the command ran but no PR was created

$ctx = "A pull request was just opened: $($m.Value). Run the pr-closeout skill now: update the repo's state file on this PR's own branch, save durable non-repo facts to memory (signed), run the repo's gates, and report in a few lines. Skip any step that does not apply."
if ($cursor) {
  @{ additional_context = $ctx } | ConvertTo-Json -Compress
} else {
  @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $ctx } } | ConvertTo-Json -Compress
}
exit 0
