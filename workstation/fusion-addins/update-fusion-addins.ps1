#Requires -Version 5.1
# Fast-forward Fusion add-in git clones discovered from AddIns folder junctions.
# Manual only: run it by hand or from the Update Fusion add-ins shortcut (-Pause keeps
# the window open). No scheduled task runs it. Does not start or stop Fusion.
# Exit 0 when git or the AddIns folder is missing.
param([switch]$Pause)
$ErrorActionPreference = 'Stop'
$code = 1
try {
    . (Join-Path $PSScriptRoot 'fusion-addins-lib.ps1')
    $code = [int](@(Invoke-FusionAddinUpdate) | Select-Object -Last 1)
} catch {
    $msg = $_.Exception.Message
    try {
        $dir = $env:WORKSTATION_FUSION_LOG_DIR
        if (-not $dir -and $env:LOCALAPPDATA) { $dir = Join-Path (Join-Path $env:LOCALAPPDATA 'Workstation') 'logs' }
        if ($dir) {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $line = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') + ' error ' + $msg + "`r`n"
            [IO.File]::AppendAllText((Join-Path $dir 'fusion-addins-update.log'), $line)
        }
    } catch { }
    Write-Host "error $msg"
    $code = 1
}
if ($Pause) {
    Write-Host ''
    Write-Host 'Press any key to close...'
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
exit $code
