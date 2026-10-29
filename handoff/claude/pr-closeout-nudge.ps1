# pr-closeout-nudge.ps1 — Claude Code PostToolUse hook.
# After a pull request is opened, remind Claude to run the pr-closeout skill
# (state file on this branch, durable memory, gates, report). Never merges,
# never force-pushes, never skips hooks. Silent on everything else.
# Wired by install.ps1 into ~/.claude/settings.json (merge; other hooks stay).
$ErrorActionPreference = 'Continue'
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
if (-not $in) { exit 0 }

$tool = [string]$in.tool_name
$cmd = ''
if ($in.PSObject.Properties['tool_input'] -and $in.tool_input) {
  foreach ($k in @('command', 'Command', 'cmd')) {
    if ($in.tool_input.PSObject.Properties[$k] -and $in.tool_input.$k) {
      $cmd = [string]$in.tool_input.$k
      break
    }
  }
}

$isCreate = $false
if ($cmd -match '(?i)(?:^|[;&|]\s*)(?:gh(?:\.exe|\.cmd)?)\s+pr\s+create\b') { $isCreate = $true }
if ($tool -match '(?i)(create_pull_request|createPullRequest|open_pull_request|submit_pull_request)') { $isCreate = $true }
if (-not $isCreate) { exit 0 }

$blob = $raw
if ($blob -match '(?i)"is_error"\s*:\s*true') { exit 0 }
if ($cmd -match '(?i)\b--dry-run\b') { exit 0 }

$url = $null
$m = [regex]::Match($blob, 'https://github\.com/[^/\s"'']+/[^/\s"'']+/pull/\d+')
if ($m.Success) { $url = $m.Value }
$num = $null
if ($url) {
  $nm = [regex]::Match($url, '/pull/(\d+)')
  if ($nm.Success) { $num = $nm.Groups[1].Value }
}

$where = if ($url) { $url } elseif ($num) { "PR #$num" } else { 'a pull request' }
$msg = @"
A pull request was just opened ($where). Run the pr-closeout skill now: put the PR's effect into the repo's state file on this same branch, save durable memory, run the repo's gates, and report. Do not merge, do not force-push, do not skip hooks. Do not wait for the user to say close out.
"@.Trim()

@{
  hookSpecificOutput = @{
    hookEventName = 'PostToolUse'
    additionalContext = $msg
  }
} | ConvertTo-Json -Compress -Depth 6
exit 0
