# PreToolUse hook (Claude Code and Cursor). Guards files an agent must not change on its own.
# Ask (permissionDecision "ask") before a Write / Edit / NotebookEdit of:
#   - a SPEC file (SPEC.md, SPEC-*.md, SPEC_*.md, SPEC.*.md anywhere in a repo);
#   - a file listed in the repo's VERIFIED.lock (JSON: repo-relative path -> sha256);
#   - a path matched by a line of the repo's optional .claude/protected-paths.txt
#     (repo-relative globs: * and ? stay in one folder, ** crosses folders, a trailing / means the folder;
#      # starts a comment).
# Ask before a shell command that runs deliverable_lock.py unlock (only the owner gives that token).
# Deny a write to another branch's STATE-<slug>.md in the memory store (only STATE-<own slug>.md is this
#   session's; the root STATE.md and archives\ are not judged here).
# Allow everything else. Claude Code: allow prints nothing. Cursor: every run prints exactly one
#   {"permission": ...} line. Any error allows.
. (Join-Path $PSScriptRoot 'state-common.ps1')

$script:IsCursor = $false

function Write-GuardDecision {
  param([string]$Decision, [string]$Msg)
  $obj = [ordered]@{
    permission = $Decision
    user_message = $Msg
    agent_message = $Msg
    hookSpecificOutput = [ordered]@{
      hookEventName = 'PreToolUse'
      permissionDecision = $Decision
      permissionDecisionReason = $Msg
    }
  }
  [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 5))
  exit 0
}

function Exit-GuardAllow {
  if ($script:IsCursor) { [Console]::Out.WriteLine('{"permission":"allow"}') }
  exit 0
}

function ConvertTo-GuardKey {
  param([string]$Path)
  return (($Path -replace '\\', '/').Trim('/')).ToLowerInvariant()
}

function Resolve-GuardTarget {
  param([string]$Path, [string]$Cwd)
  if (-not $Path) { return $null }
  $p = $Path.Trim()
  if (-not [IO.Path]::IsPathRooted($p) -and $Cwd) { $p = Join-Path $Cwd $p }
  try { return [IO.Path]::GetFullPath($p) } catch { return $null }
}

function Get-GuardRepoRoot {
  param([string]$FullPath)
  $dir = Split-Path $FullPath -Parent
  while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path $dir -Parent }
  if (-not $dir) { return $null }
  $top = $null
  try { $top = (& git -C $dir rev-parse --show-toplevel 2>$null) } catch { $top = $null }
  if ($LASTEXITCODE -ne 0 -or -not $top) { return $null }
  try { return [IO.Path]::GetFullPath(([string]$top).Trim()) } catch { return $null }
}

function Get-RepoRelativeKey {
  param([string]$FullPath, [string]$Root)
  $a = ConvertTo-GuardKey $FullPath
  $b = ConvertTo-GuardKey $Root
  if ($a.StartsWith($b + '/')) { return $a.Substring($b.Length + 1) }
  return $null
}

function ConvertFrom-GuardGlob {
  param([string]$Glob)
  $g = ConvertTo-GuardKey $Glob
  if ($Glob.Trim().EndsWith('/') -or $Glob.Trim().EndsWith('\')) { $g = $g + '/**' }
  $sb = New-Object Text.StringBuilder
  $i = 0
  while ($i -lt $g.Length) {
    $c = $g[$i]
    if ($c -eq '*' -and ($i + 1) -lt $g.Length -and $g[$i + 1] -eq '*') {
      if (($i + 2) -lt $g.Length -and $g[$i + 2] -eq '/') { [void]$sb.Append('(?:.*/)?'); $i += 3; continue }
      [void]$sb.Append('.*'); $i += 2; continue
    }
    if ($c -eq '*') { [void]$sb.Append('[^/]*') }
    elseif ($c -eq '?') { [void]$sb.Append('[^/]') }
    else { [void]$sb.Append([regex]::Escape([string]$c)) }
    $i++
  }
  return ('^' + $sb.ToString() + '$')
}

