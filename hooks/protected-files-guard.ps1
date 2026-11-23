# PreToolUse hook (Claude Code and Cursor). Guards files an agent must not change on its own.
# Ask (permissionDecision "ask") before a Write / Edit / NotebookEdit of:
#   - a SPEC file (SPEC.md, SPEC-*.md, SPEC_*.md, SPEC.*.md anywhere in a repo);
#   - a file listed in the repo's VERIFIED.lock (JSON: repo-relative path -> sha256);
#   - a source of truth listed in the repo's optional .claude/sot.json (sot_guard.py match), or that
#     registry itself; the message names the entry's checks;
#   - a path matched by a line of the repo's optional .claude/protected-paths.txt
#     (repo-relative globs: * and ? stay in one folder, ** crosses folders, a trailing / means the folder;
#      # starts a comment).
# Ask before a shell command that runs deliverable_lock.py unlock (this ask is the owner's real gate).
# Ask before any Write / Edit of VERIFIED.lock itself (only deliverable_lock.py writes it).
# A SPEC file asks only when the repo is migrated (its worktree root has STATE.md).
# Deny a write to another branch's STATE-<slug>.md at a worktree root of the same repo (only
#   STATE-<own slug>.md is this session's; archives/ are not judged here). Ask before a write to the
#   root STATE.md when this session's own file is a STATE-<slug>.md (one writer: the coordinator).
# Allow everything else. Claude Code: only hookSpecificOutput; allow prints nothing. Cursor: only
#   {"permission", "user_message", "agent_message"}, one line every run. Rule: agents may edit these
#   files, only with the owner's explicit yes, and checks prove each edit; the one hard block is another
#   branch's STATE-<slug>.md. Cursor does not enforce "ask" in preToolUse (https://cursor.com/docs/hooks),
#   so there an ask becomes allow plus a warning naming the yes it needs and the checks that will run.
#   Cursor beforeShellExecution does enforce "ask": the unlock command asks there.
# Any error allows.
. (Join-Path $PSScriptRoot 'state-common.ps1')

$script:IsCursor = $false
$script:IsCursorShellEvent = $false

function Write-GuardDecision {
  param([string]$Decision, [string]$Msg, [string]$Checks)
  if ($script:IsCursor) {
    if ($Decision -eq 'ask' -and -not $script:IsCursorShellEvent) {
      $Decision = 'allow'
      $Msg = $Msg + ' Cursor allows this without a hard block, but you must already have the owner''s explicit yes in this chat for this exact edit (name the file and why). No yes: stop and ask first. After the edit, report every changed value and the check results.'
    }
    if ($Checks) { $Msg = $Msg + " Checks: $Checks." }
    $obj = [ordered]@{ permission = $Decision; user_message = $Msg; agent_message = $Msg }
  } else {
    if ($Checks) { $Msg = $Msg + " Checks: $Checks." }
    $obj = [ordered]@{
      hookSpecificOutput = [ordered]@{
        hookEventName = 'PreToolUse'
        permissionDecision = $Decision
        permissionDecisionReason = $Msg
      }
    }
  }
  [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 5))
  exit 0
}

$script:UnlockMessage = 'protected-files-guard: this command unlocks a verified deliverable (deliverable_lock unlock). Only the owner may approve it, in their own words.'
$script:UnlockChecks = 'deliverable_lock.py logs the owner phrase in VERIFIED.lock _history; Cursor asks the owner in beforeShellExecution'

