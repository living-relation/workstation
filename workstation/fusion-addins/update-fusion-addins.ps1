#Requires -Version 5.1
# Fast-forward Fusion add-in git clones discovered from AddIns folder junctions.
# Does not start or stop Fusion. A hidden scheduled task runs this at logon and
# every 60 minutes after install.ps1. Exit 0 when git or the AddIns folder is missing.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'fusion-addins-lib.ps1')
    exit (Invoke-FusionAddinUpdate)
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
    exit 1
}
