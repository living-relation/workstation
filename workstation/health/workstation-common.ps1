# Health check helpers. Dot-sourced by workstation-status.ps1.
# Windows PowerShell 5.1 compatible. ASCII-only.
$ErrorActionPreference = 'Continue'

$HealthDir = $PSScriptRoot
$BridgeRoot = Split-Path -Parent $HealthDir
. (Join-Path $BridgeRoot 'paths.ps1')
. (Join-Path $HealthDir 'claude-auth-status.ps1')
. (Join-Path $HealthDir 'orphans.ps1')
. (Join-Path $HealthDir 'claude-ai-plugin.ps1')
$__cwLib = Join-Path (Join-Path $BridgeRoot 'cursor-worker') 'cursor-worker-lib.ps1'
if (-not (Get-Command Get-CursorWorkerHealthLines -ErrorAction SilentlyContinue)) { . $__cwLib }
$BridgeProjects = $WsProjectsRoot

function Write-Title([string]$t) {
    Write-Host ''
    Write-Host "==== $t ====  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ''
}
function Write-Ok([string]$m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Off([string]$m)  { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
# Running / stopped are states, not results: [ RUN ] green, [STOP] gray (normal for a manual tool).
function Write-Run([string]$m)  { Write-Host "  [ RUN ] $m" -ForegroundColor Green }
function Write-Stop([string]$m) { Write-Host "  [STOP] $m" -ForegroundColor DarkGray }
function Write-Warn([string]$m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Bad([string]$m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red }

function Wait-BridgeClose([switch]$NoPause) {
    if ($NoPause) { return }
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}

function Expand-UserPath([string]$p) {
    if (-not $p) { return $p }
    $p = $p.Trim()
    if ($p -match '^~(?=[\\/]|$)') { $p = $HOME + $p.Substring(1) }
    if ($p -match '^\$HOME(?=[\\/]|$)') { $p = $HOME + $p.Substring(5) }
    $p = [regex]::Replace($p, '\$env:([A-Za-z_][A-Za-z0-9_]*)', { param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value) })
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($env:OS -eq 'Windows_NT') { return ($p -replace '/', '\') }
    return ($p -replace '\\', '/')
}

function Get-PathFromCommand([string]$cmd) {
    if (-not $cmd) { return $null }
    $m = [regex]::Match($cmd, '"([^"]+\.ps1)"', 'IgnoreCase')
    if (-not $m.Success) { $m = [regex]::Match($cmd, '(\S+\.ps1)(?:\s|$)', 'IgnoreCase') }
    if (-not $m.Success) { return $null }
    return (Expand-UserPath $m.Groups[1].Value)
}

function Show-MemoryAndHooks {
    Write-Host 'Memory and hooks' -ForegroundColor Cyan
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $oldSync = Get-ScheduledTask -TaskName 'Claude-Memory-To-Cursor-Sync' -ErrorAction SilentlyContinue
        if ($oldSync -and "$($oldSync.State)" -ne 'Disabled') { Write-Warn 'retired memory sync task is still enabled' }
        else { Write-Ok 'no retired memory sync task' }
    } else { Write-Ok 'no retired memory sync task' }

    $claudeDir = Join-Path $HOME '.claude'
    $settingsPath = Join-Path $claudeDir 'settings.json'
    $settings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
        catch { Write-Bad "can't parse $settingsPath" }
    } else { Write-Warn "no Claude settings at $settingsPath" }

    $hookCmds = @()
    if ($settings -and $settings.hooks) {
        foreach ($ev in $settings.hooks.PSObject.Properties) {
            foreach ($group in @($ev.Value)) {
                foreach ($h in @($group.hooks)) { if ($h.command) { $hookCmds += [pscustomobject]@{ Event = $ev.Name; Command = "$($h.command)" } } }
            }
        }
    }
    foreach ($pair in @(
        @{ Leaf = 'memory-link-guard.ps1'; File = (Join-Path $claudeDir 'hooks\memory-link-guard.ps1') },
        @{ Leaf = 'pr-closeout-nudge.ps1'; File = (Join-Path $claudeDir 'hooks\pr-closeout-nudge.ps1') },
        @{ Leaf = 'context-guard.ps1'; File = (Join-Path $claudeDir 'hooks\context-guard.ps1') }
    )) {
        # Since D-2026-11-26-hooks-in-plugin these run from the workstation-core plugin (hooks/hooks.json).
        # An older install's copy in settings.json still runs; the plugin copy stays quiet for that event.
        $refs = @($hookCmds | Where-Object { $_.Command -match [regex]::Escape($pair.Leaf) })
        if (-not $refs) { Write-Ok "$($pair.Leaf) hook: from the workstation-core plugin" }
        else {
            $bad = @($refs | Where-Object { $p = Get-PathFromCommand $_.Command; $p -and -not (Test-Path -LiteralPath $p) })
            if ($bad) { Write-Bad "$($pair.Leaf): settings.json wires an older copy that is missing ($($pair.File)); the plugin copy stays quiet while that entry is there" }
            else { Write-Ok "$($pair.Leaf) hook: older copy wired in settings.json ($(($refs | ForEach-Object Event | Sort-Object -Unique) -join ', ')); the plugin copy stays quiet for those events" }
        }
    }
    if ($settings) {
        $amd = $settings.autoMemoryDirectory
        if (-not $amd) { Write-Warn 'autoMemoryDirectory not set in settings.json' }
        else {
            $amdPath = Expand-UserPath "$amd"
            if (Test-Path -LiteralPath $amdPath) { Write-Ok "autoMemoryDirectory -> $amdPath" }
            else { Write-Bad "autoMemoryDirectory points at a missing folder: $amdPath" }
        }
    }
    Write-Off 'working-memory junction is not checked (a leftover is harmless)'
    $rootClaude = Join-Path $BridgeProjects 'CLAUDE.md'
    if (Test-Path -LiteralPath $rootClaude) { Write-Warn "root CLAUDE.md found ($rootClaude); merge it into AGENTS.md" }
    else { Write-Ok 'Projects root has no CLAUDE.md (AGENTS.md only)' }
    foreach ($lf in @($WsLegacyFolders)) {
        $lp = Join-Path $BridgeProjects $lf
        if ($lf -and (Test-Path -LiteralPath $lp)) { Write-Warn "old toolkit copy still there: $lp" }
    }
}

function Get-WsRepoRoot { return (Split-Path -Parent $BridgeRoot) }

# origin/main of this clone as of its last fetch or pull (HEAD when there is no origin/main). $null without git.
function Get-WsRepoMainSha {
    if ($env:WORKSTATION_FAKE_MAIN_SHA) { return $env:WORKSTATION_FAKE_MAIN_SHA }
    $repo = Get-WsRepoRoot
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return $null }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $sha = & git -C $repo rev-parse --verify --quiet 'origin/main' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $sha) { $sha = & git -C $repo rev-parse --verify --quiet HEAD 2>$null }
    if ($LASTEXITCODE -ne 0 -or -not $sha) { return $null }
    return ("$sha").Trim()
}

