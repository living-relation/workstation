#Requires -Version 5.1
<#
.SYNOPSIS
  Open the claude.ai Plugins page and copy workstation-core for Cursor.
.DESCRIPTION
  Manual only. Double-click install-plugins.cmd, or run this file.
  A script cannot turn the plugin on at claude.ai. A real run opens the page
  and prints the clicks. It also copies this repo to
  ~\.cursor\plugins\local\workstation-core.
  It does not copy skills into ~\.claude\skills.
  It does not create a scheduled task, a sign-in item, or a Run key.
  Turn Sync automatically on. Nothing runs in the background.
  -WhatIf prints the clicks and changes nothing.
  -UserHome is for tests: the Cursor copy goes under that folder, and the
  browser is not opened.
.PARAMETER Catalog
  GitHub owner/repo pasted into Add marketplace. Default: living-relation/workstation.
.PARAMETER UserHome
  Testing only. Cursor copy destination root. Also skips the browser.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$Catalog = 'living-relation/workstation',
  [string]$UserHome
)

$ErrorActionPreference = 'Stop'
if ($Catalog -notmatch '^[A-Za-z0-9_./:@\\-]+$') {
  Write-Host "Catalog source has unexpected characters: $Catalog"
  exit 1
}

$Page = 'https://claude.ai/customize/plugins'
$dry = [bool]$WhatIfPreference
$copyHome = $UserHome
if (-not $copyHome) {
  $copyHome = $env:USERPROFILE
  if (-not $copyHome) { $copyHome = $HOME }
}

Write-Output "Catalog to paste: $Catalog"
Write-Output 'Catalog name: workstation-plugins'
Write-Output "Plugin page: $Page"
Write-Output '1. Sign in to the claude.ai account you use for chat, Cowork, and Claude Code.'
Write-Output '2. Open Customize in the left sidebar.'
Write-Output '3. Open Plugins.'
Write-Output '4. Click Add, then Add marketplace.'
Write-Output '5. Choose Add from a repository.'
Write-Output "6. Paste $Catalog."
Write-Output '7. Turn Sync automatically on.'
Write-Output '8. Confirm the add.'
Write-Output '9. Turn on workstation-core.'
Write-Output 'That covers chat, Cowork, and Claude Code signed in to this account.'
Write-Output 'Updates later: updates arrive automatically after merges to main. Check for updates in the catalog forces it sooner.'

$dest = Join-Path $copyHome '.cursor\plugins\local\workstation-core'
$src = $PSScriptRoot
if (-not $src) { $src = Split-Path -Parent $MyInvocation.MyCommand.Path }
$fullDest = [IO.Path]::GetFullPath($dest)
$fullSrc = [IO.Path]::GetFullPath($src)
if ($fullDest.TrimEnd('\','/').StartsWith($fullSrc.TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase)) {
  Write-Host 'Refusing to copy the plugin into its own folder.'
  exit 1
}
Write-Output "Cursor copy: $fullDest"

if ($dry) {
  Write-Output 'WhatIf: browser was not opened. Nothing was copied. Nothing was scheduled.'
  exit 0
}

New-Item -ItemType Directory -Force -Path $fullDest | Out-Null
Get-ChildItem -Force -LiteralPath $fullSrc | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.venv' } | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $fullDest $_.Name) -Recurse -Force
}
Write-Output "Copied workstation-core to $fullDest. Reload the Cursor window."

if ($UserHome) {
  Write-Output 'browser was not opened (test home). Nothing was scheduled.'
  exit 0
}

$opened = $false
try {
  if ($env:OS -eq 'Windows_NT') {
    Start-Process $Page
    $opened = $true
  } else {
    $xdg = Get-Command xdg-open -ErrorAction SilentlyContinue
    if ($xdg) {
      & $xdg.Source $Page
      if ($LASTEXITCODE -eq 0) { $opened = $true }
    }
  }
} catch {
  $opened = $false
}
if ($opened) { Write-Output "Opened $Page" }
else { Write-Output "Could not open a browser. Open this page yourself: $Page" }
Write-Output 'Nothing was scheduled.'
exit 0
