#Requires -Version 5.1
# Creates the manual shortcuts in -LinkDir. No Startup item, no Run key, no scheduled task.
# Also removes an old "Desktop Commander Remote" Startup link when it still runs start-dc-remote.ps1.
param([Parameter(Mandatory = $true)][string]$LinkDir, [string]$StartupDir, [switch]$NoPause)
$ErrorActionPreference = 'Continue'
$toolkit = $PSScriptRoot
$pkg = Split-Path -Parent $toolkit
$tkFile = Join-Path $pkg 'toolkit.psd1'
try { $TK = Import-PowerShellDataFile -LiteralPath $tkFile } catch { Write-Host "cannot read $tkFile"; exit 1 }
$linkDir = [IO.Path]::GetFullPath($LinkDir).TrimEnd('\')
# Old installs left shortcuts\rc behind after the per-project remote links were removed.
# Remove that folder only when it is empty and is not a link.
$rcDir = Join-Path $linkDir 'rc'
if (Test-Path -LiteralPath $rcDir -PathType Container) {
    $rcItem = Get-Item -LiteralPath $rcDir -Force
    $rcLink = [bool]($rcItem.Attributes -band [IO.FileAttributes]::ReparsePoint)
    # Windows PowerShell 5.1: @($null).Count is 1, so test the result itself.
    $rcKids = Get-ChildItem -LiteralPath $rcDir -Force -ErrorAction SilentlyContinue
    if ($rcLink) { Write-Host "left $rcDir alone (it is a link)" }
    elseif (-not $rcKids) {
        Remove-Item -LiteralPath $rcDir -Force -ErrorAction SilentlyContinue
        Write-Host "removed empty folder $rcDir"
    } else { Write-Host "left $rcDir alone (it still has files)" }
}
if (-not $StartupDir) {
    $StartupDir = [Environment]::GetFolderPath('Startup')
}
$psExe = $null
if ($env:SystemRoot) { $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
if (-not $psExe -or -not (Test-Path -LiteralPath $psExe)) {
    $self = Get-Process -Id $PID -ErrorAction SilentlyContinue
    if ($self -and $self.Path) { $psExe = $self.Path }
}
$shell32 = $null
if ($env:SystemRoot) { $shell32 = Join-Path $env:SystemRoot 'System32\shell32.dll' }
$wsh = $null
try { $wsh = New-Object -ComObject WScript.Shell } catch {
    Write-Host 'Shortcut links need Windows. Nothing was created.'
    exit 0
}
if (-not (Test-Path -LiteralPath $linkDir)) { New-Item -ItemType Directory -Path $linkDir -Force | Out-Null }
$failed = 0
foreach ($sc in @($TK.Shortcuts)) {
    $script = Join-Path $toolkit $sc.Script
    $lnk = Join-Path $linkDir ($sc.Name + '.lnk')
    if (-not (Test-Path -LiteralPath $script)) { Write-Host "missing $script"; $failed++; continue }
    $s = $wsh.CreateShortcut($lnk)
    $s.TargetPath = $psExe
    $s.Arguments = ("-NoProfile -ExecutionPolicy Bypass -File `"$script`" " + [string]$sc.Args).TrimEnd()
    $s.WorkingDirectory = Split-Path $script -Parent
    $s.WindowStyle = 1
    $s.Description = "$($sc.Name) (manual; does not start at sign-in)"
    $icon = 13; if ($sc.Icon) { $icon = [int]$sc.Icon }
    if ($shell32) { $s.IconLocation = "$shell32,$icon" }
    $s.Save()
    Write-Host "shortcut $($sc.Name)"
}
if ($StartupDir -and (Test-Path -LiteralPath $StartupDir)) {
    foreach ($r in @($TK.RetiredStartupLinks)) {
        if (-not $r) { continue }
        $lp = Join-Path $StartupDir ($r.Name + '.lnk')
        if (-not (Test-Path -LiteralPath $lp)) { continue }
        $old = $wsh.CreateShortcut($lp)
        if ("$($old.TargetPath) $($old.Arguments)" -notmatch [regex]::Escape([string]$r.Script)) { continue }
        $bak = Join-Path $env:LOCALAPPDATA ("Workstation\backups\retired-startup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Force -Path $bak | Out-Null
        Copy-Item -LiteralPath $lp -Destination $bak -Force
        Remove-Item -LiteralPath $lp -Force
        Write-Host "removed Startup link $($r.Name) (backup $bak)"
    }
}
if (-not $NoPause) {
    Write-Host 'Press any key to close...'
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
if ($failed) { exit 1 }
exit 0
