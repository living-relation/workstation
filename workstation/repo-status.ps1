#Requires -Version 5.1
<#
.SYNOPSIS
  Report git status for every entry under Projects\active\
#>
$ErrorActionPreference = 'Continue'
# Projects root from paths.ps1 (install.ps1's config file, else the clone's <Projects>\active\<repo> location).
. (Join-Path $PSScriptRoot 'paths.ps1')
$ProjectsRoot = $WsProjectsRoot
$ActiveRoot = Join-Path $ProjectsRoot 'active'

Write-Host "=== repo-status ===" -ForegroundColor Cyan
Write-Host "Projects: $ProjectsRoot"
Write-Host "Active:   $ActiveRoot"
Write-Host "Time:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

if (-not (Test-Path -LiteralPath $ActiveRoot)) {
    Write-Host "ERROR: active folder not found: $ActiveRoot" -ForegroundColor Red
    exit 1
}

$entries = Get-ChildItem -LiteralPath $ActiveRoot -Force | Sort-Object Name
if (-not $entries) {
    Write-Host "(active is empty)"
    exit 0
}

foreach ($entry in $entries) {
    $name = $entry.Name
    $path = $entry.FullName

    if ($entry.PSIsContainer -eq $false) {
        Write-Host "[file] $name" -ForegroundColor DarkGray
        Write-Host "  path: $path"
        Write-Host ""
        continue
    }

    $gitDir = Join-Path $path '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        Write-Host "[no-git] $name" -ForegroundColor Yellow
        Write-Host "  path: $path"
        Write-Host ""
        continue
    }

    Push-Location -LiteralPath $path
    try {
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
        if (-not $branch) { $branch = '(unknown)' }

        $remotes = @(git remote -v 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $remoteNames = @(git remote 2>$null)

        $statusPorcelain = @(git status --porcelain 2>$null)
        $dirty = if ($statusPorcelain.Count -gt 0) { 'DIRTY' } else { 'clean' }

        $upstream = (git rev-parse --abbrev-ref '--symbolic-full-name' '@{u}' 2>$null)
        $aheadBehind = $null
        if ($upstream) {
            $counts = (git rev-list --left-right --count '@{u}...HEAD' 2>$null)
            if ($counts) {
                $parts = $counts -split '\s+'
                if ($parts.Count -ge 2) {
                    $aheadBehind = "behind=$($parts[0]) ahead=$($parts[1]) vs $upstream"
                }
            }
        }

        Write-Host "[git] $name" -ForegroundColor Green
        Write-Host "  path:   $path"
        Write-Host "  branch: $branch"
        Write-Host "  state:  $dirty"
        if ($aheadBehind) { Write-Host "  sync:   $aheadBehind" }
        if ($remoteNames.Count -eq 0) {
            Write-Host "  remote: (none)" -ForegroundColor Yellow
        } else {
            Write-Host "  remotes:"
            foreach ($r in $remotes) {
                if ($r -match '\(fetch\)$') {
                    Write-Host "    $r"
                }
            }
        }
        if ($statusPorcelain.Count -gt 0 -and $statusPorcelain.Count -le 20) {
            Write-Host "  changes:"
            foreach ($line in $statusPorcelain) { Write-Host "    $line" }
        } elseif ($statusPorcelain.Count -gt 20) {
            Write-Host "  changes: $($statusPorcelain.Count) files (truncated)"
        }
    } finally {
        Pop-Location
    }
    Write-Host ""
}

Write-Host "=== done ===" -ForegroundColor Cyan
