# PostToolUse hook (Claude Code Write / Edit / NotebookEdit; Cursor postToolUse). Non-blocking.
# After an edit of a file listed in the repo's .claude/sot.json, runs `sot_guard.py after-edit` (the
# entry's fast checks; for `report: cells`, the changed CSV cells vs HEAD) and hands the result to the
# agent, which must report every changed value and the check results to the owner. A failed check or a
# hand-edited derived (generated) file is shown loudly: Claude also gets a systemMessage for the user.
# Cursor's afterFileEdit has no output fields (https://cursor.com/docs/hooks), so Cursor uses
# postToolUse, whose additional_context reaches the agent. No registry, no repo, or any error: silent.
. (Join-Path $PSScriptRoot 'state-common.ps1')

function Get-SotEditedPath {
  param($HookInput)
  if ($HookInput.PSObject.Properties['file_path'] -and $HookInput.file_path) { return [string]$HookInput.file_path }
  $ti = $HookInput.tool_input
  if (-not $ti) { return $null }
  foreach ($name in @('file_path', 'notebook_path', 'path', 'target_file')) {
    if ($ti.PSObject.Properties[$name] -and $ti.$name) { return [string]$ti.$name }
  }
  return $null
}

function Get-SotRepoRoot {
  param([string]$FullPath)
  $dir = Split-Path $FullPath -Parent
  while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path $dir -Parent }
  if (-not $dir) { return $null }
  $top = (& git -C $dir rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not $top) { return $null }
  return [IO.Path]::GetFullPath(([string]$top).Trim())
}

function Write-SotResult {
  param([bool]$IsCursor, [int]$Code, [string]$Text)
  if ($IsCursor) {
    $obj = [ordered]@{ additional_context = $Text }
  } else {
    $obj = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PostToolUse'; additionalContext = $Text } }
    if ($Code -ne 0) {
      $first = ($Text -split "`r?`n" | Where-Object { $_ -match 'SOT (CHECK FAILED|WARNING)' } | Select-Object -First 1)
      $obj['systemMessage'] = "sot-after-edit: $first"
    }
  }
  [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 5))
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    $hookIn = Read-StateHookInput
    if (-not $hookIn) { exit 0 }
    $isCursor = Test-CursorHook $hookIn
    $raw = Get-SotEditedPath $hookIn
    if (-not $raw) { exit 0 }
    $cwd = Get-StateHookCwd $hookIn
    $p = $raw.Trim()
    if (-not [IO.Path]::IsPathRooted($p) -and $cwd) { $p = Join-Path $cwd $p }
    $full = [IO.Path]::GetFullPath($p)
    $root = Get-SotRepoRoot $full
    if (-not $root) { exit 0 }
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $root '.claude') 'sot.json') -PathType Leaf)) { exit 0 }
    $result = Invoke-StateTool 'sot_guard.py' @('--repo', $root, 'after-edit', $full)
    if (-not $result) { exit 0 }
    $text = ([string]$result.Out).Trim()
    if ($result.Code -ne 0 -and -not $text) { $text = 'SOT CHECK FAILED: ' + ([string]$result.Err).Trim() }
    if (-not $text) { exit 0 }
    Write-SotResult $isCursor ([int]$result.Code) $text
    exit 0
  } catch {
    exit 0
  }
}
