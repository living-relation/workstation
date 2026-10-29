# link-skills.ps1 - link this repo's skills into ~\.claude\skills as junctions (a git pull updates them). Cursor also reads
# ~\.claude\skills, so linking into ~\.cursor\skills too made every skill show up twice there.
# Usage: .\link-skills.ps1 [-From <skills folder>] [-WhatIf]   (default: this repo's skills\)
# A same-name skill that is not already this link is moved to -BackupRoot first; never touches other skills.
# The only delete: a junction into -From whose skill is gone (renamed or removed) is removed - the link only.
# -Retire: skill names that were merged or removed; a same-name folder or link in -Targets is moved to
# -BackupRoot\<stamp>\retired\ (never deleted). -Unlink: folders (default ~\.cursor\skills) where an old junction into -From
# is removed (the link only, never its target); anything else there is never touched. Stops if a skill name is in two sources. Output: one object per link (Path, Target, Action). install.ps1 runs it.
[CmdletBinding(SupportsShouldProcess = $true)]
param([string[]]$From = @((Join-Path $PSScriptRoot 'skills')),
      [string[]]$Targets = @("$env:USERPROFILE\.claude\skills"),
      [string[]]$Unlink = @("$env:USERPROFILE\.cursor\skills"),
      [string]$BackupRoot = "$env:USERPROFILE\.skills-backup",
      [string[]]$Retire = @('handoff-sync-continue'))
