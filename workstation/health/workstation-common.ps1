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
$global:WsHealthFails = 0
function Write-Ok([string]$m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Run([string]$m)  { Write-Host "  [ RUN ] $m" -ForegroundColor Green }
function Write-Stop([string]$m) { Write-Host "  [STOP] $m" -ForegroundColor DarkGray }
function Write-Off([string]$m)  { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Write-Warn([string]$m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Bad([string]$m)  { $global:WsHealthFails++; Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-HealthLevel([string]$Level, [string]$Text) {
    if ($Level -eq 'WARN') { Write-Warn $Text }
    elseif ($Level -eq 'FAIL') { Write-Bad $Text }
    elseif ($Level -eq 'STOP') { Write-Stop $Text }
    elseif ($Level -eq 'SKIP') { Write-Off $Text }
    else { Write-Run $Text }
}

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
        $refs = @($hookCmds | Where-Object { $_.Command -match [regex]::Escape($pair.Leaf) })
        if (-not (Test-Path -LiteralPath $pair.File)) { Write-Warn "$($pair.Leaf) missing: $($pair.File)" }
        elseif (-not $refs) { Write-Warn "$($pair.Leaf) is not wired in settings.json" }
        else {
            $bad = @($refs | Where-Object { $p = Get-PathFromCommand $_.Command; $p -and -not (Test-Path -LiteralPath $p) })
            if ($bad) { Write-Bad "$($pair.Leaf) points at a missing script" }
            else { Write-Ok "$($pair.Leaf) hook: $(($refs | ForEach-Object Event | Sort-Object -Unique) -join ', ')" }
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
        $ifv = $null
        foreach ($pn in 'cc-plugin-agents-md@builtin','agents-md@builtin') {
            $pc = $null; if ($settings.pluginConfigs) { $pc = $settings.pluginConfigs.$pn }
            if ($pc -and $pc.options -and $pc.options.instructionFiles) { $ifv = "$($pc.options.instructionFiles)"; break }
        }
        if ($ifv -eq 'claude-md-and-agents-md') { Write-Ok "Claude reads both CLAUDE.md and AGENTS.md ($ifv)" }
        else { Write-Warn "Claude read-both setting is off (instructionFiles=$(if($ifv){$ifv}else{'unset'}))" }
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

function Show-Skills {
    Write-Host ''
    Write-Host 'Skills' -ForegroundColor Cyan
    Write-Off (Get-ClaudeAiSyncedCopyText -UserRoot $HOME)
    $repo = Split-Path -Parent $BridgeRoot
    foreach ($line in @(Get-PluginVersionReports -UserRoot $HOME -RepoRoot $repo)) {
        Write-HealthLevel $line.Level $line.Text
    }
}

function Show-DcRemote {
    Write-Host ''
    Write-Host 'Desktop Commander remote' -ForegroundColor Cyan
    $rows = @(Get-DcRemoteRows)
    if ($rows.Count -eq 0) {
        Write-Stop 'Desktop Commander remote is not running (manual Start only; one copy serves all chats)'
        return
    }
    $keep = Get-DcRemoteKeep $rows
    $extra = @($rows | Where-Object { -not $_.Keep })
    if ($rows.Count -eq 1 -and $keep -and $keep.Healthy) {
        Write-Run "Desktop Commander remote: one copy pid $($keep.Pid) online (one copy serves all chats)"
        return
    }
    if ($rows.Count -eq 1) {
        Write-Bad "Desktop Commander remote died or is broken: pid $($rows[0].Pid) $($rows[0].Verdict) (one copy serves all chats)"
        return
    }
    if ($keep) {
        Write-Warn "Desktop Commander remote: pid $($keep.Pid) online; $($extra.Count) extra (one copy serves all chats)"
    } else {
        Write-Bad "Desktop Commander remote died or is broken: $($rows.Count) copies, no healthy copy (one copy serves all chats)"
    }
}

function Show-DcAutostart {
    $hits = @()
    $startup = [Environment]::GetFolderPath('Startup')
    if ($startup -and (Test-Path -LiteralPath $startup)) {
        $wsh = $null
        try { $wsh = New-Object -ComObject WScript.Shell } catch { $wsh = $null }
        foreach ($l in @(Get-ChildItem -LiteralPath $startup -Filter *.lnk -ErrorAction SilentlyContinue)) {
            $cmd = ''
            if ($wsh) { try { $s = $wsh.CreateShortcut($l.FullName); $cmd = "$($s.TargetPath) $($s.Arguments)" } catch { $cmd = '' } }
            if ($cmd -match 'start-dc-remote\.ps1') { $hits += $l.FullName }
        }
    }
    foreach ($run in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')) {
        if (-not (Test-Path -LiteralPath $run)) { continue }
        try { $props = Get-ItemProperty -LiteralPath $run -ErrorAction Stop } catch { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $v = [string]$p.Value
            if ($v -match 'start-dc-remote\.ps1') { $hits += "Run:$($p.Name)" }
        }
    }
    if ($hits) { Write-Warn ("Desktop Commander remote has a Windows startup entry: " + ($hits -join ', ')) }
    else { Write-Run 'Desktop Commander remote has no Windows startup entry' }
}

function Show-CursorWorker {
    Write-Host ''
    Write-Host 'Cursor worker' -ForegroundColor Cyan
    foreach ($line in @(Get-CursorWorkerHealthLines)) {
        Write-HealthLevel $line.Level $line.Text
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
    # Claude Code loads the lock rule from the enabled workstation-core copy in
    # installed_plugins.json (hooks\rules-inject.ps1), not from the first cache folder.
    # Cowork is unverified: hooks/run-ps.sh exits 0 and does nothing when powershell and
    # pwsh are missing, and Cowork is likely a Linux sandbox.
    # The Cursor desktop app loads it from ~/.cursor/plugins/local/workstation-core.
    # Whether a Cursor worker session runs hooks/cursor-hooks.json is unverified.
    function Find-ClaudeRulesHook([string]$Profile) {
        if (-not (Get-Command Get-EnabledWorkstationCoreRoot -ErrorAction SilentlyContinue)) { return $null }
        $root = Get-EnabledWorkstationCoreRoot -UserRoot $Profile
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { return $null }
        $direct = Join-Path $root 'hooks/rules-inject.ps1'
        if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
        $hit = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'rules-inject.ps1' -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($hit) { return $hit.FullName }
        return $null
    }
    function Find-CursorRulesHook([string]$Profile) {
        $direct = Join-ProfilePath $Profile @('.cursor', 'plugins', 'local', 'workstation-core', 'hooks', 'rules-inject.ps1')
        if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
        return $null
    }
    Write-Host 'App locks (read-only): harness.design' -ForegroundColor Cyan
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
            $claudeHook = Find-ClaudeRulesHook $profile
            if ($claudeText -and (Test-LockRuleComplete $claudeText)) { Add-Item 'PASS' "$leaf Claude Code CLAUDE.md has acquire, check-in, and release for harness.design: $claudeMd" }
            elseif ($claudeHook) { Add-Item 'PASS' "$leaf Claude Code gets the harness.design lock rule from the enabled workstation-core copy: $claudeHook" }
            else { Add-Item 'FAIL' "$leaf Claude Code: no harness.design lock rule in $claudeMd and no rules-inject.ps1 in the enabled workstation-core copy (installed_plugins.json). Install workstation-core from the workstation-plugins catalog (INSTALL.md, Claude Code section)." }
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
            $cursorHook = Find-CursorRulesHook $profile
            if ($cursorHook) { Add-Item 'PASS' "$leaf Cursor gets the harness.design lock rule from the local workstation-core sessionStart hook: $cursorHook" }
            elseif (-not $ruleFiles) { Add-Item 'FAIL' "$leaf Cursor rules: .cursor exists but no .mdc/.md rule file and no rules-inject.ps1 in .cursor\plugins\local\workstation-core" }
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
        # The comma keeps this one pair. Without it PowerShell flattens the list and -Name becomes "h".
        foreach ($pair in @(,@('harness-design', 'harness.design'))) {
            $name = [string]$pair[0]
            $label = [string]$pair[1]
            $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, 'status', '-Name', $name)
            $out = & $shell @arg 2>&1
            $code = $LASTEXITCODE
            $text = (($out | ForEach-Object { "$_" }) -join ' ')
            if ($code -eq 0) { Add-Item 'PASS' "$label lock script runs (status exit 0): $scriptPath" }
            else { Add-Item 'FAIL' "$label lock script status failed (exit $code): $scriptPath $text" }
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
