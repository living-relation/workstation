# Keeps Claude Code's memory folder pointed at the one shared store.
# Silent when everything is fine. Never deletes notes.
# Also warns (never blocks, moves or deletes) when a write to the store looks like
# project progress; that belongs in the repo's in-repo state file.
# Portable: no hardcoded profile, user or machine names. Paths are worked out at run time:
#   link  = autoMemoryDirectory from ~\.claude\settings.json (~ expanded); this is the junction.
#   store = storePath from the optional ~\.claude\hooks\memory-link-guard.config.json, else the
#           junction's current target, else ~\Projects\_claude\Claude Projects\Working Memory\memory.
#   Projects root = the first folder above the store that contains _claude.
# Worktrees (a .git file pointing into <repo>\.git\worktrees\) use the main repo's project folder;
# no folder is ever made per worktree.
# Also keeps ~\.claude\working-memory (a junction to the store, the same path on every PC; Cowork / Chat
# pointer lines use it): recreated only when missing, never changed when it is a real folder or another link.
$ErrorActionPreference = 'SilentlyContinue'
$userHome = $env:USERPROFILE
if (-not $userHome) { $userHome = $HOME }
function Expand-UserPath([string]$p) {
  if (-not $p) { return $null }
  $sep = [IO.Path]::DirectorySeparatorChar
  $p = ([Environment]::ExpandEnvironmentVariables($p.Trim()) -replace '[\\/]', $sep) -replace '^\\\?\?\\', ''
  if ($p -eq '~') { $p = $userHome } elseif ($p.StartsWith("~$sep")) { $p = Join-Path $userHome $p.Substring(2) }
  return $p.TrimEnd('\', '/')
}
# One stdin read: SessionStart (cwd) and PreToolUse Write/Edit (file_path + content).
$hookIn = $null
if ([Console]::IsInputRedirected) {
  $rawIn = [Console]::In.ReadToEnd()
  if ($rawIn) { try { $hookIn = $rawIn | ConvertFrom-Json } catch { } }
}
function Get-PathKey([string]$p) {
  if (-not $p) { return '' }
  $p = Expand-UserPath $p
  try { $p = [IO.Path]::GetFullPath(($p -replace '[\\/]', [IO.Path]::DirectorySeparatorChar)) } catch { }
  return $p.TrimEnd('\', '/').ToLowerInvariant()
}
function Test-UnderStore([string]$Path, [string]$Root) {
  if (-not $Path -or -not $Root) { return $false }
  $a = Get-PathKey $Path; $b = Get-PathKey $Root
  if (-not $a -or -not $b) { return $false }
  return ($a -eq $b) -or $a.StartsWith($b + [IO.Path]::DirectorySeparatorChar) -or $a.StartsWith($b + '\') -or $a.StartsWith($b + '/')
}
# status/progress/next-steps/PR/branch/TODO language, or a project_* note with that content.
function Test-ProgressNote([string]$NotePath, [string]$Text) {
  $leaf = Split-Path $NotePath -Leaf
  if ($leaf -match '(?i)^(INDEX|MEMORY|CLAUDE)\.md$') { return $false }
  $stem = [IO.Path]::GetFileNameWithoutExtension($leaf)
  $lang = '(?i)(\b(project[- ]?)?(status|progress)\b|\bnext[- ]steps?\b|\bTODOs?\b|\bpull request\b|\bPR\s*#\d+\b|\bopen PRs?\b|\bcurrent branch\b|\bon branch\b|\bfeature branch\b)'
  $nameHit = $stem -match '(?i)(status|progress|next[-_ ]?steps?|todos?)'
  $bodyHit = $Text -and [regex]::IsMatch($Text, $lang)
  $projectStar = $stem -match '(?i)^project[_-]'
  return [bool]($nameHit -or $bodyHit -or ($projectStar -and $bodyHit))
}

# Link: the folder Claude Code reads for auto memory.
$link = $null
try { $link = Expand-UserPath ((Get-Content -LiteralPath (Join-Path $userHome '.claude\settings.json') -Raw | ConvertFrom-Json).autoMemoryDirectory) } catch { }

# Store: explicit config first, then wherever the junction already points, then the default.
$home_ = $null
$cfg = Join-Path $userHome '.claude\hooks\memory-link-guard.config.json'
if (Test-Path -LiteralPath $cfg) { try { $home_ = Expand-UserPath ((Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).storePath) } catch { } }
if (-not $home_ -and $link) {
  $li = Get-Item -LiteralPath $link -Force
  if ($li -and $li.LinkType) { $home_ = Expand-UserPath (@($li.Target)[0]) }
}
if (-not $home_) { $home_ = Join-Path $userHome 'Projects\_claude\Claude Projects\Working Memory\memory' }

# Projects root: walk up from the store to the folder that contains _claude.
$projRoot = $null
$d = Split-Path $home_ -Parent
while ($d) {
  if (Test-Path -LiteralPath (Join-Path $d '_claude') -PathType Container) { $projRoot = $d; break }
  $d = Split-Path $d -Parent
}
if (-not $projRoot) { $projRoot = Join-Path $userHome 'Projects' }

# No autoMemoryDirectory in settings: use Claude Code's own folder name for the Projects root.
if (-not $link) { $link = Join-Path $userHome ('.claude\projects\' + ($projRoot -replace '[^A-Za-z0-9]', '-') + '\memory') }

if (-not (Test-Path -LiteralPath $home_)) { Write-Output "MEMORY WARNING: shared memory folder is missing: $home_. Tell the user before saving any memory."; exit 0 }

# Warn only when a write to the store looks like project progress. Never block, move or delete.
try {
  $ti = $null
  if ($hookIn -and $hookIn.PSObject.Properties['tool_input']) { $ti = $hookIn.tool_input }
  $notePath = $null
  if ($ti) {
    if ($ti.PSObject.Properties['file_path'] -and $ti.file_path) { $notePath = [string]$ti.file_path }
    elseif ($ti.PSObject.Properties['path'] -and $ti.path) { $notePath = [string]$ti.path }
  }
  if ($notePath -and (Test-UnderStore $notePath $home_)) {
    $noteText = ''
    if ($ti.PSObject.Properties['content'] -and $ti.content) { $noteText = [string]$ti.content }
    elseif ($ti.PSObject.Properties['new_string'] -and $ti.new_string) { $noteText = [string]$ti.new_string }
    elseif (Test-Path -LiteralPath $notePath -PathType Leaf) { try { $noteText = [IO.File]::ReadAllText($notePath) } catch { } }
    if (Test-ProgressNote $notePath $noteText) {
      Write-Output "MEMORY WARNING: '$notePath' looks like project progress/state. Put that in the repo's in-repo state file instead (the one AGENTS.md names, e.g. STATE.md). Local Working Memory holds only preferences, rules and cross-project facts; each fact is written once. This is a warning only; the note was not blocked, moved or deleted."
    }
  }
} catch { }
# If autoMemoryDirectory points straight at the store, there is no junction to manage. Never move the store onto itself.
$sameAsStore = ([IO.Path]::GetFullPath($link).TrimEnd('\').ToLower() -eq [IO.Path]::GetFullPath($home_).TrimEnd('\').ToLower())
$item = Get-Item -LiteralPath $link -Force
$linkOk = ($item -and $item.LinkType -eq 'Junction' -and (@($item.Target | ForEach-Object { ($_ -replace '^\\\?\?\\', '').TrimEnd('\').ToLower() }) -contains $home_.TrimEnd('\').ToLower()))
if (-not $linkOk -and -not $sameAsStore) {
$msg = @()
if ($item -and -not $item.LinkType) {
  # A real folder appeared (an app recreated it). Move its notes into the shared store, never overwrite.
  $base = (Get-Item -LiteralPath $link -Force).FullName.TrimEnd('\')
  foreach ($f in Get-ChildItem -LiteralPath $base -File -Recurse) {
    $rel = $f.FullName.Substring($base.Length).TrimStart('\')
    $dest = Join-Path $home_ $rel
    if (Test-Path -LiteralPath $dest) {
      if ((Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $f.FullName).Hash) { continue }
      $dest = [IO.Path]::ChangeExtension($dest, ".conflict-$(Get-Date -Format yyyyMMddHHmmss)" + [IO.Path]::GetExtension($dest))
      $msg += "kept a conflicting copy: $dest"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Move-Item -LiteralPath $f.FullName -Destination $dest
  }
  Remove-Item -LiteralPath $link -Recurse -Force
} elseif ($item) {
  # A junction/link pointing somewhere else: remove only the link, never its target's contents.
  [IO.Directory]::Delete($link)
}
New-Item -ItemType Directory -Force -Path (Split-Path $link -Parent) | Out-Null
New-Item -ItemType Junction -Path $link -Target $home_ | Out-Null
Write-Output ("MEMORY NOTE: re-linked Claude Code memory to the shared store. " + ($msg -join '; ') + " Merge any .conflict files into the real notes.")
}

# Path-independent alias: ~\.claude\working-memory -> store. Recreate it only when nothing is there.
# A real folder, a file or a link to somewhere else is left alone (warning only); nothing is deleted.
try {
  $wm = Join-Path $userHome '.claude\working-memory'
  $wi = Get-Item -LiteralPath $wm -Force
  if (-not $wi) {
    New-Item -ItemType Directory -Force -Path (Split-Path $wm -Parent) | Out-Null
    New-Item -ItemType Junction -Path $wm -Target $home_ | Out-Null
    if (Test-Path -LiteralPath $wm) { Write-Output "MEMORY NOTE: recreated the link $wm -> $home_ (used by Cowork / Chat memory pointer lines)." }
  } elseif (-not $wi.LinkType) {
    Write-Output "MEMORY WARNING: $wm is a real folder or file, not a link to the shared store ($home_). Left alone; Cowork / Chat memory pointer lines will not reach the shared notes on this PC. Tell the user."
  } elseif (-not (@($wi.Target | ForEach-Object { ($_ -replace '^\\\?\?\\', '').TrimEnd('\').ToLower() }) -contains $home_.TrimEnd('\').ToLower())) {
    Write-Output ("MEMORY WARNING: $wm is a $($wi.LinkType) to '" + (@($wi.Target) -join ';') + "', not the shared store ($home_). Left alone. Tell the user.")
  }
} catch { }

# Per-project memory folder: find the project from the working directory and make sure the
# store has <slug>\INDEX.md plus a line in MEMORY.md. Only for projects under <Projects>\active.
try {
  $cwd = $null
  if ($hookIn -and $hookIn.PSObject.Properties['cwd'] -and $hookIn.cwd) { $cwd = [string]$hookIn.cwd }
  if (-not $cwd) { $cwd = (Get-Location).ProviderPath }
  $active = Join-Path $projRoot 'active'
  $full = [IO.Path]::GetFullPath($cwd).TrimEnd('\')
  if ($full.ToLower().StartsWith($active.ToLower() + '\')) {
    $rel = $full.Substring($active.Length + 1)
    $top = Join-Path $active ($rel.Split('\')[0])
    $proj = $top
    # git root wins if it is inside the project folder
    $d = $full
    while ($d -and $d.Length -ge $top.Length) {
      $g = Join-Path $d '.git'
      if (Test-Path -LiteralPath $g) {
        $proj = $d
        # A git worktree has a .git FILE ("gitdir: <main repo>\.git\worktrees\<name>").
        # Use the main repo, so worktree sessions share the parent's memory folder
        # (matches Claude Code: all worktrees of a repo share one auto memory directory).
        if (Test-Path -LiteralPath $g -PathType Leaf) {
          $gd = ((Get-Content -LiteralPath $g -TotalCount 1) -replace '^gitdir:\s*', '').Trim()
          if ($gd) {
            if (-not [IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $d $gd }
            $gd = [IO.Path]::GetFullPath(($gd -replace '/', '\'))
            $k = $gd.ToLower().IndexOf('\.git\worktrees\')
            if ($k -gt 0) { $proj = $gd.Substring(0, $k) }
          }
        }
        break
      }
      $d = Split-Path $d -Parent
    }
    $name = Split-Path $proj -Leaf
    $slug = ($name.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug -and -not (Test-Path -LiteralPath (Join-Path $home_ $slug)) -and -not (Test-Path -LiteralPath (Join-Path $home_ "_archive\$slug"))) {
      $enc = New-Object Text.UTF8Encoding $false
      $today = Get-Date -Format yyyy-MM-dd
      $sig = "-- memory-link-guard, $today"
      New-Item -ItemType Directory -Path (Join-Path $home_ $slug) | Out-Null
      [IO.File]::WriteAllText((Join-Path $home_ "$slug\INDEX.md"), "# $name - memory index`r`n`r`nProject folder: ``$proj```r`n`r`n(No notes yet.)`r`n`r`nIndex created. $sig`r`n", $enc)
      $mem = Join-Path $home_ 'MEMORY.md'
      $mt = [IO.File]::ReadAllText($mem, $enc)
      if (-not $mt.Contains("($slug/INDEX.md)")) {
        $nl = if ($mt.Contains("`r`n")) { "`r`n" } else { "`n" }
        $line = "- [$name]($slug/INDEX.md) - no notes yet. $sig"
        $lines = [Collections.Generic.List[string]]($mt -split "`r?`n")
        $h = $lines.IndexOf('## Projects')
        if ($h -ge 0) {
          $at = $h + 1
          for ($i = $h + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -like '## *') { break }; if ($lines[$i] -like '- *') { $at = $i + 1 } }
          $lines.Insert($at, $line)
          $mt = $lines -join $nl
        } else { $mt = $mt.TrimEnd() + $nl + $line + $nl }
        [IO.File]::WriteAllText($mem, $mt, $enc)
      }
      Write-Output "MEMORY NOTE: created project memory folder $slug\INDEX.md in the shared store."
    }
  }
} catch { }
exit 0