function Get-ShortSha([string]$Sha) {
    if (-not $Sha) { return 'unknown' }
    if ($Sha.Length -gt 7) { return $Sha.Substring(0, 7) }
    return $Sha
}

# Files of this clone that the Cursor copy should match (tracked plugin parts). Empty without git.
function Get-WsCursorCopyFiles {
    $repo = Get-WsRepoRoot
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return @() }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return @() }
    $list = @(& git -C $repo ls-files -- hooks skills rules memory/templates .cursor-plugin 2>$null)
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($list | Where-Object { $_ -and ($_ -notmatch '\.zip$') })
}

function Show-Plugins {
    Write-Host ''
    Write-Host 'Plugins' -ForegroundColor Cyan
    # Claude Code: the catalog copy (decision D-2026-11-23-claude-code-catalog).
    if (-not (Test-Path -LiteralPath (Join-Path $HOME '.claude'))) {
        Write-Off 'Claude Code: not set up on this account (no .claude folder)'
    } else {
        $cc = Get-ClaudeCodeWorkstationCore -UserRoot $HOME
        if (-not $cc.Installed) {
            Write-Warn "Claude Code: $WsCatalogPluginId is not installed. Commands: INSTALL.md, Claude Code section"
        } elseif (-not $cc.Enabled) {
            Write-Warn "Claude Code: $WsCatalogPluginId is turned off. Run: claude plugin enable $WsCatalogPluginId"
        } elseif (-not $cc.HasRulesHook) {
            Write-Warn "Claude Code: $WsCatalogPluginId $(Get-ShortSha $cc.Sha) has no hooks\rules-inject.ps1. Update it (INSTALL.md, Claude Code section)"
        } else {
            $main = Get-WsRepoMainSha
            if (-not $main) {
                Write-Ok "Claude Code: $WsCatalogPluginId $(Get-ShortSha $cc.Sha) enabled (version not compared: no git clone)"
            } elseif ($cc.Sha -and ($main.StartsWith($cc.Sha) -or $cc.Sha.StartsWith($main))) {
                Write-Ok "Claude Code: $WsCatalogPluginId $(Get-ShortSha $cc.Sha) enabled, same as origin/main"
            } else {
                Write-Warn "Claude Code: $WsCatalogPluginId $(Get-ShortSha $cc.Sha) is behind origin/main $(Get-ShortSha $main) (as of the last pull). Run, one at a time: claude plugin marketplace update workstation-plugins / claude plugin update $WsCatalogPluginId"
            }
        }
    }
    # Cursor: the local copy made by install-plugins.
    $cursorDir = Join-Path $HOME '.cursor'
    if (-not (Test-Path -LiteralPath $cursorDir)) {
        Write-Off 'Cursor: not set up on this account (no .cursor folder)'
    } else {
        $dest = Join-Path $cursorDir 'plugins\local\workstation-core'
        if (-not (Test-Path -LiteralPath (Join-Path $dest '.cursor-plugin\plugin.json'))) {
            Write-Warn "Cursor: no workstation-core copy at $dest. Run install-plugins.cmd, then fully quit and reopen Cursor"
        } else {
            $files = @(Get-WsCursorCopyFiles)
            if (-not $files.Count) {
                Write-Ok "Cursor: workstation-core copy present (not compared: no git clone)"
            } else {
                $repo = Get-WsRepoRoot
                $diff = @()
                foreach ($rel in $files) {
                    $src = Join-Path $repo $rel
                    $dst = Join-Path $dest $rel
                    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
                    if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { $diff += $rel; continue }
                    $a = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
                    $b = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
                    if ($a -ne $b) { $diff += $rel }
                }
                if ($diff.Count) {
                    Write-Warn ("Cursor: workstation-core copy differs from this clone in {0} file(s), e.g. {1}. Run install-plugins.cmd, then fully quit and reopen Cursor" -f $diff.Count, (($diff | Select-Object -First 2) -join ', '))
                } else {
                    Write-Ok ("Cursor: workstation-core copy matches this clone ({0} files)" -f $files.Count)
                }
            }
        }
    }
    # claude.ai: what Claude desktop and Cowork use. A script cannot see the website; this is info only.
    $sy = Get-SyncedWorkstationCore -UserRoot $HOME
    if ($sy.SyncOff) {
        Write-Off 'claude.ai copy: plugin sync is off in Claude Code settings (syncClaudeAiPlugins false); Claude desktop and Cowork still read your claude.ai account'
    } elseif ($sy.Found) {
        $when = 'unknown'
        if ($sy.LastSync) { $when = $sy.LastSync.ToString('yyyy-MM-dd HH:mm') }
        $hookTxt = 'no'; if ($sy.HasRulesHook) { $hookTxt = 'yes' }
        $off = ''; if ($sy.TurnedOffInClaudeCode) { $off = '; turned off in Claude Code (fine: Claude Code uses the catalog copy)' }
        Write-Off "claude.ai copy (Claude desktop and Cowork use the account copy; a script cannot see the website): synced copy on this PC last changed $when, has rules-inject: $hookTxt$off"
    } else {
        Write-Off 'claude.ai copy: none synced to this PC. Claude desktop and Cowork read workstation-core from your claude.ai account (Customize > Plugins); a script cannot see it'
    }
}