$ErrorActionPreference = 'Stop'
# Claude-app-owned skills (harness.design plugin): names in <From>\EXCLUDE.txt, or any SKILL.md whose frontmatter has
# `source: harness-design-app`. Never linked, and a folder or link with that name in -Targets/-Unlink is NEVER moved,
# backed up aside, replaced, retired or removed. Logged as 'SKIP harness app skill'.
function Test-HarnessAppSkill([string]$Dir) {
  $md = Join-Path $Dir 'SKILL.md'
  if (-not (Test-Path -LiteralPath $md -PathType Leaf)) { return $false }
  $text = Get-Content -LiteralPath $md -Raw -ErrorAction SilentlyContinue
  if (-not $text -or -not $text.StartsWith('---')) { return $false }
  $m = [regex]::Match($text.Substring(3), '(?s)^\r?\n?(.*?)\r?\n---')
  if (-not $m.Success) { return $false }
  return [regex]::IsMatch($m.Groups[1].Value, '(?m)^source:\s*[''"]?harness-design-app[''"]?\s*$')
}
$excluded = @{}
foreach ($src in $From) {
  $ex = Join-Path $src 'EXCLUDE.txt'
  if (Test-Path -LiteralPath $ex -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $ex) { $n = ($line -split '#', 2)[0].Trim(); if ($n) { $excluded[$n] = $true } }
  }
}
function Test-Protected([string]$Name, [string]$Path) {
  if ($excluded.ContainsKey($Name)) { return $true }
  if ($Path -and (Test-Path -LiteralPath $Path)) { return (Test-HarnessAppSkill $Path) }
  return $false
}
function Write-Skip([string]$Path, [string]$Why) {
  Write-Host "SKIP harness app skill: $Path ($Why)"
  [pscustomobject]@{ Path = $Path; Target = $null; Action = 'SKIP harness app skill' }
}
$stamp = Get-Date -Format yyyyMMdd-HHmmss
$seen = @{}
$plan = @()
foreach ($src in $From) {
  $src = (Resolve-Path -LiteralPath $src).Path
  foreach ($skill in Get-ChildItem -LiteralPath $src -Directory) {
    # Only folders with SKILL.md are skills. Zip files beside them (skills\<name>.zip) are Claude import packages, not linked.
    if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
    if ($excluded.ContainsKey($skill.Name) -or (Test-HarnessAppSkill $skill.FullName)) { $excluded[$skill.Name] = $true; Write-Skip $skill.FullName 'excluded in source'; continue }
    if ($seen.ContainsKey($skill.Name)) { throw "skill '$($skill.Name)' is in both $($seen[$skill.Name]) and $src; fix one source first" }
    $seen[$skill.Name] = $src
    $plan += $skill
  }
}
foreach ($s in $plan) {
  $want = $s.FullName.TrimEnd('\')
  foreach ($t in $Targets) {
    $dest = Join-Path $t $s.Name
    if (Test-Protected $s.Name $dest) { Write-Skip $dest 'target is a harness app skill'; continue }
    $item = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction' -and (@($item.Target | ForEach-Object { $_.TrimEnd('\') }) -icontains $want)) {
      [pscustomobject]@{ Path = $dest; Target = $want; Action = 'ok' }; continue
    }
    if (-not $PSCmdlet.ShouldProcess($dest, "link -> $want")) { [pscustomobject]@{ Path = $dest; Target = $want; Action = 'would-link' }; continue }
    New-Item -ItemType Directory -Force $t | Out-Null
    $backup = $null
    if ($item) {
      $backup = Join-Path $BackupRoot "$stamp\$(Split-Path (Split-Path $t) -Leaf)\$($s.Name)"
      New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
      Move-Item -LiteralPath $dest $backup
    }
    New-Item -ItemType Junction -Path $dest -Target $want | Out-Null
    [pscustomobject]@{ Path = $dest; Target = $want; Backup = $backup; Action = $(if ($backup) { "relinked; the old one is backed up at $backup" } else { 'linked' }) }
  }
}
# Prune: remove only junctions in -Targets that point into a -From folder at a skill that is gone (the link only, never
# its target). Links to anything else, and real folders, are never touched.
$roots = @($From | ForEach-Object { (Resolve-Path -LiteralPath $_).Path.TrimEnd('\') + '\' })
foreach ($t in $Targets) {
  foreach ($item in @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | Where-Object { $_.LinkType -eq 'Junction' })) {
    $tgt = "$(@($item.Target)[0])".TrimEnd('\')
    if (-not @($roots | Where-Object { $tgt.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count) { continue }
    if (Test-Path -LiteralPath (Join-Path $tgt 'SKILL.md')) { continue }
    # A broken junction into this repo's skills\ (target gone) is only a dead link: prune it even for an excluded name.
    # Real folders are never pruned here, and a non-broken link of an excluded or marked skill stays protected.
    if ((Test-Path -LiteralPath $tgt) -and (Test-Protected $item.Name $item.FullName)) { Write-Skip $item.FullName 'not pruned'; continue }
    if (-not $PSCmdlet.ShouldProcess($item.FullName, "remove dead skill link -> $tgt")) { [pscustomobject]@{ Path = $item.FullName; Target = $tgt; Action = 'would-prune' }; continue }
    [IO.Directory]::Delete($item.FullName, $false)
    [pscustomobject]@{ Path = $item.FullName; Target = $tgt; Action = 'pruned' }
  }
}
# Unlink: remove only junctions in -Unlink folders that point into a -From folder (the link only, never its target),
# so a skill is not listed twice in Cursor. Real folders and links to anything else are never touched.
foreach ($u in @($Unlink | Where-Object { $_ -and ($Targets -notcontains $_) })) {
  foreach ($item in @(Get-ChildItem -LiteralPath $u -Force -ErrorAction SilentlyContinue | Where-Object { $_.LinkType -eq 'Junction' })) {
    $tgt = "$(@($item.Target)[0])".TrimEnd('\')
    if (-not @($roots | Where-Object { ($tgt + '\').StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count) { continue }
    if (Test-Protected $item.Name $item.FullName) { Write-Skip $item.FullName 'not unlinked'; continue }
    if (-not $PSCmdlet.ShouldProcess($item.FullName, "remove duplicate skill link -> $tgt")) { [pscustomobject]@{ Path = $item.FullName; Target = $tgt; Action = 'would-unlink' }; continue }
    [IO.Directory]::Delete($item.FullName, $false)
    [pscustomobject]@{ Path = $item.FullName; Target = $tgt; Action = 'unlinked' }
  }
}
# Retire: move (never delete) a retired skill's old folder or link out of -Targets into -BackupRoot.
foreach ($name in $Retire) {
  if ($seen.ContainsKey($name)) { continue }
  foreach ($t in $Targets) {
    $dest = Join-Path $t $name
    $item = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    if (-not $item) { continue }
    if (Test-Protected $name $dest) { Write-Skip $dest 'not retired'; continue }
    $backup = Join-Path $BackupRoot "$stamp\retired\$(Split-Path (Split-Path $t) -Leaf)\$name"
    if (-not $PSCmdlet.ShouldProcess($dest, "move retired skill to $backup")) { [pscustomobject]@{ Path = $dest; Target = $backup; Action = 'would-retire' }; continue }
    New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
    if ($item.LinkType) { New-Item -ItemType Junction -Path $backup -Target "$(@($item.Target)[0])" | Out-Null; [IO.Directory]::Delete($item.FullName, $false) }
    else { Move-Item -LiteralPath $dest $backup }
    [pscustomobject]@{ Path = $dest; Target = $backup; Action = 'retired' }
  }
}
