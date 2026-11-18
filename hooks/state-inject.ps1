# SessionStart hook. Prints the project's live state from the memory store so the agent starts from it:
# STATE.md on a trunk branch (main, master, trunk) or a detached HEAD, else STATE-<branch-slug>.md.
# When the branch file does not exist yet, prints STATE.md with a note. Then one line asks the agent to
# confirm goal, Last_Verified_SHA and next step in 3 lines.
# Silent exit 0 when: not a git repo, no state tools or Python, store unreachable, no project folder
# (repo not migrated yet), or no STATE file. Never writes anything. Exit 0 on every error.
# Claude Code (SessionStart): plain text on stdout. Cursor (sessionStart): one {"additional_context": ...} line.
. (Join-Path $PSScriptRoot 'state-common.ps1')

function Format-StateInjection {
  param([string]$Path, [string]$Text, [string]$Note)
  $lines = New-Object 'System.Collections.Generic.List[string]'
  [void]$lines.Add("state-inject: live state from $Path")
  if ($Note) { [void]$lines.Add($Note) }
  [void]$lines.Add('```')
  [void]$lines.Add($Text.TrimEnd())
  [void]$lines.Add('```')
  [void]$lines.Add('Before any other work, confirm in 3 lines: (1) the goal, (2) Last_Verified_SHA, (3) the next step, all from this STATE file. Ask only if it is missing or wrong.')
  return ($lines -join [Environment]::NewLine)
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    try {
      $utf8 = New-Object System.Text.UTF8Encoding $false
      [Console]::OutputEncoding = $utf8
    } catch { }
    $hookIn = Read-StateHookInput
    $cwd = Get-StateHookCwd $hookIn
    if (-not $cwd) { exit 0 }
    $info = Get-StatePathInfo $cwd
    if (-not $info -or -not $info.store_reachable) { exit 0 }
    if (-not (Test-Path -LiteralPath $info.project_dir -PathType Container)) { exit 0 }
    $target = [string]$info.state_file
    $note = $null
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
      $root = Join-Path $info.project_dir 'STATE.md'
      if ($target -ieq $root -or -not (Test-Path -LiteralPath $root -PathType Leaf)) { exit 0 }
      $note = "No $(Split-Path $target -Leaf) for branch '$($info.branch)' yet; showing the root STATE.md. Create the branch file with: state_manager.py new-branch"
      $target = $root
    }
    $text = [IO.File]::ReadAllText($target)
    if ([string]::IsNullOrWhiteSpace($text)) { exit 0 }
    $injection = Format-StateInjection -Path $target -Text $text -Note $note
    if (Test-CursorHook $hookIn) {
      [Console]::Out.WriteLine((@{ additional_context = $injection } | ConvertTo-Json -Compress))
    } else {
      [Console]::Out.WriteLine($injection)
    }
    exit 0
  } catch {
    exit 0
  }
}
