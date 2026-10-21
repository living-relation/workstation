#Requires -Version 5.1
# Creates (or recreates) the Workstation shortcuts listed in toolkit.psd1 (Shortcuts) in -LinkDir, pointing at
# this clone, and the sign-in links (StartupLinks) in -StartupDir (default: the user's Startup folder).
# An existing Startup link of the same name is replaced only when it runs the same script file name; it is backed up
# first to %LOCALAPPDATA%\Workstation\backups\startup-links-<time>\. -NoStartup skips the Startup links.
# install.ps1 passes -LinkDir = <workstation package/repo>\<ShortcutFolder from toolkit.psd1> (default 'shortcuts').
# Also removes old copies of these links left on the desktop: loose, or in the old Desktop 'Bridge' and
# 'Workstation' folders (only links that run one of these scripts), then those folders once empty.
# Idempotent; no admin needed. Afterwards it runs read-only prerequisite checks.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install-shortcuts.ps1 -LinkDir <folder> [-StartupDir <folder>] [-NoStartup] [-SkipChecks] [-NoPause]
param([string]$LinkDir, [string]$StartupDir, [switch]$NoStartup, [switch]$SkipChecks, [switch]$NoPause)
$ErrorActionPreference = 'Continue'

if (-not $LinkDir) {
    Write-Host '  [FAIL] -LinkDir is required: the folder for the shortcuts (install.ps1 passes <workstation repo>\shortcuts).' -ForegroundColor Red
    exit 1
}
$here    = $PSScriptRoot
$desktop = [Environment]::GetFolderPath('Desktop')   # may be a OneDrive-redirected Desktop
$linkDir = [IO.Path]::GetFullPath($LinkDir).TrimEnd('\')
# Old Desktop folders (pre-rename 'Bridge', and 'Workstation' from before the links moved into the repo).
$oldLinkDirs = @(@('Bridge', 'Workstation') | ForEach-Object { Join-Path $desktop $_ } | Where-Object { $_ -ine $linkDir })
$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shell32 = Join-Path $env:SystemRoot 'System32\shell32.dll'

$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$toolkit = Split-Path -Parent $here                      # <clone>\workstation
$tkFile  = Join-Path (Split-Path -Parent $toolkit) 'toolkit.psd1'
try { $TK = Import-PowerShellDataFile -LiteralPath $tkFile } catch {
    Write-Host "  [FAIL] cannot read $tkFile : $($_.Exception.Message)" -ForegroundColor Red; exit 1
}
$links = @($TK.Shortcuts | ForEach-Object {
    $p = Join-Path $toolkit $_.Script
    @{ Name = $_.Name; Script = (Split-Path $p -Leaf); Path = $p; Dir = (Split-Path $p -Parent); Args = [string]$_.Args; Icon = $(if ($_.Icon) { $_.Icon } else { 13 }) }
})
if (-not $StartupDir) { $StartupDir = [Environment]::GetFolderPath('Startup') }

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
    $script = $l.Path
    $lnkPath = Join-Path $linkDir ($l.Name + '.lnk')
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Host "  [FAIL] $($l.Name): missing $script" -ForegroundColor Red; $failed++; continue
    }
    try {
        $existed = Test-Path -LiteralPath $lnkPath
        $s = $wsh.CreateShortcut($lnkPath)
        $s.TargetPath       = $psExe
        $s.Arguments        = ("-NoProfile -ExecutionPolicy Bypass -File `"$script`" " + $l.Args).TrimEnd()
        $s.WorkingDirectory = $l.Dir
        $s.WindowStyle      = 1
        $s.Description      = "$($l.Name) (workstation manual shortcut)"
        $s.IconLocation     = "$shell32,$($l.Icon)"
        $s.Save()
        $check = $wsh.CreateShortcut($lnkPath)
        if ($check.TargetPath -ieq $psExe -and $check.Arguments -like "*$($l.Script)*" -and $check.WorkingDirectory -ieq $l.Dir) {
            $verb = if ($existed) { 'updated' } else { 'created' }
            Write-Host "  [ OK ] $($l.Name).lnk $verb -> $($l.Script)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($l.Name).lnk did not read back as expected" -ForegroundColor Red; $failed++
        }
    } catch {
        Write-Host "  [FAIL] $($l.Name): $($_.Exception.Message)" -ForegroundColor Red; $failed++
    }
}

# Sign-in links in the Startup folder.
$startupDone = 0
if (-not $NoStartup -and @($TK.StartupLinks).Count) {
    $suDir = [IO.Path]::GetFullPath($StartupDir).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $suDir)) { New-Item -ItemType Directory -Path $suDir -Force | Out-Null }
    $bkDir = Join-Path $env:LOCALAPPDATA ("Workstation\backups\startup-links-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $vbs = Join-Path $toolkit 'desktop-commander-remote\run-hidden.vbs'
    foreach ($u in @($TK.StartupLinks)) {
        $script = Join-Path $toolkit $u.Script
        $leaf = Split-Path $script -Leaf
        $lnkPath = Join-Path $suDir ($u.Name + '.lnk')
        if (-not (Test-Path -LiteralPath $script)) { Write-Host "  [FAIL] Startup $($u.Name): missing $script" -ForegroundColor Red; $failed++; continue }
        if ($u.Hidden) {
            $target = $wscript; $argsLine = "//B //Nologo `"$vbs`" `"$script`""
        } else {
            $target = $psExe; $argsLine = ("-NoProfile -ExecutionPolicy Bypass -File `"$script`" " + [string]$u.Args).TrimEnd()
        }
        try {
            $existed = Test-Path -LiteralPath $lnkPath
            if ($existed) {
                $old = $wsh.CreateShortcut($lnkPath)
                if ($old.TargetPath -ieq $target -and $old.Arguments -eq $argsLine) { Write-Host "  [ OK ] Startup\$($u.Name).lnk already -> $leaf" -ForegroundColor Green; $startupDone++; continue }
                if ($old.Arguments -notmatch [regex]::Escape($leaf)) { Write-Host "  [WARN] left Startup\$($u.Name).lnk alone: it does not run $leaf" -ForegroundColor Yellow; continue }
                New-Item -ItemType Directory -Path $bkDir -Force | Out-Null
                Copy-Item -LiteralPath $lnkPath -Destination $bkDir -Force
                Write-Host "  [ OK ] backed up old Startup\$($u.Name).lnk ($($old.Arguments)) to $bkDir" -ForegroundColor Green
            }
            $s = $wsh.CreateShortcut($lnkPath)
            $s.TargetPath = $target; $s.Arguments = $argsLine; $s.WorkingDirectory = (Split-Path $script -Parent)
            $s.WindowStyle = $(if ($u.Hidden) { 7 } else { 1 }); $s.Description = "$($u.Name) (workstation sign-in link)"
            $s.Save()
            $check = $wsh.CreateShortcut($lnkPath)
            if ($check.TargetPath -ieq $target -and $check.Arguments -eq $argsLine) {
                $verb = if ($existed) { 'updated' } else { 'created' }
                Write-Host "  [ OK ] Startup\$($u.Name).lnk $verb -> $leaf" -ForegroundColor Green; $startupDone++
            } else { Write-Host "  [FAIL] Startup\$($u.Name).lnk did not read back as expected" -ForegroundColor Red; $failed++ }
        } catch { Write-Host "  [FAIL] Startup $($u.Name): $($_.Exception.Message)" -ForegroundColor Red; $failed++ }
    }
}

# Remove old copies (loose on the desktop, or pre-rename names/folder), but only links that run one of these scripts.
$oldNames = @{ 'workers-start.ps1' = 'Bridge Start'; 'workers-stop.ps1' = 'Bridge Stop'; 'workstation-status.ps1' = 'Bridge Status' }  # pull/push batch-git archived 2026-10-17
$oldPaths = @()
foreach ($l in $links) {
    $names = @($l.Name); $on = $oldNames[$l.Script]; if ($on) { $names += $on }
    foreach ($n in $names) {
        foreach ($d in @(@($desktop) + $oldLinkDirs)) {
            $oldPaths += [pscustomobject]@{ Path = (Join-Path $d ($n + '.lnk')); Script = $l.Script; Name = $n }
        }
    }
}
foreach ($l in $oldPaths) {
    $loose = $l.Path
    if ((Split-Path $loose -Parent) -ieq $linkDir) { continue }
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

# Drop the old Desktop folders once they are empty.
foreach ($oldLinkDir in $oldLinkDirs) {
    if ((Test-Path -LiteralPath $oldLinkDir) -and -not (Get-ChildItem -LiteralPath $oldLinkDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $oldLinkDir -Force
        Write-Host "  [ OK ] removed empty old folder $oldLinkDir" -ForegroundColor Green
    } elseif (Test-Path -LiteralPath $oldLinkDir) {
        Write-Host "  [WARN] left $oldLinkDir alone: it still has other files" -ForegroundColor Yellow
    }
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
else { Write-Host "==== done: $($links.Count) shortcuts and $startupDone Startup links in place ====" -ForegroundColor Green }
if (-not $NoPause) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
if ($failed -gt 0) { exit 1 }
