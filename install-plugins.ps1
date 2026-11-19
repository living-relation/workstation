#Requires -Version 5.1
<#
.SYNOPSIS
  Install workstation-core and handbuilt-cad from the living-relation-plugins catalog.
.DESCRIPTION
  Manual only. Double-click install-plugins.cmd, or run this file.
  Does not link skills. Does not create a scheduled task, a sign-in item, or a Run key.
  Does not turn on marketplace auto-update. Updates later come from the Plugins menu.
  -WhatIf prints the two commands and runs none.
.PARAMETER Marketplace
  Marketplace source passed to --marketplace. Default: living-relation/workstation.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$Marketplace = 'living-relation/workstation'
)

$ErrorActionPreference = 'Stop'
if ($Marketplace -notmatch '^[A-Za-z0-9_./:@\\-]+$') {
  Write-Host "Marketplace source has unexpected characters: $Marketplace"
  exit 1
}

$lines = @(
  "claude plugin install workstation-core --marketplace $Marketplace --scope user",
  "claude plugin install handbuilt-cad --marketplace $Marketplace --scope user"
)
# Nested arrays (the leading comma). Without it, PowerShell flattens the list.
$steps = @(
  ,@('plugin', 'install', 'workstation-core', '--marketplace', $Marketplace, '--scope', 'user'),
  ,@('plugin', 'install', 'handbuilt-cad', '--marketplace', $Marketplace, '--scope', 'user')
)

if (-not $PSCmdlet.ShouldProcess('living-relation-plugins', 'install plugins')) {
  foreach ($line in $lines) { Write-Output $line }
  Write-Output 'WhatIf: no command was run. Skills were not linked. Nothing was scheduled.'
  exit 0
}

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
  Write-Host 'Claude Code CLI (claude) was not found on PATH. Install Claude Code, open a new window, and run this again.'
  exit 1
}

for ($i = 0; $i -lt $steps.Count; $i++) {
  Write-Output $lines[$i]
  $stepArgs = $steps[$i]
  & $claude.Source @stepArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Host "stopped: exit $LASTEXITCODE"
    exit $LASTEXITCODE
  }
}
Write-Output 'Installed both plugins at user scope. Updates come from the Plugins menu. Leave auto-update off. Skills were not linked.'
exit 0
