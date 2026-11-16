#Requires -Version 5.1
# Manual. Compares each claude.ai synced skill with this repo.
# Synced copies live at ~\.claude\skills\synced\<bucket>\<name>.
# claude.ai rewrites frontmatter, so only the body after the frontmatter is compared.
# Lists zips that need a fresh upload, and repo skills that are not on claude.ai at all.
# Does not change any files. No schedule. No sign-in item.
param(
    [string]$SkillsRoot,
    [string]$SyncedRoot,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
if (-not $SkillsRoot) {
    $top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $top) { $top = Split-Path -Parent $PSScriptRoot }
    $SkillsRoot = Join-Path $top 'skills'
}
if (-not $SyncedRoot) {
    $homeDir = $env:USERPROFILE
    if (-not $homeDir) { $homeDir = $HOME }
    $SyncedRoot = Join-Path (Join-Path $homeDir '.claude\skills') 'synced'
}

function Get-SkillBody([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
    if ($text.StartsWith('---')) {
        $m = [regex]::Match($text.Substring(3), '(?s)^\n?(.*?)\n---\n?')
        if ($m.Success) { $text = $text.Substring(3 + $m.Length) }
    }
    return $text.TrimEnd("`n")
}

function Get-RepoSkills([string]$Root) {
    $out = @()
    if (-not (Test-Path -LiteralPath $Root)) { return $out }
    foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
        $md = Join-Path $d.FullName 'SKILL.md'
        if (Test-Path -LiteralPath $md -PathType Leaf) { $out += $d }
    }
    return $out
}

$buckets = @()
if (Test-Path -LiteralPath $SyncedRoot -PathType Container) {
    $buckets = @(Get-ChildItem -LiteralPath $SyncedRoot -Directory -Force -ErrorAction SilentlyContinue)
}

$need = 0
Write-Host ''
Write-Host '==== Skills drift ====' -ForegroundColor Cyan
Write-Host "  repo:   $SkillsRoot"
Write-Host "  synced: $SyncedRoot"
if (-not $buckets.Count) { Write-Host '  no synced buckets (claude.ai has not synced a skill copy here)' }
Write-Host ''

foreach ($skill in @(Get-RepoSkills $SkillsRoot)) {
    $name = $skill.Name
    $repoMd = Join-Path $skill.FullName 'SKILL.md'
    $repoBody = Get-SkillBody $repoMd
    $zip = "skills/$name.zip"
    $found = $false
    foreach ($b in $buckets) {
        $copy = Join-Path (Join-Path $b.FullName $name) 'SKILL.md'
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) {
            Write-Host "MISSING $zip  ($($b.Name) has no copy)" -ForegroundColor Yellow
            $need++
            continue
        }
        $found = $true
        $syncedBody = Get-SkillBody $copy
        if ($syncedBody -eq $repoBody) {
            Write-Host "OK $name  ($($b.Name))" -ForegroundColor Green
        } else {
            Write-Host "RE-UPLOAD $zip  ($($b.Name) body differs)" -ForegroundColor Yellow
            $need++
        }
    }
    if (-not $found) {
        Write-Host "NOT ON CLAUDE.AI $zip" -ForegroundColor Yellow
        $need++
    }
}

Write-Host ''
if ($need) { Write-Host "$need item(s) need an upload at claude.ai: Customize > Skills > Upload" -ForegroundColor Yellow }
else { Write-Host 'Synced copies match this repo.' -ForegroundColor Green }
if (-not $NoPause) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
if ($need) { exit 1 }
exit 0
