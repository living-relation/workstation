# Tests for pr-closeout-nudge.ps1. No files written to the real profile.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File handoff/claude/tests/test-pr-closeout-nudge.ps1
$ErrorActionPreference = 'Stop'
$hook = Join-Path $PSScriptRoot '..\pr-closeout-nudge.ps1'
$fail = 0
function Check([string]$What, $Ok) {
  if ($Ok) { "PASS $What" } else { "FAIL $What"; $script:fail++ }
}
$shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
function Invoke-Hook($Payload) {
  $psi = New-Object Diagnostics.ProcessStartInfo $shell, "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write(($Payload | ConvertTo-Json -Compress -Depth 8))
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd()
  $null = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out }
}

$r0 = Invoke-Hook @{ hook_event_name = 'PostToolUse'; tool_name = 'Bash'; tool_input = @{ command = 'git status' } }
Check 'unrelated bash silent' ([string]::IsNullOrWhiteSpace($r0.Out))
Check 'unrelated bash exit 0' ($r0.Code -eq 0)

$rView = Invoke-Hook @{
  hook_event_name = 'PostToolUse'
  tool_name = 'Bash'
  tool_input = @{ command = 'gh pr view 12' }
  tool_response = 'https://github.com/org/repo/pull/12'
}
Check 'gh pr view silent' ([string]::IsNullOrWhiteSpace($rView.Out))

$rCreate = Invoke-Hook @{
  hook_event_name = 'PostToolUse'
  tool_name = 'Bash'
  tool_input = @{ command = 'gh pr create --fill' }
  tool_response = "https://github.com/living-relation/workstation/pull/99`n"
}
Check 'gh pr create nudges' ($rCreate.Out -match 'pr-closeout')
Check 'gh pr create includes url' ($rCreate.Out -match 'living-relation/workstation/pull/99')
Check 'nested additionalContext' ($rCreate.Out -match 'hookSpecificOutput' -and $rCreate.Out -match 'additionalContext')
Check 'create exit 0' ($rCreate.Code -eq 0)

$rMcp = Invoke-Hook @{
  hook_event_name = 'PostToolUse'
  tool_name = 'mcp__github__create_pull_request'
  tool_input = @{ title = 'x' }
  tool_response = @{ html_url = 'https://github.com/org/repo/pull/7' }
}
Check 'github mcp create nudges' ($rMcp.Out -match 'pr-closeout' -and $rMcp.Out -match '/pull/7')

$rErr = Invoke-Hook @{
  hook_event_name = 'PostToolUse'
  tool_name = 'Bash'
  tool_input = @{ command = 'gh pr create --fill' }
  tool_response = @{ is_error = $true; stderr = 'failed' }
}
Check 'failed create silent' ([string]::IsNullOrWhiteSpace($rErr.Out))

if ($fail) { exit 1 } else { 'ALL PASS' }
