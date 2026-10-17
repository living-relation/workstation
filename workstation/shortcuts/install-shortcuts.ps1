#Requires -Version 5.1
# Creates (or recreates) the three Workstation shortcuts in a 'Workstation' folder on this PC's desktop,
# pointing at this folder. Also removes old copies of those five links left loose on the desktop
# (only links that run one of these bridge scripts). Idempotent; no admin needed.
# Afterwards it runs read-only prerequisite checks.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install-shortcuts.ps1 [-SkipChecks] [-NoPause]
param([switch]$SkipChecks, [switch]$NoPause)
$ErrorActionPreference = 'Continue'

$here    = $PSScriptRoot
$desktop = [Environment]::GetFolderPath('Desktop')   # may be a OneDrive-redirected Desktop
$linkDir = Join-Path $desktop 'Workstation'
$oldLinkDir = Join-Path $desktop 'Bridge'   # pre-rename folder; old links in it are removed
$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shell32 = Join-Path $env:SystemRoot 'System32\shell32.dll'

$links = @(
    @{ Name = 'Workers Start';      Script = 'workers-start.ps1';  Icon = 137 },
    @{ Name = 'Workers Stop';   Script = 'workers-stop.ps1';   Icon = 131 },
    @{ Name = 'Workstation Status'; Script = 'workstation-status.ps1'; Icon = 23 }
)

Write-Host ''
Write-Host "==== Install Workstation shortcuts ====  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  scripts: $here"
Write-Host "  links:   $linkDir"
Write-Host ''

$failed = 0
$wsh = New-Object -ComObject WScript.Shell

if (-not (Test-Path -LiteralPath $linkDir)) {
    New-Item -ItemType Directory -Path $linkDir -Force | Out-Null
    Write-Host "  [ OK ] created folder $linkDir" -ForegroundColor Green
}
foreach ($l in $links) {
    $script = Join-Path $here $l.Script
    $lnkPath = Join-Path $linkDir ($l.Name + '.lnk')
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Host "  [FAIL] $($l.Name): missing $script" -ForegroundColor Red; $failed++; continue
    }
    try {
        $existed = Test-Path -LiteralPath $lnkPath
        $s = $wsh.CreateShortcut($lnkPath)
        $s.TargetPath       = $psExe
        $s.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
        $s.WorkingDirectory = $here
        $s.WindowStyle      = 1
        $s.Description      = "$($l.Name) (workstation manual shortcut)"
        $s.IconLocation     = "$shell32,$($l.Icon)"
        $s.Save()
        $check = $wsh.CreateShortcut($lnkPath)
        if ($check.TargetPath -ieq $psExe -and $check.Arguments -like "*$($l.Script)*" -and $check.WorkingDirectory -ieq $here) {
            $verb = if ($existed) { 'updated' } else { 'created' }
            Write-Host "  [ OK ] $($l.Name).lnk $verb -> $($l.Script)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($l.Name).lnk did not read back as expected" -ForegroundColor Red; $failed++
        }
    } catch {
        Write-Host "  [FAIL] $($l.Name): $($_.Exception.Message)" -ForegroundColor Red; $failed++
    }
}

# Remove old copies (loose on the desktop, or pre-rename names/folder), but only links that run one of these scripts.
$oldNames = @{ 'workers-start.ps1' = 'Bridge Start'; 'workers-stop.ps1' = 'Bridge Stop'; 'workstation-status.ps1' = 'Bridge Status' }  # pull/push batch-git archived 2026-10-17
$oldPaths = @()
foreach ($l in $links) {
    $oldPaths += [pscustomobject]@{ Path = (Join-Path $desktop ($l.Name + '.lnk')); Script = $l.Script; Name = $l.Name }
    $on = $oldNames[$l.Script]
    if ($on) {
        $oldPaths += [pscustomobject]@{ Path = (Join-Path $desktop ($on + '.lnk')); Script = $l.Script; Name = $on }
        $oldPaths += [pscustomobject]@{ Path = (Join-Path $oldLinkDir ($on + '.lnk')); Script = $l.Script; Name = $on }
    }
}
foreach ($l in $oldPaths) {
    $loose = $l.Path
    if (-not (Test-Path -LiteralPath $loose)) { continue }
    try {
        $old = $wsh.CreateShortcut($loose)
        if ($old.TargetPath -match 'powershell\.exe$' -and $old.Arguments -match [regex]::Escape($l.Script)) {
            Remove-Item -LiteralPath $loose -Force
            Write-Host "  [ OK ] removed old link $loose" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] left $loose alone: it does not run $($l.Script)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] could not check/remove $loose : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Drop the pre-rename folder once it is empty.
if ((Test-Path -LiteralPath $oldLinkDir) -and -not (Get-ChildItem -LiteralPath $oldLinkDir -Force -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $oldLinkDir -Force
    Write-Host "  [ OK ] removed empty old folder $oldLinkDir" -ForegroundColor Green
} elseif (Test-Path -LiteralPath $oldLinkDir) {
    Write-Host "  [WARN] left $oldLinkDir alone: it still has other files" -ForegroundColor Yellow
}

if (-not $SkipChecks) {
    Write-Host ''
    try {
        . (Join-Path $here 'workstation-common.ps1')
        Show-Prerequisites
    } catch {
        Write-Host "  [WARN] prerequisite checks could not run: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ''
if ($failed -gt 0) { Write-Host "==== done with $failed failure(s) ====" -ForegroundColor Red }
else { Write-Host '==== done: 5 shortcuts in place ====' -ForegroundColor Green }
if (-not $NoPause) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
if ($failed -gt 0) { exit 1 }