function Find-ProtectedReason {
  param([string]$FullPath, [string]$Root, [string]$Key)
  $leaf = Split-Path $FullPath -Leaf
  if ($leaf -match '(?i)^SPEC([-_.][^\\/]*)?\.md$' -or $leaf -match '(?i)^SPEC$') {
    return "$Key is a SPEC file"
  }
  $lock = Join-Path $Root 'VERIFIED.lock'
  if (Test-Path -LiteralPath $lock -PathType Leaf) {
    try {
      $data = [IO.File]::ReadAllText($lock) | ConvertFrom-Json
      foreach ($prop in $data.PSObject.Properties) {
        if ((ConvertTo-GuardKey $prop.Name) -eq $Key) { return "$Key is locked in VERIFIED.lock (verified deliverable)" }
      }
    } catch { }
  }
  $listFile = Join-Path (Join-Path $Root '.claude') 'protected-paths.txt'
  if (Test-Path -LiteralPath $listFile -PathType Leaf) {
    foreach ($line in [IO.File]::ReadAllLines($listFile)) {
      $glob = $line.Trim()
      if (-not $glob -or $glob.StartsWith('#')) { continue }
      try {
        if ($Key -match (ConvertFrom-GuardGlob $glob)) { return "$Key matches '$glob' in .claude/protected-paths.txt" }
      } catch { }
    }
  }
  return $null
}

function Find-OtherBranchState {
  param([string]$FullPath, [string]$Cwd)
  $leaf = Split-Path $FullPath -Leaf
  if ($leaf -notmatch '(?i)^STATE-.+\.md$') { return $null }
  $info = Get-StatePathInfo $Cwd
  if (-not $info -or -not $info.store) { return $null }
  $storeKey = ConvertTo-GuardKey ([IO.Path]::GetFullPath([string]$info.store))
  $key = ConvertTo-GuardKey $FullPath
  if (-not $key.StartsWith($storeKey + '/')) { return $null }
  $rel = $key.Substring($storeKey.Length + 1)
  if ($rel -notmatch '^[^/]+/state-[^/]+\.md$') { return $null }
  $own = ConvertTo-GuardKey ([IO.Path]::GetFullPath([string]$info.state_file))
  if ($key -eq $own) { return $null }
  $mine = Split-Path ([string]$info.state_file) -Leaf
  return "$FullPath is another branch's live state. This session ($($info.project), branch '$($info.branch)') writes only $mine. Leave other STATE-<slug>.md files to their owners; put cross-branch items in BACKLOG.md."
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    $script:IsCursor = [bool]$env:CURSOR_VERSION
    $hookIn = Read-StateHookInput
    if (Test-CursorHook $hookIn) { $script:IsCursor = $true }
    if (-not $hookIn) { Exit-GuardAllow }
    $tool = [string]$hookIn.tool_name
    $ti = $hookIn.tool_input
    if (-not $ti) { Exit-GuardAllow }
    $cwd = Get-StateHookCwd $hookIn
    $shellTools = @('Bash', 'PowerShell', 'Shell')
    if ($shellTools -contains $tool) {
      $command = [string]$ti.command
      if ($command -match '(?i)deliverable_lock(\.py)?\b[^\r\n;|&]*\bunlock\b') {
        Write-GuardDecision 'ask' 'protected-files-guard: this command unlocks a verified deliverable (deliverable_lock unlock). Only the owner may approve it, in their own words.'
      }
      Exit-GuardAllow
    }
    $raw = $null
    foreach ($name in @('file_path', 'notebook_path', 'path', 'target_file')) {
      if ($ti.PSObject.Properties[$name] -and $ti.$name) { $raw = [string]$ti.$name; break }
    }
    if (-not $raw) { Exit-GuardAllow }
    $full = Resolve-GuardTarget $raw $cwd
    if (-not $full) { Exit-GuardAllow }
    if ($cwd) {
      $deny = Find-OtherBranchState $full $cwd
      if ($deny) { Write-GuardDecision 'deny' ("protected-files-guard: " + $deny) }
    }
    $root = Get-GuardRepoRoot $full
    if ($root) {
      $key = Get-RepoRelativeKey $full $root
      if ($key) {
        $why = Find-ProtectedReason $full $root $key
        if ($why) {
          Write-GuardDecision 'ask' ("protected-files-guard: $why. Changing it needs the owner's yes; say what you will change and why.")
        }
      }
    }
    Exit-GuardAllow
  } catch {
    Exit-GuardAllow
  }
}
