# SessionStart hook. Warns when CLAUDE.md, .claude/CLAUDE.md, or CLAUDE.local.md
# is in the session directory or any parent up to the drive root.
# Ignores ~/.claude/CLAUDE.md (USERPROFILE, HOME, and the OS user profile).
# Warn only: plain text on stdout. Never deletes, edits, or blocks.
# Exit 0 on every error. Windows PowerShell 5.1 and pwsh (POSIX) safe.

function Get-FullPathSafe {
  param([string]$Path)
  if (-not $Path) { return $null }
  $p = "$Path".Trim()
  if (-not $p) { return $null }
  if ($p -match '^([A-Za-z]):[\\/]*$') { return ($Matches[1].ToUpper() + ':\') }
  $sep = [IO.Path]::DirectorySeparatorChar
  if ($sep -eq '/' -and $p -match '^[A-Za-z]:') { return $null }
  try { $full = [IO.Path]::GetFullPath($p) } catch { return $null }
  if (-not $full) { return $null }
  $full = $full -replace '^\\\\\?\\', ''
  if ($full -eq '/' -or $full -match '^[A-Za-z]:\\$') { return $full }
  return $full.TrimEnd('\', '/')
}

function Add-InstructionKeys {
  param($Set, [string]$Path)
  if (-not $Set -or -not $Path) { return }
  $raw = ("$Path".Trim() -replace '\\', '/')
  if (-not $raw) { return }
  $forms = New-Object 'System.Collections.Generic.List[string]'
  [void]$forms.Add($raw)
  if ($raw -notmatch '^[A-Za-z]:') {
    $full = Get-FullPathSafe $Path
    if ($full) { [void]$forms.Add(($full -replace '\\', '/')) }
  }
  $all = New-Object 'System.Collections.Generic.List[string]'
  foreach ($form in $forms) {
    $s = ($form -replace '\\', '/').TrimEnd('/')
    if (-not $s) { continue }
    [void]$all.Add($s)
    $drive = $null
    $rest = $null
    if ($s -match '^(?i)([a-z]):(.*)$') {
      $drive = $Matches[1].ToLower()
      $rest = $Matches[2]
      if (-not $rest.StartsWith('/')) { $rest = '/' + $rest }
    } elseif ($s -match '^(?i)/mnt/([a-z])(/.*)?$') {
      $drive = $Matches[1].ToLower()
      $rest = '/'
      if ($Matches[2]) { $rest = $Matches[2] }
    } elseif ($s -match '^(?i)/([a-z])(/.*)$') {
      $drive = $Matches[1].ToLower()
      $rest = $Matches[2]
    }
    if ($drive) {
      [void]$all.Add($drive + ':' + $rest)
      [void]$all.Add('/' + $drive + $rest)
      [void]$all.Add('/mnt/' + $drive + $rest)
    }
  }
  foreach ($item in $all) {
    $key = $item.ToLowerInvariant()
    if (-not $Set.ContainsKey($key)) { $Set[$key] = $true }
  }
}

function Join-HomeClaudeFile {
  param([string]$ProfilePath)
  if (-not $ProfilePath) { return $null }
  $h = "$ProfilePath".Trim().TrimEnd('\', '/')
  if (-not $h) { return $null }
  if ($h -match '^[A-Za-z]:') { return ($h + '\.claude\CLAUDE.md') }
  return (Join-Path (Join-Path $h '.claude') 'CLAUDE.md')
}

function Add-HomeIgnoreKeys {
  param($Set, [string]$ProfilePath)
  $file = Join-HomeClaudeFile $ProfilePath
  if ($file) { Add-InstructionKeys $Set $file }
}

function Get-IgnoreKeySet {
  $set = @{}
  foreach ($profilePath in @($env:USERPROFILE, $env:HOME)) {
    if ($profilePath) { Add-HomeIgnoreKeys $set "$profilePath" }
  }
  try {
    $profile = [Environment]::GetFolderPath('UserProfile')
    if ($profile) { Add-HomeIgnoreKeys $set $profile }
  } catch { }
  return $set
}

function Test-InstructionIgnored {
  param([string]$Path, $IgnoreSet)
  if (-not $Path -or -not $IgnoreSet) { return $false }
  $mine = @{}
  Add-InstructionKeys $mine $Path
  foreach ($k in @($mine.Keys)) {
    if ($IgnoreSet.ContainsKey($k)) { return $true }
  }
  return $false
}

function Get-DisplayPath {
  param([string]$Path)
  $full = Get-FullPathSafe $Path
  if ($full) { return $full }
  if ($Path -match '^[A-Za-z]:') { return ($Path -replace '/', '\') }
  return ($Path -replace '\\', '/')
}

function Get-ParentDirectory {
  param([string]$Path)
  if (-not $Path) { return $null }
  try {
    $parent = [IO.Directory]::GetParent($Path)
  } catch { return $null }
  if (-not $parent) { return $null }
  return $parent.FullName
}

function Get-DirectoryChain {
  param([string]$Start)
  $dir = Get-FullPathSafe $Start
  if (-not $dir) { return }
  $guard = 0
  while ($dir -and $guard -lt 256) {
    $guard++
    Write-Output $dir
    $parent = Get-ParentDirectory $dir
    if (-not $parent) { break }
    $parentNorm = Get-FullPathSafe $parent
    if (-not $parentNorm -or $parentNorm -eq $dir) { break }
    $dir = $parentNorm
  }
}

function Get-SessionDir {
  param($In)
  $cwd = $null
  try {
    if ($In -and $In.PSObject.Properties['cwd'] -and $In.cwd) { $cwd = [string]$In.cwd }
  } catch { $cwd = $null }
  if (-not $cwd) {
    try { $cwd = (Get-Location).Path } catch { return $null }
  }
  $full = Get-FullPathSafe $cwd
  if (-not $full) { return $null }
  $isFile = $false
  try { $isFile = Test-Path -LiteralPath $full -PathType Leaf } catch { $isFile = $false }
  if ($isFile) {
    $parent = Get-ParentDirectory $full
    if ($parent) { return (Get-FullPathSafe $parent) }
  }
  return $full
}

function Find-InstructionFiles {
  param([Parameter(Mandatory = $true)][string]$StartDir)
  $ignore = Get-IgnoreKeySet
  $seen = @{}
  foreach ($dir in @(Get-DirectoryChain -Start $StartDir)) {
    $names = @(
      (Join-Path $dir 'CLAUDE.md'),
      (Join-Path (Join-Path $dir '.claude') 'CLAUDE.md'),
      (Join-Path $dir 'CLAUDE.local.md')
    )
    foreach ($candidate in $names) {
      if (Test-InstructionIgnored $candidate $ignore) { continue }
      $exists = $false
      try { $exists = Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue } catch { $exists = $false }
      if (-not $exists) { continue }
      $display = Get-DisplayPath $candidate
      if (-not $display) { continue }
      $keySet = @{}
      Add-InstructionKeys $keySet $display
      $dup = $false
      foreach ($k in @($keySet.Keys)) {
        if ($seen.ContainsKey($k)) { $dup = $true; break }
      }
      if ($dup) { continue }
      foreach ($k in @($keySet.Keys)) { $seen[$k] = $true }
      Write-Output $display
    }
  }
}

function Format-AgentsMdWarning {
  param([string[]]$Paths)
  $rule = "Rule: AGENTS.md is the only instruction file. Fold this file's content into AGENTS.md, then delete it (in a PR for repo files; files outside a repo: tell the user)."
  $lines = New-Object 'System.Collections.Generic.List[string]'
  [void]$lines.Add('agents-md-only-warn: instruction files found. This hook only warns. It did not delete, edit, or block anything.')
  [void]$lines.Add($rule)
  foreach ($p in $Paths) {
    if ($p) { [void]$lines.Add('- ' + $p) }
  }
  return ($lines -join [Environment]::NewLine)
}

if ($MyInvocation.InvocationName -ne '.') {
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    try {
      $utf8 = New-Object System.Text.UTF8Encoding $false
      [Console]::InputEncoding = $utf8
      [Console]::OutputEncoding = $utf8
    } catch { }
    $raw = ''
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch { $redirected = $true }
    if ($redirected) {
      try { $raw = [Console]::In.ReadToEnd() } catch { $raw = '' }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
      try { $raw = @($input | ForEach-Object { "$_" }) -join "`n" } catch { $raw = '' }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $hookIn = $null
    try { $hookIn = $raw | ConvertFrom-Json } catch { exit 0 }
    if (-not $hookIn) { exit 0 }
    $start = Get-SessionDir $hookIn
    if (-not $start) { exit 0 }
    $hits = @(Find-InstructionFiles -StartDir $start)
    if ($hits.Count -eq 0) { exit 0 }
    [Console]::Out.WriteLine((Format-AgentsMdWarning -Paths $hits))
    exit 0
  } catch {
    exit 0
  }
}
