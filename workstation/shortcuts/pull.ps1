#Requires -Version 5.1
# Fast-forward only pull of this workstation clone. One repo only; never touches other clones.
# Wired as the Pull shortcut in toolkit.psd1 (install puts Pull.lnk in shortcuts\).
param([switch]$NoPause)
$ErrorActionPreference = 'Continue'
$repo = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repo) {
    Write-Host '[FAIL] not inside a git clone.' -ForegroundColor Red
    if (-not $NoPause) {
        Write-Host ''; Write-Host 'Press any key to close...' -ForegroundColor DarkGray
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
    }
    exit 1
}
Write-Host ''
Write-Host "Pulling $repo ..." -ForegroundColor Cyan
Write-Host ''
& git -C $repo pull --ff-only
$code = $LASTEXITCODE
Write-Host ''
if ($code -eq 0) { Write-Host 'Done.' -ForegroundColor Green }
else { Write-Host "git pull --ff-only failed (exit $code)." -ForegroundColor Red }
if (-not $NoPause) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
exit $code