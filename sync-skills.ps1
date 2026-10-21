# sync-skills.ps1 - install skills for Claude Code/Desktop and Cursor from one or more repo skills/ folders.
# Usage: .\sync-skills.ps1 -From <handbuilt-cad clone>\skills -From <workstation-repo>\skills [-WhatIf]
# (install.ps1 uses link-skills.ps1 instead, which links rather than copies.)
# Backs up any same-name skill folder before replacing; never touches other skills; no deletes.
# Writes .source (repo@commit) into each installed skill. Stops if a skill name is in two sources.
[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(Mandatory = $true)][string[]]$From,
      [string[]]$Targets = @("$env:USERPROFILE\.claude\skills", "$env:USERPROFILE\.cursor\skills"),
      [string]$BackupRoot = "$env:USERPROFILE\.skills-backup")
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format yyyyMMdd-HHmmss
$seen = @{}
$plan = @()
foreach ($src in $From) {
  $src = (Resolve-Path $src).Path
  $repo = Split-Path $src -Parent
  $commit = (& git -C $repo rev-parse --short HEAD 2>$null)
  $origin = (& git -C $repo remote get-url origin 2>$null)
  $label = if ($origin) { $origin } else { Split-Path $repo -Leaf }
  foreach ($skill in Get-ChildItem $src -Directory) {
    if (-not (Test-Path (Join-Path $skill.FullName 'SKILL.md'))) { continue }
    if ($seen.ContainsKey($skill.Name)) { throw "skill '$($skill.Name)' is in both $($seen[$skill.Name]) and $src; fix one source first" }
    $seen[$skill.Name] = $src
    $plan += [pscustomobject]@{ Name = $skill.Name; Path = $skill.FullName; Source = "$label@$commit" }
  }
}
foreach ($p in $plan) {
  foreach ($t in $Targets) {
    $dest = Join-Path $t $p.Name
    if (-not $PSCmdlet.ShouldProcess($dest, "install $($p.Name) from $($p.Source)")) { continue }
    New-Item -ItemType Directory -Force $t | Out-Null
    if (Test-Path $dest) {
      $b = Join-Path $BackupRoot "$stamp\$(Split-Path (Split-Path $t) -Leaf)\$($p.Name)"
      New-Item -ItemType Directory -Force (Split-Path $b) | Out-Null
      Move-Item $dest $b
    }
    Copy-Item $p.Path $dest -Recurse
    Set-Content -Path (Join-Path $dest '.source') -Value $p.Source -Encoding ascii
    Write-Output "installed $($p.Name) -> $dest ($($p.Source))"
  }
}
