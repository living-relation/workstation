$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'projects-root-common.ps1')

function Exit-Allow {
  if ($env:CURSOR_VERSION) { [Console]::Out.WriteLine('{"permission":"allow"}') }
  exit 0
}

function Write-Deny {
  param([string]$Msg)
  $obj = [ordered]@{
    permission = 'deny'
    agent_message = $Msg
    hookSpecificOutput = [ordered]@{
      hookEventName = 'PreToolUse'
      permissionDecision = 'deny'
      permissionDecisionReason = $Msg
    }
  }
  [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 5))
  exit 0
}

if ($MyInvocation.InvocationName -ne '.') {
  $raw = ''
  try { $raw = [Console]::In.ReadToEnd() } catch { Exit-Allow }
  if ([string]::IsNullOrWhiteSpace($raw)) {
    $raw = @($input | ForEach-Object { "$_" }) -join "`n"
  }
  $in = $null
  try { $in = $raw | ConvertFrom-Json } catch { Exit-Allow }
  $tool = [string]$in.tool_name
  $ti = $in.tool_input
  if (-not $ti) { Exit-Allow }
  $fileTools = @('Write', 'Edit', 'NotebookEdit')
  $shellTools = @('Bash', 'PowerShell', 'Shell')
  $createAny = '(?i)\b(mkdir|md|New-Item|ni|mv|move|Move-Item|cp|copy|Copy-Item|Out-File|Set-Content|Add-Content|tee|touch|Expand-Archive|git\s+clone|git\s+worktree\s+add)\b|>'
  if ($fileTools -contains $tool) {
    $text = "$($ti.file_path) $($ti.notebook_path) $($ti.path)"
  } elseif ($shellTools -contains $tool) {
    $text = "$($ti.command)"
    if ($text -notmatch $createAny) { Exit-Allow }
  } else { Exit-Allow }
  $root = Get-ProjectsRoot
  if (-not $root) { Exit-Allow }
  $cwd = [string]$in.cwd
  $why = Find-ProjectsRootViolation -Root $root -Text $text -Cwd $cwd -Tool $tool
  if ($why) {
    $display = Get-ProjectsRootDisplay $root
    $msg = "Blocked by projects-root-guard: $why. Put project files inside the project folder. Root rules: $display\AGENTS.md."
    Write-Deny $msg
  }
  Exit-Allow
}
