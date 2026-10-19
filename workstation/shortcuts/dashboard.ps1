#Requires -Version 5.1
# Opens the local project dashboard. Does not start or stop the workers.
$ErrorActionPreference = 'Continue'
$start = Join-Path (Split-Path -Parent $PSScriptRoot) 'dashboard\start-dashboard.ps1'
if (-not (Test-Path -LiteralPath $start)) {
    Write-Host "Dashboard start script is not in this checkout: $start"
    exit 1
}
& $start
exit $LASTEXITCODE
