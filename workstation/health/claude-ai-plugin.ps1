# Shared check: the workstation-core copy synced from claude.ai, and the copy Claude Code installed
# from the workstation-plugins catalog (decision D-2026-11-23-claude-code-catalog).
# Claude Code downloads account plugins into ~/.claude/plugins/synced/ (or $CLAUDE_CODE_PLUGIN_CACHE_DIR/synced).
# A script cannot see the website: the synced copy only shows what the account had at the last sync.
# ASCII-only. Windows PowerShell 5.1 compatible.
# Do not set $ErrorActionPreference here. This file is dot-sourced by the health check.

$WsPluginMissingText = 'workstation-core plugin not added on claude.ai yet: add catalog living-relation/workstation and turn on workstation-core'
$WsPluginPresentText = 'workstation-core synced from claude.ai is on this PC'
$WsCatalogPluginId = 'workstation-core@workstation-plugins'

function Test-PluginJsonName([string]$Path) {
    try {
        $doc = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch {
        return $false
    }
    return ("$($doc.name)" -eq 'workstation-core')
}

function Get-WsClaudeSettings([string]$UserRoot) {
    $settingsPath = Join-Path $UserRoot '.claude\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    try { return (Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}

# The synced copy: Found, Path (plugin root), LastSync (newest file time), HasRulesHook,
# TurnedOffInClaudeCode (enabledPlugins workstation-core@synced = false; fine, Claude Code uses the
# catalog copy), SyncOff (syncClaudeAiPlugins = false).
function Get-SyncedWorkstationCore {
    param([string]$UserRoot, [string]$PluginsDir)
    if (-not $UserRoot) { $UserRoot = $HOME }
    $r = [pscustomobject]@{ Found = $false; Path = $null; LastSync = $null; HasRulesHook = $false; TurnedOffInClaudeCode = $false; SyncOff = $false }
    $settings = Get-WsClaudeSettings $UserRoot
    if ($settings) {
        if ($settings.syncClaudeAiPlugins -eq $false) { $r.SyncOff = $true }
        $ep = $settings.enabledPlugins
        if ($ep -and ($ep.'workstation-core@synced' -eq $false)) { $r.TurnedOffInClaudeCode = $true }
    }
    $root = $PluginsDir
    if (-not $root) { $root = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR }
    if (-not $root) { $root = Join-Path $UserRoot '.claude\plugins' }
    $synced = Join-Path $root 'synced'
    if (-not (Test-Path -LiteralPath $synced -PathType Container)) { return $r }
    # -Force so a .claude-plugin folder is included. Dot folders are hidden on Linux.
    $files = @(Get-ChildItem -LiteralPath $synced -Force -Recurse -Filter 'plugin.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        if (-not (Test-PluginJsonName $f.FullName)) { continue }
        $dir = $f.Directory.FullName
        if ($f.Directory.Name -match '^\.(claude|cursor)-plugin$') { $dir = $f.Directory.Parent.FullName }
        $r.Found = $true
        $r.Path = $dir
        $r.HasRulesHook = (Test-Path -LiteralPath (Join-Path $dir 'hooks\rules-inject.ps1') -PathType Leaf)
        $newest = @(Get-ChildItem -LiteralPath $dir -Force -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($newest.Count) { $r.LastSync = $newest[0].LastWriteTime }
        break
    }
    return $r
}

# True when a synced copy is on this PC and account sync is on. Turning the synced copy off in
# Claude Code (workstation-core@synced = false) does not remove it from claude.ai, so it still counts.
function Test-WorkstationCoreOnClaudeAi {
    param([string]$UserRoot)
    $s = Get-SyncedWorkstationCore -UserRoot $UserRoot
    return ($s.Found -and -not $s.SyncOff)
}

# The copy Claude Code loads: the installed_plugins.json record for workstation-core@workstation-plugins
# (user scope first) whose installPath exists, and whether settings.json turns it off.
function Get-ClaudeCodeWorkstationCore {
    param([string]$UserRoot, [string]$PluginsDir)
    if (-not $UserRoot) { $UserRoot = $HOME }
    $r = [pscustomobject]@{ Installed = $false; Enabled = $false; Path = $null; Sha = $null; HasRulesHook = $false; RulesHook = $null }
    $root = $PluginsDir
    if (-not $root) { $root = Join-Path $UserRoot '.claude\plugins' }
    $ip = Join-Path $root 'installed_plugins.json'
    if (-not (Test-Path -LiteralPath $ip -PathType Leaf)) { return $r }
    $doc = $null
    try { $doc = Get-Content -LiteralPath $ip -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $r }
    if (-not $doc -or -not $doc.plugins) { return $r }
    $prop = $doc.plugins.PSObject.Properties[$WsCatalogPluginId]
    if (-not $prop) { return $r }
    $recs = @($prop.Value)
    $rec = @($recs | Where-Object { "$($_.scope)" -eq 'user' }) | Select-Object -First 1
    if (-not $rec) { $rec = $recs | Select-Object -First 1 }
    if (-not $rec -or -not $rec.installPath -or -not (Test-Path -LiteralPath "$($rec.installPath)" -PathType Container)) { return $r }
    $r.Installed = $true
    $r.Path = "$($rec.installPath)"
    $r.Sha = "$($rec.gitCommitSha)"
    $hook = Join-Path $r.Path 'hooks\rules-inject.ps1'
    if (Test-Path -LiteralPath $hook -PathType Leaf) { $r.HasRulesHook = $true; $r.RulesHook = $hook }
    $r.Enabled = $true
    $settings = Get-WsClaudeSettings $UserRoot
    if ($settings -and $settings.enabledPlugins) {
        $v = $settings.enabledPlugins.PSObject.Properties[$WsCatalogPluginId]
        if ($v -and $v.Value -eq $false) { $r.Enabled = $false }
    }
    return $r
}
