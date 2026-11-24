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

# The synced folder is the claude.ai copy (Desktop and Cowork). A disabled
# workstation-core@synced flag does not mean the plugin was never added.
# This line is information only. It is not a pass or a fail.
function Get-ClaudeAiSyncedCopyText {
    param([string]$UserRoot)
    if (-not $UserRoot) { $UserRoot = $HOME }
    $root = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    if (-not $root) { $root = Join-Path $UserRoot '.claude/plugins' }
    $synced = Join-Path $root 'synced'
    $best = $null
    $bestTime = [datetime]::MinValue
    if (Test-Path -LiteralPath $synced -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $synced -Force -Recurse -Filter 'plugin.json' -File -ErrorAction SilentlyContinue)
        foreach ($f in @($files)) {
            if (-not (Test-PluginJsonName $f.FullName)) { continue }
            $when = $f.LastWriteTime
            if (-not $best -or $when -gt $bestTime) { $best = $f; $bestTime = $when }
        }
    }
    if (-not $best) {
        return 'claude.ai synced copy (Desktop/Cowork): last synced none, has rules-inject no'
    }
    $pluginRoot = Split-Path -Parent $best.FullName
    if ((Split-Path -Leaf $pluginRoot) -eq '.claude-plugin') { $pluginRoot = Split-Path -Parent $pluginRoot }
    $has = 'no'
    $hook = Join-Path $pluginRoot 'hooks/rules-inject.ps1'
    if (Test-Path -LiteralPath $hook -PathType Leaf) { $has = 'yes' }
    else {
        $any = @(Get-ChildItem -LiteralPath $pluginRoot -Force -Recurse -Filter 'rules-inject.ps1' -File -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($any) { $has = 'yes' }
    }
    return ('claude.ai synced copy (Desktop/Cowork): last synced {0}, has rules-inject {1}' -f $bestTime.ToString('yyyy-MM-dd'), $has)
}

