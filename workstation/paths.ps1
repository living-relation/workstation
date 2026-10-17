# Shared paths for the Workstation toolkit. Dot-sourced by shortcuts\workstation-common.ps1, cursor-worker\config.ps1
# and repo-status.ps1. Windows PowerShell 5.1 compatible. Keep this file ASCII-only.
# The toolkit runs straight from the workstation repo clone (<Projects>\active\workstation\workstation); nothing is
# copied under <Projects>. Runtime files (Workers Stop flag, Cursor worker logs/state/cache) go to
# %LOCALAPPDATA%\<StateFolder>, never into the clone, so the clone stays clean.
$WsToolkitDir    = $PSScriptRoot
$WsPackageDir    = Split-Path -Parent $WsToolkitDir
$WsStateName     = 'Workstation'
$WsConfigName    = 'workstation.json'
$WsLegacyFolders = @('_bridge', '_workstation')
$WsTkDef = Join-Path $WsPackageDir 'toolkit.psd1'
if (Test-Path -LiteralPath $WsTkDef) {
    try {
        $WsTk = Import-PowerShellDataFile -LiteralPath $WsTkDef
        if ($WsTk.StateFolder)   { $WsStateName = [string]$WsTk.StateFolder }
        if ($WsTk.ConfigFile)    { $WsConfigName = [string]$WsTk.ConfigFile }
        if ($WsTk.LegacyFolders) { $WsLegacyFolders = @($WsTk.LegacyFolders) }
    } catch { }
}
$WsStateDir   = Join-Path $env:LOCALAPPDATA $WsStateName
$WsConfigPath = Join-Path $WsStateDir $WsConfigName
$WsStopFlag   = Join-Path $WsStateDir 'workers-stopped.flag'

# Projects root: from the config file install.ps1 writes (projectsRoot); else from the clone's own location
# (<Projects>\active\<repo>\workstation -> <Projects>).
$WsProjectsRoot = $null
if (Test-Path -LiteralPath $WsConfigPath) {
    try { $WsProjectsRoot = [string](Get-Content -LiteralPath $WsConfigPath -Raw | ConvertFrom-Json).projectsRoot } catch { }
}
if (-not $WsProjectsRoot -or -not (Test-Path -LiteralPath $WsProjectsRoot)) {
    $WsUp = Split-Path -Parent $WsPackageDir
    if ((Split-Path -Leaf $WsUp) -ieq 'active') { $WsProjectsRoot = Split-Path -Parent $WsUp } else { $WsProjectsRoot = $WsUp }
}
$WsProjectsRoot = $WsProjectsRoot.TrimEnd('\')
