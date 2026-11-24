#Requires -Version 5.1
<#
.SYNOPSIS
  Run the two Claude Code catalog commands for workstation-core.
.DESCRIPTION
  install.ps1 calls this. install.cmd starts install.ps1, so both run these commands.
  If the claude CLI is missing, both commands are skipped and the exit code is 0.
  This script never removes or turns off a plugin. It runs only the two commands below.
.PARAMETER WhatIf
  Print the two commands and do not run them.
#>
[CmdletBinding()]
param(
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$Add = 'claude plugin marketplace add living-relation/workstation'
$Install = 'claude plugin install workstation-core@workstation-plugins'

if ($WhatIf) {
  Write-Output "WOULD $Add"
  Write-Output "WOULD $Install"
  exit 0
}

$claude = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $claude) {
  Write-Output "SKIP claude CLI is missing. Skipped: $Add"
  Write-Output "SKIP claude CLI is missing. Skipped: $Install"
  exit 0
}

function Invoke-CatalogCommand([string[]]$ArgList, [string]$Printed) {
  Write-Output "RUN $Printed"
  $ErrorActionPreference = 'Continue'
  & $claude.Source @ArgList
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($code -and $code -ne 0) {
    Write-Output "WARN $Printed exited $code. Left every plugin as it is."
  } else {
    Write-Output "DONE $Printed"
  }
}

Invoke-CatalogCommand @('plugin', 'marketplace', 'add', 'living-relation/workstation') $Add
Invoke-CatalogCommand @('plugin', 'install', 'workstation-core@workstation-plugins') $Install
exit 0