function Show-CursorWorker {
    Write-Host ''
    Write-Host 'Cursor worker' -ForegroundColor Cyan
    foreach ($line in @(Get-CursorWorkerHealthLines)) {
        switch ($line.Level) {
            'RUN'  { Write-Run $line.Text }
            'STOP' { Write-Stop $line.Text }
            'WARN' { Write-Warn $line.Text }
            'FAIL' { Write-Bad $line.Text }
            default { Write-Ok $line.Text }
        }
    }
}


function Show-Orphans {
    $warn = @(Get-HealthOrphanWarnings)
    if ($warn.Count) { Write-Warn "$($warn.Count) leftover process(es). Run workstation\kill-orphans.ps1" }
    else { Write-Ok 'no leftover processes (workstation\kill-orphans.ps1)' }
}

function Get-LockShell {
    foreach ($n in @('powershell', 'pwsh')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c -and $c.Source) { return $c.Source }
    }
    $self = Get-Process -Id $PID -ErrorAction SilentlyContinue
    if ($self -and $self.Path) { return $self.Path }
    return $null
}

function Join-ProfilePath([string]$Profile, [string[]]$Parts) {
    $p = $Profile
    foreach ($part in $Parts) { if ($part) { $p = Join-Path $p $part } }
    return $p
}
function Test-LockRuleComplete([string]$Text) {
    if (-not $Text) { return $false }
    return ($Text -match '(?i)\bacquire\b' -and $Text -match '(?i)(check-?in|check in)\b' -and $Text -match '(?i)\brelease\b' -and $Text -match '(?i)harness\.design')
}
function Get-LockRuleGaps([string]$Text) {
    $gaps = New-Object System.Collections.Generic.List[string]
    if ($Text -notmatch '(?i)\bacquire\b') { [void]$gaps.Add('acquire') }
    if ($Text -notmatch '(?i)(check-?in|check in)\b') { [void]$gaps.Add('check-in') }
    if ($Text -notmatch '(?i)\brelease\b') { [void]$gaps.Add('release') }
    if ($Text -notmatch '(?i)harness\.design') { [void]$gaps.Add('harness.design') }
    return @($gaps)
}
function Test-AclAllowsWrite($Rules, [string]$ProfileLeaf, [string[]]$IdentityNames) {
    $deny = $false
    $allow = $false
    foreach ($rule in @($Rules)) {
        $rights = "$($rule.FileSystemRights)"
        if ($rights -notmatch 'Write|Modify|FullControl') { continue }
        $id = "$($rule.IdentityReference)"
        $hit = $false
        if ($id -match '(?i)(^|\\)(Users|Everyone|Authenticated Users)$') { $hit = $true }
        if ($ProfileLeaf -and (($id -eq $ProfileLeaf) -or ($id -like "*\$ProfileLeaf"))) { $hit = $true }
        foreach ($n in @($IdentityNames)) {
            if ($n -and (($id -eq $n) -or ($id -like "*\$n"))) { $hit = $true }
        }
        if (-not $hit) { continue }
        if ("$($rule.AccessControlType)" -eq 'Deny') { $deny = $true } else { $allow = $true }
    }
    if ($deny) { return $false }
    return [bool]$allow
}
function Get-CurrentIdentityNames {
    $names = New-Object System.Collections.Generic.List[string]
    if ($env:USERNAME) { [void]$names.Add([string]$env:USERNAME) }
    if ($env:USERDOMAIN -and $env:USERNAME) { [void]$names.Add("$($env:USERDOMAIN)\$($env:USERNAME)") }
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($me.Name) { [void]$names.Add([string]$me.Name) }
        if ($me.User) { [void]$names.Add([string]$me.User) }
        foreach ($g in @($me.Groups)) { if ($g) { [void]$names.Add([string]$g) } }
    } catch { }
    return @($names | Where-Object { $_ } | Select-Object -Unique)
}
function Test-ProfileFolderWritable([string]$Folder, [string]$ProfileLeaf) {
    $path = $Folder
    while ($path -and -not (Test-Path -LiteralPath $path)) {
        $parent = Split-Path -Parent $path
        if (-not $parent -or $parent -eq $path) { $path = $null; break }
        $path = $parent
    }
    if (-not $path) { return @{ Ok = $false; Why = 'lock folder and its parents are missing' } }
    $probeOk = $false
    try {
        $probe = Join-Path $path ('.lockcheck-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force
        $probeOk = $true
    } catch { $probeOk = $false }
    if (Get-Command Get-Acl -ErrorAction SilentlyContinue) {
        try {
            $acl = Get-Acl -LiteralPath $path
            $rules = @($acl.Access)
            if (Test-AclAllowsWrite $rules $ProfileLeaf (Get-CurrentIdentityNames)) { return @{ Ok = $true; Why = $path } }
            $deny = @($rules | Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and "$($_.FileSystemRights)" -match 'Write|Modify|FullControl' })
            if ($deny.Count) { return @{ Ok = $false; Why = "write is denied on $path" } }
        } catch { }
    }
    if ($probeOk) { return @{ Ok = $true; Why = $path } }
    return @{ Ok = $false; Why = "no write rule for $ProfileLeaf on $path" }
}
function Get-LockCheckProfiles {
    if ($env:WORKSTATION_LOCKCHECK_USERS) {
        if (-not (Test-Path -LiteralPath $env:WORKSTATION_LOCKCHECK_USERS)) { return @() }
        return @(Get-ChildItem -LiteralPath $env:WORKSTATION_LOCKCHECK_USERS -Force -Directory | ForEach-Object { $_.FullName })
    }
    $paths = @()
    try {
        $paths = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special -and $_.LocalPath } | ForEach-Object { [string]$_.LocalPath })
    } catch { }
    if (-not $paths -and $env:USERPROFILE) { $paths = @($env:USERPROFILE) }
    $skip = @('public', 'default', 'default user', 'all users', 'defaultaccount', 'wdagutilityaccount')
    return @($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and ($skip -notcontains (Split-Path -Leaf $_).ToLower()) })
}
function Get-ProfileProjectsRoot([string]$Profile) {
    $cfg = Join-ProfilePath $Profile @('AppData', 'Local', $WsStateName, $WsConfigName)
    if (-not (Test-Path -LiteralPath $cfg)) { return $null }
    try { return ([string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).projectsRoot).TrimEnd('\', '/') } catch { return $null }
}
function Show-AppLocks {
    $box = @{ n = 0 }
    function Add-Item([string]$State, [string]$Msg) {
        Write-Host ("{0}  {1}" -f $State, $Msg)
        if ($State -eq 'FAIL') { $box.n++ }
    }
    function Add-RuleFile([string]$Label, [string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { Add-Item 'FAIL' "$Label missing: $Path"; return }
        try { $text = [IO.File]::ReadAllText($Path) } catch { Add-Item 'FAIL' "$Label unreadable: $Path ($($_.Exception.Message))"; return }
        if (Test-LockRuleComplete $text) { Add-Item 'PASS' "$Label has acquire, check-in, and release for harness.design: $Path" }
        else { Add-Item 'FAIL' "$Label missing [$($(Get-LockRuleGaps $text) -join ', ')]: $Path" }
    }
    # The workstation-core plugin's SessionStart hook (hooks\rules-inject.ps1) loads the lock rule in Claude Code
    # (the installed catalog copy) and Cursor (the local copy), so a profile passes when that copy has the hook even
    # if no rule file has the text. Cowork is not checked here: its hooks run in its own sandbox, where run-ps.sh
    # finds no PowerShell and reports WORKSTATION RULES NOT LOADED (hooks/README.md). Claude chat runs no hooks.
    function Find-RulesHook([string]$Dir) {
        if (-not (Test-Path -LiteralPath $Dir)) { return $null }
        $hit = Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter 'rules-inject.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
        return $null
    }
    Write-Host 'App locks (read-only): harness.design and Fusion Desktop' -ForegroundColor Cyan
    $selfScript = Join-Path $BridgeRoot 'app-lock\app-lock.ps1'
    if ($env:WORKSTATION_LOCKCHECK_SCRIPT) { $selfScript = $env:WORKSTATION_LOCKCHECK_SCRIPT }
    $scripts = New-Object System.Collections.Generic.List[string]
    $seenScript = @{}
    if ($selfScript -and -not $seenScript.ContainsKey($selfScript.ToLower())) { [void]$scripts.Add($selfScript); $seenScript[$selfScript.ToLower()] = $true }
    $shell = Get-LockShell

    $profiles = @(Get-LockCheckProfiles)
    $roots = New-Object System.Collections.Generic.List[string]
    $seenRoot = @{}
    $profilesWithApps = 0
    foreach ($profile in $profiles) {
        $leaf = Split-Path -Leaf $profile
        $hasClaude = Test-Path -LiteralPath (Join-Path $profile '.claude')
        $hasCursor = Test-Path -LiteralPath (Join-Path $profile '.cursor')
        $desktopDirs = @(
            (Join-ProfilePath $profile @('AppData', 'Roaming', 'Claude')),
            (Join-ProfilePath $profile @('AppData', 'Local', 'Claude-Data')),
            (Join-ProfilePath $profile @('AppData', 'Local', 'AnthropicClaude'))
        )
        $hasDesktop = $false
        foreach ($d in $desktopDirs) { if (Test-Path -LiteralPath $d) { $hasDesktop = $true } }
        if (-not ($hasClaude -or $hasCursor -or $hasDesktop)) { continue }
        $profilesWithApps++
        $folder = Join-ProfilePath $profile @('AppData', 'Local', $WsStateName)
        $w = Test-ProfileFolderWritable $folder $leaf
        if ($w.Ok) { Add-Item 'PASS' "$leaf lock folder writable: $($w.Why)" }
        else { Add-Item 'FAIL' "$leaf lock folder not writable ($folder): $($w.Why)" }
        if ($hasClaude) {
            $claudeMd = Join-ProfilePath $profile @('.claude', 'CLAUDE.md')
            $claudeText = $null
            if (Test-Path -LiteralPath $claudeMd) { try { $claudeText = [IO.File]::ReadAllText($claudeMd) } catch { } }
            $cc = Get-ClaudeCodeWorkstationCore -UserRoot $profile -PluginsDir (Join-ProfilePath $profile @('.claude', 'plugins'))
            if ($claudeText -and (Test-LockRuleComplete $claudeText)) { Add-Item 'PASS' "$leaf Claude Code CLAUDE.md has acquire, check-in, and release for harness.design: $claudeMd" }
            elseif ($cc.Installed -and $cc.Enabled -and $cc.HasRulesHook) { Add-Item 'PASS' "$leaf Claude Code gets the harness.design lock rule from the installed workstation-core SessionStart hook ($(Get-ShortSha $cc.Sha)): $($cc.RulesHook)" }
            else { Add-Item 'FAIL' "$leaf Claude Code: no harness.design lock rule in $claudeMd and no enabled $WsCatalogPluginId copy with hooks\rules-inject.ps1 (installed_plugins.json). Install it from the workstation-plugins catalog (INSTALL.md, Claude Code section)." }
        }
        if ($hasCursor) {
            $rulesDir = Join-ProfilePath $profile @('.cursor', 'rules')
            $ruleFiles = @()
            if (Test-Path -LiteralPath $rulesDir) {
                $ruleFiles = @(Get-ChildItem -LiteralPath $rulesDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(mdc|md)$' })
            }
            foreach ($extraName in @('user-rules.md', 'rules.md')) {
                $extra = Join-ProfilePath $profile @('.cursor', $extraName)
                if (Test-Path -LiteralPath $extra) { $ruleFiles += @(Get-Item -LiteralPath $extra) }
            }
            $cursorHook = Find-RulesHook (Join-ProfilePath $profile @('.cursor', 'plugins'))
            if ($cursorHook) { Add-Item 'PASS' "$leaf Cursor gets the harness.design lock rule from the workstation-core sessionStart hook: $cursorHook" }
            elseif (-not $ruleFiles) { Add-Item 'FAIL' "$leaf Cursor rules: .cursor exists but no .mdc/.md rule file and no workstation-core plugin hook (rules-inject.ps1) under .cursor\plugins was found" }
            else {
                $hit = $null
                foreach ($rf in $ruleFiles) {
                    try { $t = [IO.File]::ReadAllText($rf.FullName) } catch { continue }
                    if (Test-LockRuleComplete $t) { $hit = $rf.FullName; break }
                }
                if ($hit) { Add-Item 'PASS' "$leaf Cursor rules have acquire, check-in, and release for harness.design: $hit" }
                else { Add-Item 'FAIL' "$leaf Cursor rules: none of the $($ruleFiles.Count) file(s) under .cursor have acquire, check-in, and release for harness.design" }
            }
            Add-Item 'SKIP' "$leaf Cursor account User Rules are not a file on disk (they follow the Cursor account). Checked .cursor rules files."
        }
        if ($hasDesktop) {
            $found = @()
            $names = @('CLAUDE.md', 'instructions.md', 'instructions-for-claude.md', 'cowork-global-instructions.md', 'global-instructions.md')
            foreach ($d in $desktopDirs) {
                if (-not (Test-Path -LiteralPath $d)) { continue }
                foreach ($name in $names) {
                    $one = Join-Path $d $name
                    if (Test-Path -LiteralPath $one -PathType Leaf) { $found += $one }
                }
                foreach ($sub in @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue)) {
                    foreach ($name in $names) {
                        $one = Join-Path $sub.FullName $name
                        if (Test-Path -LiteralPath $one -PathType Leaf) { $found += $one }
                    }
                }
            }
            if (-not $found) { Add-Item 'SKIP' "$leaf Claude Desktop/Cowork instructions are not a file (account box). Paste instructions\cowork-global-instructions.md and instructions\instructions-for-claude.md by hand." }
            else { foreach ($f in $found) { Add-RuleFile "$leaf Claude Desktop/Cowork" $f } }
        }
        $root = Get-ProfileProjectsRoot $profile
        if (-not $root) { Add-Item 'FAIL' "$leaf projects AGENTS.md: no projectsRoot in $(Join-ProfilePath $profile @('AppData', 'Local', $WsStateName, $WsConfigName))" }
        elseif (-not $seenRoot.ContainsKey($root.ToLower())) { [void]$roots.Add($root); $seenRoot[$root.ToLower()] = $true }
    }
    if (-not $profilesWithApps) { Add-Item 'FAIL' 'no Windows profile with Claude Code, Cursor, or Claude Desktop was found to check' }
    if (-not $env:WORKSTATION_LOCKCHECK_SCRIPT) {
        foreach ($root in @($roots)) {
            $active = Join-Path $root 'active'
            if (-not (Test-Path -LiteralPath $active)) { continue }
            foreach ($d in @(Get-ChildItem -LiteralPath $active -Directory -ErrorAction SilentlyContinue)) {
                $cand = Join-Path $d.FullName (Join-Path 'workstation' (Join-Path 'app-lock' 'app-lock.ps1'))
                if ((Test-Path -LiteralPath $cand) -and -not $seenScript.ContainsKey($cand.ToLower())) { [void]$scripts.Add($cand); $seenScript[$cand.ToLower()] = $true }
            }
        }
    }
    if (-not $scripts.Count) { Add-Item 'FAIL' 'lock script not found' }
    foreach ($scriptPath in @($scripts)) {
        if (-not (Test-Path -LiteralPath $scriptPath)) { Add-Item 'FAIL' "lock script missing: $scriptPath"; continue }
        if (-not $shell) { Add-Item 'FAIL' 'powershell not found to run the lock script'; continue }
        foreach ($pair in @(@('harness-design', 'harness.design'), @('fusion-desktop', 'Fusion Desktop'))) {
            $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, 'status', '-Name', $pair[0])
            $out = & $shell @arg 2>&1
            $code = $LASTEXITCODE
            $text = (($out | ForEach-Object { "$_" }) -join ' ')
            if ($code -eq 0) { Add-Item 'PASS' "$($pair[1]) lock script status runs (exit 0): $scriptPath" }
            else { Add-Item 'FAIL' "$($pair[1]) lock script status failed (exit $code): $scriptPath $text" }
        }
    }
    $ruleSeen = @{}
    $shared = Join-Path (Split-Path -Parent $BridgeRoot) (Join-Path 'instructions' 'projects-AGENTS.md')
    Add-RuleFile 'projects AGENTS.md (shared rules)' $shared
    $ruleSeen[$shared.ToLower()] = $true
    foreach ($root in @($roots)) {
        $agents = Join-Path $root 'AGENTS.md'
        if (-not $ruleSeen.ContainsKey($agents.ToLower())) { Add-RuleFile 'projects AGENTS.md' $agents; $ruleSeen[$agents.ToLower()] = $true }
        $active = Join-Path $root 'active'
        if (-not (Test-Path -LiteralPath $active)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $active -Directory -ErrorAction SilentlyContinue)) {
            $one = Join-Path $d.FullName (Join-Path 'instructions' 'projects-AGENTS.md')
            if ((Test-Path -LiteralPath $one) -and -not $ruleSeen.ContainsKey($one.ToLower())) { Add-RuleFile 'projects AGENTS.md (shared rules)' $one; $ruleSeen[$one.ToLower()] = $true }
        }
    }
    Add-Item 'SKIP' 'Grok Bot: this repo does not track a separate instruction file. Grok reads instructions/projects-AGENTS.md (checked above).'
    if ($box.n) { Write-Host "FAIL  $($box.n) item(s)" } else { Write-Host 'PASS  all checked items' }
    return [int]$box.n
}
