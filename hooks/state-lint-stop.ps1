# Stop hook. Lints this session's STATE file (STATE.md on a trunk branch, else STATE-<branch-slug>.md)
# with scripts/state/state_lint.py against STATE schema v1 (30 lines, headers, only [NEXT], the 2-run rule).
# Only the session's own file is linted: another branch's file is not this agent's to fix.
# Claude Code: a violation prints the problems to stderr and exits 2, which blocks the stop once so the
#   agent fixes the file. stop_hook_active (a stop already blocked) exits 0, so it never loops.
# Cursor: a violation prints one {"followup_message": ...} line; a later loop (loop_count >= 1) stays quiet.
# Exit 0 with no output when: not a git repo, no tools or Python, store unreachable, no project folder,
# or no STATE file for this session. Never edits the file.
. (Join-Path $PSScriptRoot 'state-common.ps1')

function Test-StopLoop {
  param($HookInput)
  if (-not $HookInput) { return $false }
  try {
    if ($HookInput.PSObject.Properties['stop_hook_active'] -and $HookInput.stop_hook_active) { return $true }
    if ($HookInput.PSObject.Properties['loop_count'] -and $null -ne $HookInput.loop_count -and ([int]$HookInput.loop_count -ge 1)) { return $true }
  } catch { }
  return $false
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
    $hookIn = Read-StateHookInput
    if (Test-StopLoop $hookIn) { exit 0 }
    $cwd = Get-StateHookCwd $hookIn
    if (-not $cwd) { exit 0 }
    $info = Get-StatePathInfo $cwd
    if (-not $info -or -not $info.store_reachable) { exit 0 }
    $target = [string]$info.state_file
    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { exit 0 }
    $result = Invoke-StateTool 'state_lint.py' @($target)
    if (-not $result -or $result.Code -ne 2) { exit 0 }
    $problems = ($result.Out.Trim())
    $msg = "state-lint-stop: $target breaks STATE schema v1. Fix it before you stop (overwrite the file, keep it to 30 lines; graduate or BACKLOG anything that is not the one [NEXT] step):" + [Environment]::NewLine + $problems
    if (Test-CursorHook $hookIn) {
      [Console]::Out.WriteLine(([ordered]@{ followup_message = $msg } | ConvertTo-Json -Compress))
      exit 0
    }
    [Console]::Error.WriteLine($msg)
    exit 2
  } catch {
    exit 0
  }
}
