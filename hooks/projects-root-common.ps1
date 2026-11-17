# Shared root detection for the projects-root hooks.
# Root: WORKSTATION_PROJECTS_ROOT if that path exists, else C:\projects if it
# exists, else %USERPROFILE%\projects if it exists, else nothing.
# Keyword block list: WORKSTATION_PROJECTS_DENY_KEYWORDS (a regex). Empty skips it.

function ConvertTo-WindowsProjectsRoot {
  param([string]$Root)
  if (-not $Root) { return $null }
  $r = $Root.TrimEnd('\', '/')
  $drive = $null
  $rest = $null
  if ($r -match '^(?i)([a-z]):[\\/](.*)$') {
    $drive = $Matches[1].ToUpper()
    $rest = ($Matches[2] -replace '[\\/]+', '\').Trim('\')
  } elseif ($r -match '^(?i)/mnt/([a-z])(?:/(.*))?$') {
    $drive = $Matches[1].ToUpper()
    $rest = ''
    if ($Matches[2]) { $rest = ($Matches[2] -replace '[\\/]+', '\').Trim('\') }
  } elseif ($r -match '^(?i)/([a-z])(?:/(.*))?$') {
    $drive = $Matches[1].ToUpper()
    $rest = ''
    if ($Matches[2]) { $rest = ($Matches[2] -replace '[\\/]+', '\').Trim('\') }
  } else {
    return $null
  }
  if ($rest) { return ($drive + ':\' + $rest) }
  return ($drive + ':\')
}

function Get-ProjectsRootDisplay {
  param([string]$Root)
  $win = ConvertTo-WindowsProjectsRoot $Root
  if ($win) { return $win.TrimEnd('\') }
  return $Root.TrimEnd('\', '/')
}

function Get-ProjectsRootRegex {
  param([string]$Root)
  $win = ConvertTo-WindowsProjectsRoot $Root
  if (-not $win) {
    $trim = $Root.TrimEnd('\', '/')
    $parts = @($trim -split '[\\/]+' | Where-Object { $_ -ne '' })
    $body = ($parts | ForEach-Object { [regex]::Escape($_) }) -join '[\\/]+'
    if ($trim.StartsWith('/')) { return ('(?i)/' + $body) }
    return ('(?i)' + $body)
  }
  $drive = $null
  $rest = ''
  if ($win -match '^(?i)([a-z]):\\(.*)$') {
    $drive = $Matches[1]
    $rest = $Matches[2]
  } elseif ($win -match '^(?i)([a-z]):\\?$') {
    $drive = $Matches[1]
    $rest = ''
  } else {
    return ('(?i)' + [regex]::Escape($win))
  }
  $segs = @($rest -split '\\' | Where-Object { $_ -ne '' })
  $segAny = ''
  if ($segs.Count -gt 0) {
    $segAny = ($segs | ForEach-Object { [regex]::Escape($_) }) -join '[\\/]+'
  }
  $d = [regex]::Escape($drive)
  $dl = [regex]::Escape($drive.ToLower())
  if ($segAny) {
    return ('(?i)(?:' + $d + ':[\\/]+' + $segAny + '|/' + $dl + '[\\/]+' + $segAny + '|/mnt/' + $dl + '[\\/]+' + $segAny + ')')
  }
  return ('(?i)(?:' + $d + ':[\\/]*|/' + $dl + '|/mnt/' + $dl + ')')
}

function Test-SessionInProjectsRoot {
  param([string]$Cwd, [string]$Root)
  if (-not $Cwd) { return $false }
  $norm = ($Cwd -replace '/', '\').TrimEnd('\')
  $win = ConvertTo-WindowsProjectsRoot $Root
  if ($win -and ($win -match '^(?i)([A-Z]):\\(.*)$')) {
    $drive = $Matches[1]
    $rest = $Matches[2].Trim('\')
    $tail = ''
    if ($rest) { $tail = '\' + $rest }
    $cands = @(
      ($drive.ToUpper() + ':' + $tail),
      ('\' + $drive.ToLower() + $tail),
      ('\mnt\' + $drive.ToLower() + $tail)
    )
    foreach ($c in $cands) {
      if ($norm -ieq $c.TrimEnd('\')) { return $true }
    }
    return $false
  }
  $want = ($Root -replace '/', '\').TrimEnd('\')
  return ($norm -ieq $want)
}

function Get-DenyKeywords {
  $v = $env:WORKSTATION_PROJECTS_DENY_KEYWORDS
  if ($null -eq $v) { return $null }
  $v = "$v".Trim()
  if ($v -eq '') { return $null }
  try { [void][regex]::Match('', $v) } catch { return $null }
  return $v
}

function Get-ProjectsRoot {
  $override = $env:WORKSTATION_PROJECTS_ROOT
  if ($null -ne $override -and "$override".Trim() -ne '') {
    $override = "$override".Trim()
    if (Test-Path -LiteralPath $override) {
      $full = (Resolve-Path -LiteralPath $override).Path
      $full = $full -replace '^\\\\\?\\', ''
      return $full.TrimEnd('\', '/')
    }
    return $null
  }
  if (Test-Path -LiteralPath 'C:\projects') {
    $full = (Resolve-Path -LiteralPath 'C:\projects').Path
    $full = $full -replace '^\\\\\?\\', ''
    return $full.TrimEnd('\', '/')
  }
  if ($env:USERPROFILE) {
    $homeProjects = Join-Path $env:USERPROFILE 'projects'
    if (Test-Path -LiteralPath $homeProjects) {
      $full = (Resolve-Path -LiteralPath $homeProjects).Path
      $full = $full -replace '^\\\\\?\\', ''
      return $full.TrimEnd('\', '/')
    }
  }
  return $null
}

function Find-ProjectsRootViolation {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Cwd,
    [string]$Tool
  )
  $display = Get-ProjectsRootDisplay $Root
  $rootRe = Get-ProjectsRootRegex $Root
  $why = $null
  $shellTools = @('Bash', 'PowerShell', 'Shell')
  $createHere = '(?i)\b(mkdir|md|New-Item|ni|git\s+clone|git\s+worktree\s+add|Expand-Archive|touch|Out-File|Set-Content|tee)\b|>'
  if (($shellTools -contains $Tool) -and (Test-SessionInProjectsRoot $Cwd $Root)) {
    $absRe = $rootRe + '[\\/]+(active|_archive|_scratch|_claude|_tools|_refs)\b'
    $abs = [regex]::Matches($Text, $absRe).Count
    if (($Text -match $createHere) -and $abs -eq 0) {
      $why = "this session is in the projects root ($display), so a relative create would land there. cd into $display\active\<project> first, or use a full path under $display\active\"
    }
  }
  $allowed = @('active', '_archive', '_scratch', '_claude', '_tools', '_refs', 'AGENTS.md', '.cursor')
  $segRe = $rootRe + '[\\/]+([^\\/\s"' + "'" + '`;|&)<>*?]+)'
  $keywords = Get-DenyKeywords
  foreach ($m in [regex]::Matches($Text, $segRe)) {
    $seg = $m.Groups[1].Value
    if ($allowed -notcontains $seg) {
      $why = "'$seg' is not an allowed projects root entry"
      break
    }
    if ($keywords -and (@('_scratch', '_tools') -contains $seg) -and ($Text -match ('(?i)(?:' + $keywords + ')'))) {
      $why = "that name is not allowed in $display\$seg. See $display\AGENTS.md"
      break
    }
  }
  if (-not $why) {
    $looseRe = $rootRe + '[\\/]+[^\\/\s"' + "'" + '`;|&)<>*?]+\.(md|html|json|txt|py|ps1)\b'
    $agentsRe = $rootRe + '[\\/]+AGENTS\.md\b'
    if (($Text -match $looseRe) -and ($Text -notmatch $agentsRe)) {
      $why = 'no loose files in the projects root'
    }
  }
  return $why
}