function Read-HealthJson([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}

function Get-PluginEnabledFlag($Settings, [string]$Id) {
    if (-not $Settings -or -not $Settings.enabledPlugins -or -not $Id) { return $null }
    $prop = $Settings.enabledPlugins.PSObject.Properties[$Id]
    if (-not $prop) { return $null }
    $v = $prop.Value
    if ($v -is [bool]) { return [bool]$v }
    if ("$v" -match '^(?i)true$') { return $true }
    if ("$v" -match '^(?i)false$') { return $false }
    return $null
}

function Get-PluginEntryList($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Resolve-PluginInstallPath([string]$UserRoot, [string]$InstallPath) {
    if (-not $InstallPath) { return $null }
    $raw = $InstallPath.Trim()
    $sep = [IO.Path]::DirectorySeparatorChar
    $rel = ($raw -replace '[\\/]', $sep).TrimStart($sep)
    if ([IO.Path]::IsPathRooted($raw) -and (Test-Path -LiteralPath $raw)) { return (Resolve-Path -LiteralPath $raw).Path }
    foreach ($base in @(
        (Join-Path $UserRoot '.claude/plugins'),
        (Join-Path $UserRoot '.claude'),
        $UserRoot
    )) {
        $cand = Join-Path $base $rel
        if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
    }
    return $null
}

# The copy Claude Code actually loads. installed_plugins.json plus enabledPlugins.
# workstation-core@workstation-plugins wins over the claude.ai synced copy (D-2026-11-23).
# A random cache folder is not a match.
function Get-EnabledWorkstationCoreRecord {
    param([string]$UserRoot)
    if (-not $UserRoot) { $UserRoot = $HOME }
    $settings = Read-HealthJson (Join-Path $UserRoot '.claude/settings.json')
    $reg = Read-HealthJson (Join-Path $UserRoot '.claude/plugins/installed_plugins.json')
    if (-not $reg -or -not $reg.plugins) { return $null }
    $cands = @()
    foreach ($p in @($reg.plugins.PSObject.Properties)) {
        $id = ([string]$p.Name).Trim()
        if ($id -notlike 'workstation-core@*') { continue }
        $flag = Get-PluginEnabledFlag $settings $id
        foreach ($e in @(Get-PluginEntryList $p.Value)) {
            if (-not $e) { continue }
            $scope = ''
            if ($e.PSObject.Properties.Name -contains 'scope') { $scope = "$($e.scope)".Trim() }
            $ver = ''
            if ($e.PSObject.Properties.Name -contains 'version') { $ver = "$($e.version)".Trim() }
            $ip = ''
            if ($e.PSObject.Properties.Name -contains 'installPath') { $ip = "$($e.installPath)".Trim() }
            $path = Resolve-PluginInstallPath $UserRoot $ip
            $cands += [pscustomobject]@{ Id = $id; Scope = $scope; Version = $ver; Path = $path; Flag = $flag }
        }
    }
    $picked = $null
    foreach ($c in @($cands)) {
        if ($c.Flag -ne $true) { continue }
        if ($c.Id -eq 'workstation-core@workstation-plugins') { return $c }
        if (-not $picked) { $picked = $c }
    }
    if ($picked) { return $picked }
    foreach ($c in @($cands)) {
        if ($c.Id -ne 'workstation-core@workstation-plugins') { continue }
        if ($c.Flag -eq $false) { continue }
        if ($c.Scope -and $c.Scope -ne 'user') { continue }
        return $c
    }
    return $null
}

function Get-EnabledWorkstationCoreRoot {
    param([string]$UserRoot)
    $rec = Get-EnabledWorkstationCoreRecord -UserRoot $UserRoot
    if ($rec -and $rec.Path) { return [string]$rec.Path }
    return $null
}

function Get-RepoMainSha([string]$RepoRoot) {
    if (-not $RepoRoot) { return '' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return '' }
    foreach ($ref in @('origin/main', 'main', 'HEAD')) {
        $out = & git -C $RepoRoot rev-parse $ref 2>$null
        if ($LASTEXITCODE -eq 0 -and "$out".Trim()) { return "$out".Trim().ToLowerInvariant() }
    }
    return ''
}

function Get-ShortSha([string]$Sha) {
    $s = "$Sha".Trim()
    if (-not $s) { return 'unknown' }
    if ($s.Length -gt 12) { return $s.Substring(0, 12) }
    return $s
}

function Test-GitShaText([string]$Text) {
    return [bool]("$Text" -match '^[0-9a-fA-F]{7,40}$')
}

function Test-SameGitSha([string]$A, [string]$B) {
    $a = "$A".Trim().ToLowerInvariant()
    $b = "$B".Trim().ToLowerInvariant()
    if (-not (Test-GitShaText $a) -or -not (Test-GitShaText $b)) { return $false }
    return ($a.StartsWith($b) -or $b.StartsWith($a))
}

function Get-CopyContentToken([string]$Root, [string[]]$Rels) {
    if (-not $Root) { return '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    $ms = New-Object IO.MemoryStream
    try {
        foreach ($rel in @($Rels)) {
            $sep = [IO.Path]::DirectorySeparatorChar
            $p = Join-Path $Root ($rel -replace '[\\/]', $sep)
            $nameBytes = [Text.Encoding]::UTF8.GetBytes($rel + "`n")
            $ms.Write($nameBytes, 0, $nameBytes.Length)
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
                $missing = [Text.Encoding]::UTF8.GetBytes("missing`n")
                $ms.Write($missing, 0, $missing.Length)
                continue
            }
            $bytes = [IO.File]::ReadAllBytes($p)
            $ms.Write($bytes, 0, $bytes.Length)
            $nl = [Text.Encoding]::UTF8.GetBytes("`n")
            $ms.Write($nl, 0, $nl.Length)
        }
        $ms.Position = 0
        return ([BitConverter]::ToString($sha.ComputeHash($ms))).Replace('-', '').ToLowerInvariant()
    } finally {
        $ms.Dispose()
        $sha.Dispose()
    }
}

# Claude Code copy vs repo main, and the Cursor local copy vs this repo.
# Levels: RUN match, WARN differs or the recorded folder is missing, SKIP not installed or not comparable.
function Get-PluginVersionReports {
    param([string]$UserRoot, [string]$RepoRoot)
    if (-not $UserRoot) { $UserRoot = $HOME }
    $claudeUpdate = 'Update: claude plugin marketplace update workstation-plugins, then claude plugin update workstation-core@workstation-plugins.'
    $cursorUpdate = 'Update: powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugins.ps1'
    $main = Get-RepoMainSha $RepoRoot
    $mainShort = Get-ShortSha $main
    $lines = @()
    $rec = Get-EnabledWorkstationCoreRecord -UserRoot $UserRoot
    if (-not $rec) {
        $lines += [pscustomobject]@{ Level = 'SKIP'; Text = "Claude Code plugin copy is not enabled (installed_plugins.json). Repo main $mainShort. $claudeUpdate" }
    } else {
        $ver = "$($rec.Version)".Trim()
        $shortVer = Get-ShortSha $ver
        $onDisk = [bool]($rec.Path -and (Test-Path -LiteralPath $rec.Path))
        if (-not (Test-GitShaText $ver) -or -not $main) {
            $lines += [pscustomobject]@{ Level = 'SKIP'; Text = "Claude Code plugin copy $shortVer vs repo main $mainShort (not compared). $claudeUpdate" }
        } elseif (-not $onDisk) {
            $lines += [pscustomobject]@{ Level = 'WARN'; Text = "Claude Code plugin copy $shortVer vs repo main $mainShort, folder missing. $claudeUpdate" }
        } elseif (Test-SameGitSha $ver $main) {
            $lines += [pscustomobject]@{ Level = 'RUN'; Text = "Claude Code plugin copy $shortVer matches repo main $mainShort. $claudeUpdate" }
        } else {
            $lines += [pscustomobject]@{ Level = 'WARN'; Text = "Claude Code plugin copy $shortVer differs from repo main $mainShort. $claudeUpdate" }
        }
    }
    $rels = @(
        '.cursor-plugin/plugin.json',
        '.claude-plugin/plugin.json',
        'hooks/rules-inject.ps1',
        'hooks/cursor-hooks.json',
        'hooks/hooks.json'
    )
    $cursorRoot = Join-Path $UserRoot '.cursor/plugins/local/workstation-core'
    if (-not (Test-Path -LiteralPath $cursorRoot -PathType Container)) {
        $lines += [pscustomobject]@{ Level = 'SKIP'; Text = "Cursor local copy is not installed. Repo $mainShort. $cursorUpdate" }
    } else {
        $repoTok = Get-CopyContentToken $RepoRoot $rels
        $copyTok = Get-CopyContentToken $cursorRoot $rels
        if ($repoTok -and $copyTok -and $repoTok -eq $copyTok) {
            $lines += [pscustomobject]@{ Level = 'RUN'; Text = "Cursor local copy matches this repo ($mainShort). $cursorUpdate" }
        } else {
            $lines += [pscustomobject]@{ Level = 'WARN'; Text = "Cursor local copy differs from this repo ($mainShort). $cursorUpdate" }
        }
    }
    return @($lines)
}