function Test-GuardUnlockCommand {
  param([string]$Command)
  return ($Command -match '(?i)deliverable_lock(\.py)?\b[^\r\n;|&]*\bunlock\b')
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

function New-GuardReason {
  param([string]$Why, [string]$Checks)
  return [pscustomobject]@{ Why = $Why; Checks = $Checks }
}

function Find-SotReason {
  param([string]$FullPath, [string]$Root, [string]$Key)
  $registry = Join-Path (Join-Path $Root '.claude') 'sot.json'
  if (-not (Test-Path -LiteralPath $registry -PathType Leaf)) { return $null }
  if ($Key -eq '.claude/sot.json') {
    return (New-GuardReason '.claude/sot.json is the source-of-truth registry (it decides which checks prove each SoT edit)' 'sot_guard.py lint-registry; git pre-commit sot_guard.py check')
  }
  $m = Invoke-StateTool 'sot_guard.py' @('--repo', $Root, 'match', $FullPath)
  if (-not $m) { return $null }
  if ($m.Code -ne 0) {
    return (New-GuardReason "$Key may be a source of truth: .claude/sot.json is invalid ($(([string]$m.Err).Trim()))" 'fix the registry first: sot_guard.py lint-registry')
  }
  try { $info = ([string]$m.Out) | ConvertFrom-Json } catch { return $null }
  if (-not $info -or $info.kind -ne 'sot') { return $null }
  $fast = (@($info.fast_checks) | Where-Object { $_ }) -join '; '
  $all = (@($info.checks) | Where-Object { $_ }) -join '; '
  if (-not $fast) { $fast = 'no fast check' }
  if (-not $all) { $all = 'none (the entry has no checks; sot_guard.py check fails)' }
  return (New-GuardReason "$Key is a source of truth (entry '$($info.entry)' in .claude/sot.json)" "after the edit, sot-after-edit runs $fast; at commit, git pre-commit sot_guard.py check runs $all")
}

function Find-ProtectedReason {
  param([string]$FullPath, [string]$Root, [string]$Key)
  $leaf = Split-Path $FullPath -Leaf
  if ($Key -eq 'verified.lock') {
    return (New-GuardReason 'VERIFIED.lock is written only by deliverable_lock.py (lock / unlock on the owner''s words), never by hand' 'deliverable_lock.py verify (git pre-commit) fails on any hand edit')
  }
  if ($leaf -match '(?i)^SPEC([-_.][^\\/]*)?\.md$' -or $leaf -match '(?i)^SPEC$') {
    if (Test-GuardRepoMigrated $Root) { return (New-GuardReason "$Key is a SPEC file" 'the repo''s git pre-commit hooks and CI') }
  }
  $lock = Join-Path $Root 'VERIFIED.lock'
  if (Test-Path -LiteralPath $lock -PathType Leaf) {
    try {
      $data = [IO.File]::ReadAllText($lock) | ConvertFrom-Json
      foreach ($prop in $data.PSObject.Properties) {
        if ($prop.Name -eq '_history') { continue }
        if ((ConvertTo-GuardKey $prop.Name) -eq $Key) { return (New-GuardReason "$Key is locked in VERIFIED.lock (verified deliverable)" 'deliverable_lock.py verify (git pre-commit) fails until the owner unlocks it') }
      }
    } catch { }
  }
  $sot = Find-SotReason $FullPath $Root $Key
  if ($sot) { return $sot }
  $listFile = Join-Path (Join-Path $Root '.claude') 'protected-paths.txt'
  if (Test-Path -LiteralPath $listFile -PathType Leaf) {
    foreach ($line in [IO.File]::ReadAllLines($listFile)) {
      $glob = $line.Trim()
      if (-not $glob -or $glob.StartsWith('#')) { continue }
      try {
        if ($Key -match (ConvertFrom-GuardGlob $glob)) { return (New-GuardReason "$Key matches '$glob' in .claude/protected-paths.txt" 'the repo''s git pre-commit hooks and CI') }
      } catch { }
    }
  }
  return $null
}

function Test-GuardRepoMigrated {
  param([string]$Root)
  $info = Get-StatePathInfo $Root
  if (-not $info) { return $false }
  return [bool]$info.state_ready
}

# The target's own repo info when the file sits directly at a worktree root of the same main repo
# as this session (a STATE file location); else $null.
function Get-SameRepoStateRootInfo {
  param([string]$FullPath, $Info)
  $parent = Split-Path $FullPath -Parent
  if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { return $null }
  $other = Get-StatePathInfo $parent
  if (-not $other -or -not $other.state_dir -or -not $other.repo_root) { return $null }
  if ((ConvertTo-GuardKey ([IO.Path]::GetFullPath([string]$other.state_dir))) -ne (ConvertTo-GuardKey ([IO.Path]::GetFullPath($parent)))) { return $null }
  if ((ConvertTo-GuardKey ([string]$other.repo_root)) -ne (ConvertTo-GuardKey ([string]$Info.repo_root))) { return $null }
  return $other
}

function Find-RootStateFromBranch {
  param([string]$FullPath, [string]$Cwd)
  if ((Split-Path $FullPath -Leaf) -ine 'STATE.md') { return $null }
  $info = Get-StatePathInfo $Cwd
  if (-not $info -or -not $info.state_dir -or -not $info.state_file) { return $null }
  $mine = Split-Path ([string]$info.state_file) -Leaf
  if ($mine -ieq 'STATE.md') { return $null }
  if (-not (Get-SameRepoStateRootInfo $FullPath $info)) { return $null }
  return "$FullPath is the project's root STATE, owned by the coordinator. This session (branch '$($info.branch)') writes $mine; ask before touching the root STATE"
}

function Find-OtherBranchState {
  param([string]$FullPath, [string]$Cwd)
  $leaf = Split-Path $FullPath -Leaf
  if ($leaf -notmatch '(?i)^STATE-.+\.md$') { return $null }
  $info = Get-StatePathInfo $Cwd
  if (-not $info -or -not $info.state_file) { return $null }
  if (-not (Get-SameRepoStateRootInfo $FullPath $info)) { return $null }
  $key = ConvertTo-GuardKey $FullPath
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
    if ($script:IsCursor -and ([string]$hookIn.hook_event_name) -eq 'beforeShellExecution') {
      $script:IsCursorShellEvent = $true
      if (Test-GuardUnlockCommand ([string]$hookIn.command)) {
        Write-GuardDecision 'ask' $script:UnlockMessage $script:UnlockChecks
      }
      Exit-GuardAllow
    }
    $tool = [string]$hookIn.tool_name
    $ti = $hookIn.tool_input
    if (-not $ti) { Exit-GuardAllow }
    $cwd = Get-StateHookCwd $hookIn
    $shellTools = @('Bash', 'PowerShell', 'Shell')
    if ($shellTools -contains $tool) {
      $command = [string]$ti.command
      if (Test-GuardUnlockCommand $command) {
        Write-GuardDecision 'ask' $script:UnlockMessage $script:UnlockChecks
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
      $rootAsk = Find-RootStateFromBranch $full $cwd
      if ($rootAsk) { Write-GuardDecision 'ask' ("protected-files-guard: " + $rootAsk + '.') 'state_lint.py (Stop hook and git pre-commit)' }
    }
    $root = Get-GuardRepoRoot $full
    if ($root) {
      $key = Get-RepoRelativeKey $full $root
      if ($key) {
        $why = Find-ProtectedReason $full $root $key
        if ($why) {
          Write-GuardDecision 'ask' ("protected-files-guard: $($why.Why). Changing it needs the owner's yes; say what you will change and why.") $why.Checks
        }
      }
    }
    Exit-GuardAllow
  } catch {
    Exit-GuardAllow
  }
}
