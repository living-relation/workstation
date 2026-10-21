# link-skills.ps1 - link this repo's skills into Claude Code/Desktop and Cursor as junctions (a git pull updates them).
# Usage: .\link-skills.ps1 [-From <skills folder>] [-WhatIf]   (default: this repo's skills\)
# A same-name skill that is not already this link is moved to -BackupRoot first; never touches other skills; no deletes.
# Stops if a skill name is in two sources. Output: one object per link (Path, Target, Action). install.ps1 runs it.
[CmdletBinding(SupportsShouldProcess = $true)]
param([string[]]$From = @((Join-Path $PSScriptRoot 'skills')),
      [string[]]$Targets = @("$env:USERPROFILE\.claude\skills", "$env:USERPROFILE\.cursor\skills"),
      [string]$BackupRoot = "$env:USERPROFILE\.skills-backup")
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format yyyyMMdd-HHmmss
$seen = @{}
$plan = @()
foreach ($src in $From) {
  $src = (Resolve-Path -LiteralPath $src).Path
  foreach ($skill in Get-ChildItem -LiteralPath $src -Directory) {
    if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'SKILL.md'))) { continue }
    if ($seen.ContainsKey($skill.Name)) { throw "skill '$($skill.Name)' is in both $($seen[$skill.Name]) and $src; fix one source first" }
    $seen[$skill.Name] = $src
    $plan += $skill
  }
}
foreach ($s in $plan) {
  $want = $s.FullName.TrimEnd('\')
  foreach ($t in $Targets) {
    $dest = Join-Path $t $s.Name
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
