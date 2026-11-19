# Shared check: is workstation-core already on this PC from claude.ai?
# Claude Code downloads account plugins into ~/.claude/plugins/synced/
# (or $CLAUDE_CODE_PLUGIN_CACHE_DIR/synced). A script cannot see the website.
# ASCII-only. Windows PowerShell 5.1 compatible.
# Do not set $ErrorActionPreference here. This file is dot-sourced by the health check.

$WsPluginMissingText = 'workstation-core plugin not added on claude.ai yet: add catalog living-relation/workstation and turn on workstation-core'
$WsPluginPresentText = 'workstation-core plugin is present on claude.ai'

function Test-PluginJsonName([string]$Path) {
    try {
        $doc = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch {
        return $false
    }
    return ("$($doc.name)" -eq 'workstation-core')
}

function Test-WorkstationCoreOnClaudeAi {
    param([string]$UserRoot)
    if (-not $UserRoot) { $UserRoot = $HOME }
    $settingsPath = Join-Path $UserRoot '.claude\settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = $null
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $settings = $null }
        if ($settings) {
            if ($settings.syncClaudeAiPlugins -eq $false) { return $false }
            $ep = $settings.enabledPlugins
            if ($ep -and ($ep.'workstation-core@synced' -eq $false)) { return $false }
        }
    }
    $root = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    if (-not $root) { $root = Join-Path $UserRoot '.claude\plugins' }
    $synced = Join-Path $root 'synced'
    if (-not (Test-Path -LiteralPath $synced -PathType Container)) { return $false }
    # -Force so a .claude-plugin folder is included. Dot folders are hidden on Linux.
    $files = @(Get-ChildItem -LiteralPath $synced -Force -Recurse -Filter 'plugin.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        if (Test-PluginJsonName $f.FullName) { return $true }
    }
    return $false
}
