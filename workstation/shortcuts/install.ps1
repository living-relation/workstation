#Requires -Version 5.1
# Run this clone's install.ps1. Arguments go through unchanged (do not change install behavior).
# Wired as the Install shortcut in toolkit.psd1 (install puts Install.lnk in shortcuts\).
param(
  [switch]$NoPause,
  [Parameter(ValueFromRemainingArguments = $true)]
  [object[]]$PassThru
)
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
$install = Join-Path $repo 'install.ps1'
if (-not (Test-Path -LiteralPath $install)) {
    Write-Host "[FAIL] missing $install" -ForegroundColor Red
    if (-not $NoPause) {
        Write-Host ''; Write-Host 'Press any key to close...' -ForegroundColor DarkGray
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
    }
    exit 1
}
Write-Host ''
Write-Host "Installing $repo ..." -ForegroundColor Cyan
Write-Host ''
if ($null -eq $PassThru -or $PassThru.Count -eq 0) {
    & $install
} else {
    & $install @PassThru
}
$code = $LASTEXITCODE
Write-Host ''
Write-Host "install.ps1 exit $code"
if (-not $NoPause) {
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
exit $code
