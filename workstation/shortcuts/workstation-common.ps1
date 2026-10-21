# Shared helpers for the Bridge desktop shortcuts. Dot-sourced by the five shortcut scripts.
# Windows PowerShell 5.1 compatible. Keep this file ASCII-only.
$ErrorActionPreference = 'Continue'

$BridgeShortcuts = $PSScriptRoot
$BridgeRoot      = Split-Path -Parent $BridgeShortcuts   # the toolkit folder inside the workstation repo clone
# Toolkit paths: $WsProjectsRoot, $WsStateDir, $WsStopFlag, $WsLegacyFolders (runtime files never go in the clone).
. (Join-Path $BridgeRoot 'paths.ps1')
$BridgeProjects  = $WsProjectsRoot
$BridgeActive    = Join-Path $BridgeProjects 'active'
$BridgeWorkerDir = Join-Path $BridgeRoot 'cursor-worker'
$BridgeStopFlag  = $WsStopFlag
$GrokStatusFile  = Join-Path $env:APPDATA 'Grok Bot\desktop-status.json'

# Claude Code CLI: PATH first (skipping the Claude desktop app's WindowsApps alias), then usual install spots.
function Find-ClaudeExe {
    foreach ($n in @('claude.exe', 'claude')) {
        foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) {
            if ($c.Source -and $c.Source -notmatch '\\WindowsApps\\') { return $c.Source }
        }
    }
    $cands = @(
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:APPDATA 'npm\claude.cmd'),
        (Join-Path $env:ProgramFiles 'nodejs\claude.cmd')
    )
    foreach ($p in $cands) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

# Cursor CLI (`agent`): PATH first, then the default per-user install folder.
function Find-AgentCli {
    foreach ($n in @('agent', 'cursor-agent')) {
        $c = @(Get-Command $n -CommandType ExternalScript, Application -All -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($c -and $c.Source) { return $c.Source }
    }
    foreach ($p in @((Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.ps1'), (Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.cmd'))) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# Grok Bot desktop app: machine-wide or per-user install.
function Find-GrokBotExe {
    $cands = @()
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($root) { $cands += (Join-Path $root 'Grok Bot\Grok Bot.exe') }
    }
    foreach ($p in $cands) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}

$ClaudeExe = Find-ClaudeExe

# Cursor worker settings: $PidFile, $HealthUrl, $MgmtAddr, Get-SupervisorProcess, ...
. (Join-Path $BridgeWorkerDir 'config.ps1')

# Branch helpers (base-branch detection, failure reasons).
. (Join-Path $BridgeRoot 'repo-branch.ps1')

function Write-Title([string]$t) {
    Write-Host ''
    Write-Host "==== $t ====  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ''
}
function Write-Ok([string]$m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Write-Off([string]$m)  { Write-Host "  [ -- ] $m" -ForegroundColor DarkGray }
function Write-Warn([string]$m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Bad([string]$m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-Info([string]$m) { Write-Host "         $m" -ForegroundColor Gray }

function Wait-BridgeClose([switch]$NoPause) {
    if ($NoPause) { return }
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}

function Get-ProcSnapshot { @(Get-CimInstance Win32_Process) }

function Format-Pids($procs) { (@($procs) | ForEach-Object { $_.ProcessId }) -join ',' }

function Format-Age([TimeSpan]$ts) {
    if ($ts.TotalMinutes -lt 1) { return ('{0}s' -f [int]$ts.TotalSeconds) }
    if ($ts.TotalHours -lt 1)   { return ('{0}m' -f [int][Math]::Floor($ts.TotalMinutes)) }
    if ($ts.TotalDays -lt 1)    { return ('{0}h {1}m' -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes) }
    return ('{0}d {1}h' -f [int][Math]::Floor($ts.TotalDays), $ts.Hours)
}

# watch-pull loop: the powershell running watch-pull.ps1 and its wscript launcher.
function Get-WatchPullProcs($procs) {
    @($procs | Where-Object {
        $_.ProcessId -ne $PID -and
        $_.Name -in @('powershell.exe', 'pwsh.exe', 'wscript.exe') -and
        "$($_.CommandLine)" -match 'watch-pull\.ps1'
    })
}

# Cursor worker supervisor (run-worker.ps1). Copies started by the old scheduled task hide their
# command line, so the PID-file check from config.ps1 (name + start time) is used as well.
function Get-SupervisorProcs($procs) {
    $ids = @()
    $sup = Get-SupervisorProcess
    if ($sup) { $ids += $sup.Id }
    $ids += @($procs | Where-Object {
        $_.Name -in @('powershell.exe', 'pwsh.exe') -and "$($_.CommandLine)" -match 'cursor-worker\\run-worker\.ps1'
    } | ForEach-Object { $_.ProcessId })
    $ids = @($ids | Where-Object { $_ -and $_ -ne $PID } | Sort-Object -Unique)
    @($procs | Where-Object { $ids -contains $_.ProcessId })
}

# Hidden wscript launcher that waits on run-worker.ps1 (exists only when started via run-hidden.vbs).
function Get-SupervisorLaunchers($procs) {
    @($procs | Where-Object { $_.Name -eq 'wscript.exe' -and "$($_.CommandLine)" -match 'run-worker\.ps1' })
}

# `agent worker`: node.exe started by the supervisor through %LOCALAPPDATA%\cursor-agent\agent.ps1.
function Get-AgentWorkerProcs($procs, $supIds) {
    @($procs | Where-Object {
        $_.Name -eq 'node.exe' -and (
            (@($supIds) -contains $_.ParentProcessId) -or
            ("$($_.CommandLine)" -match 'cursor-agent' -and "$($_.CommandLine)" -match '\sworker\s' -and "$($_.CommandLine)" -match '--management-addr')
        )
    })
}

# Claude Code remote control started by Workers Start (`claude --bg --remote-control`).
# Matches ONLY the --remote-control session processes and the `--bg-pty-host` that hosts one (its inner
# command after ' -- ' is a --remote-control session, or a child of it is). Other `claude --bg` sessions,
# their PTY hosts and the shared `claude.exe daemon run` never match, so Stop and Status don't touch them.
function Test-RemoteControlArgs([string]$cmd) { $cmd -match '(^|\s)--remote-control(\s|$)' }
function Get-RemoteControlProcs($procs) {
    $procs = @($procs | Where-Object { $_.ProcessId -ne $PID -and $_.Name -in @('claude.exe', 'node.exe') })
    $sessions = @($procs | Where-Object { "$($_.CommandLine)" -notmatch '--bg-pty-host' -and (Test-RemoteControlArgs "$($_.CommandLine)") })
    $sessionParents = @($sessions | ForEach-Object { $_.ParentProcessId })
    $hosts = @($procs | Where-Object {
        $c = "$($_.CommandLine)"
        $c -match '--bg-pty-host' -and (
            (($c -split ' -- ', 2).Count -eq 2 -and (Test-RemoteControlArgs ($c -split ' -- ', 2)[1])) -or
            ($sessionParents -contains $_.ProcessId))
    })
    @($sessions) + @($hosts)
}

# Desktop Commander remote connector (`npx ... desktop-commander ... remote`).
# Started at logon by Startup\Desktop Commander Remote.lnk, or by the manual Start shortcut.
function Get-DesktopCommanderRemoteProcs($procs) {
    @($procs | Where-Object {
        $_.ProcessId -ne $PID -and
        "$($_.CommandLine)" -match 'desktop-commander' -and
        "$($_.CommandLine)" -match '\bremote\b' -and
        "$($_.CommandLine)" -notmatch 'start-dc-remote' -and
        "$($_.CommandLine)" -notmatch 'stop-dc-remote'
    })
}

# `claude --bg --remote-control` hands off to a background session named "remote-control".
# Returns the active ones from `claude agents --json`.
# Every active `claude --bg` session from `claude agents --json`. Sets $script:ClaudeAgentsOk = $false when the
# list couldn't be read, so callers never treat "unknown" as "none".
function Get-ClaudeBgSessions {
    $script:ClaudeAgentsOk = $false
    if (-not $ClaudeExe) { return @() }
    $list = $null
    try {
        $json = (& $ClaudeExe agents --json 2>$null) | Out-String
        if ($LASTEXITCODE -ne 0) { return @() }
        if ($json.Trim()) { $list = ConvertFrom-Json $json }
    } catch { return @() }
    $script:ClaudeAgentsOk = $true
    $out = @()
    foreach ($s in @($list)) {
        if ($null -eq $s) { continue }
        if ("$($s.state)" -notin @('stopped', 'done', 'failed')) { $out += $s }
    }
    return $out
}
function Get-RemoteControlSessions { @(Get-ClaudeBgSessions | Where-Object { "$($_.name)" -match 'remote-control' }) }

function Test-WorkerHealth {
    try {
        $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
        return "HTTP $($r.StatusCode)"
    } catch {
        return "not answering ($($_.Exception.Message))"
    }
}

function Show-BridgeStatus {
    $procs = Get-ProcSnapshot

    # Grok Bot (stays automatic; shown for reference)
    $grok = @(Get-Process -Name 'Grok Bot' -ErrorAction SilentlyContinue)
    $hb = ''
    if (Test-Path -LiteralPath $GrokStatusFile) {
        $fi = Get-Item -LiteralPath $GrokStatusFile
        $hb = "; status file written $(Format-Age ((Get-Date) - $fi.LastWriteTime)) ago"
        try {
            $j = Get-Content -LiteralPath $GrokStatusFile -Raw | ConvertFrom-Json
            if ($j.pid) {
                $alive = [bool](Get-Process -Id ([int]$j.pid) -ErrorAction SilentlyContinue)
                $hb += " (pid $($j.pid) alive=$alive signedIn=$($j.signedIn) v$($j.appVersion))"
            }
        } catch { }
    } else { $hb = '; no desktop-status.json' }
    if ($grok) { Write-Ok "Grok Bot running ($($grok.Count) procs)$hb" }
    else {
        $gexe = Find-GrokBotExe
        if ($gexe) { Write-Bad "Grok Bot NOT running (installed at $gexe)$hb" } else { Write-Bad "Grok Bot NOT running and not found under Program Files or LocalAppData\Programs$hb" }
    }

    # Cursor worker
    $sup = Get-SupervisorProcs $procs
    $supIds = @($sup | ForEach-Object { $_.ProcessId })
    $agents = Get-AgentWorkerProcs $procs $supIds
    if ($sup) {
        $up = ''
        try { $up = ', up ' + (Format-Age ((Get-Date) - (Get-Process -Id $supIds[0]).StartTime)) } catch { }
        Write-Ok "Cursor worker supervisor running (pid $(Format-Pids $sup)$up)"
    } else { Write-Off 'Cursor worker supervisor not running' }
    $health = Test-WorkerHealth
    if ($agents) {
        if ($health -eq 'HTTP 200') { Write-Ok "agent worker running (pid $(Format-Pids $agents)); $HealthUrl -> $health" }
        else { Write-Warn "agent worker running (pid $(Format-Pids $agents)); $HealthUrl -> $health" }
    } else {
        if ($health -like 'HTTP*') { Write-Warn "agent worker process not matched, but $HealthUrl -> $health" }
        else { Write-Off "agent worker not running; $HealthUrl $health" }
    }

    # Claude remote control
    $rc = Get-RemoteControlProcs $procs
    $rcs = Get-RemoteControlSessions
    if ($rc -or $rcs) {
        $parts = @()
        if ($rc)  { $parts += "process pid $(Format-Pids $rc)" }
        if ($rcs) { $parts += 'session ' + ((@($rcs) | ForEach-Object { "$($_.id) [$($_.state)]" }) -join ', ') }
        Write-Ok "Claude remote control running ($($parts -join '; '))"
    } else { Write-Off 'Claude remote control not running' }

    # watch-pull (should be off; pulls are manual, one repo at a time)
    $wp = Get-WatchPullProcs $procs
    if ($wp) { Write-Warn "watch-pull RUNNING (pid $(Format-Pids $wp)) - should be off; Workers Stop ends it" }
    else { Write-Ok 'watch-pull off (pulls are manual, one repo at a time)' }

    $dc = Get-DesktopCommanderRemoteProcs $procs
    if ($dc) { Write-Ok "Desktop Commander remote running (pid $(Format-Pids $dc))" }
    else { Write-Off 'Desktop Commander remote not running' }

    # Stop flag
    if (Test-Path -LiteralPath $BridgeStopFlag) {
        $since = (Get-Item -LiteralPath $BridgeStopFlag).LastWriteTime
        Write-Warn "stop flag PRESENT since $($since.ToString('yyyy-MM-dd HH:mm')) (health check will not revive the worker; Workers Start clears it)"
    } else { Write-Ok 'stop flag absent' }
}

# Run a command in a background job with a timeout; returns its text output or $null on timeout.
function Invoke-WithTimeout([scriptblock]$Block, [object[]]$ArgList, [int]$Seconds = 30) {
    $job = Start-Job -ScriptBlock $Block -ArgumentList $ArgList
    try {
        if (Wait-Job $job -Timeout $Seconds) { return ((Receive-Job $job 2>&1) | Out-String) }
        return $null
    } finally { Remove-Job $job -Force -ErrorAction SilentlyContinue }
}

# Read-only checks of everything the shortcuts need. Used by install-shortcuts.ps1.
function Show-Prerequisites {
    Write-Host 'Prerequisites' -ForegroundColor Cyan

    $pol = @(Get-ExecutionPolicy -List | Where-Object { $_.Scope -in @('MachinePolicy', 'UserPolicy') -and "$($_.ExecutionPolicy)" -notin @('Undefined', 'Bypass', 'Unrestricted', 'RemoteSigned') })
    if ($pol) { Write-Bad ("execution policy forced by Group Policy: " + (($pol | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join ', ') + " (shortcuts use -ExecutionPolicy Bypass, which a GPO can override)") }
    else { Write-Ok 'execution policy: no Group Policy override (shortcuts pass -ExecutionPolicy Bypass)' }

    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) { Write-Ok "git: $((& git --version) 2>$null) ($($git.Source))" } else { Write-Bad 'git not found on PATH (per-repo pull/push and Workstation Status need it)' }

    if (Test-Path -LiteralPath $BridgeActive) {
        $withOrigin = @(); $other = @()
        foreach ($d in (Get-ChildItem -LiteralPath $BridgeActive -Directory | Sort-Object Name)) {
            $o = $null
            if ($git -and (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { $o = (& git -C $d.FullName remote get-url origin 2>$null) }
            if ($o) { $withOrigin += $d.Name } else { $other += $d.Name }
        }
        if ($withOrigin) { Write-Ok "active\ repos with origin: $($withOrigin -join ', ')" } else { Write-Warn "no active\ project is a git repo with an origin remote yet" }
        if ($other) { Write-Info "skipped by pull/push (no git or no origin): $($other -join ', ')" }
        if ($git -and $withOrigin) {
            $first = Join-Path $BridgeActive $withOrigin[0]
            $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'never'
            & git -C $first ls-remote --heads origin *> $null
            $ok = ($LASTEXITCODE -eq 0)
            Remove-Item Env:GIT_TERMINAL_PROMPT, Env:GCM_INTERACTIVE -ErrorAction SilentlyContinue
            if ($ok) { Write-Ok "GitHub access without prompting works ($($withOrigin[0]))" }
            else { Write-Bad "git ls-remote failed for $($withOrigin[0]) with prompts disabled: set up credentials (e.g. Git Credential Manager or 'gh auth login') and network" }
        }
    } else { Write-Bad "active folder not found: $BridgeActive" }

    $agent = Find-AgentCli
    if ($agent) {
        $out = Invoke-WithTimeout { param($a) & $a status } @($agent) 40
        if ($null -eq $out) { Write-Warn "Cursor CLI found ($agent) but 'agent status' timed out" }
        elseif ($out -match 'Logged in') { Write-Ok "Cursor CLI: $agent - $(($out -split "`n" | Where-Object { $_ -match 'Logged in' } | Select-Object -First 1).Trim())" }
        else { Write-Bad "Cursor CLI found ($agent) but not logged in: run 'agent login'" }
    } else { Write-Bad "Cursor CLI 'agent' not found (Workers Start needs it for the Cursor worker)" }

    if ($ClaudeExe) {
        $out = Invoke-WithTimeout { param($c) & $c auth status } @($ClaudeExe) 40
        $li = $false
        try { $li = [bool]((ConvertFrom-Json $out).loggedIn) } catch { }
        if ($li) { Write-Ok "Claude Code CLI: $ClaudeExe - logged in" }
        else { Write-Bad "Claude Code CLI found ($ClaudeExe) but not logged in (run 'claude' once and sign in)" }
    } else { Write-Bad "Claude Code CLI (claude.exe) not found (Workers Start needs it for remote control)" }

    $gexe = Find-GrokBotExe
    if ($gexe) { Write-Ok "Grok Bot installed: $gexe (optional; open it if you want Grok Bot checks)" }
    else { Write-Warn 'Grok Bot not installed (optional)' }

    try {
        $code = (Invoke-WebRequest -Uri 'https://github.com' -Method Head -UseBasicParsing -TimeoutSec 8).StatusCode
        Write-Ok "network: github.com reachable (HTTP $code)"
    } catch { Write-Bad "network: github.com not reachable ($($_.Exception.Message))" }
}

# Project branches (read-only): base-branch rule and WARN text.
function Show-BranchStatus([string]$Root = $BridgeActive) {
    Write-Host ''
    Write-Host 'Project branches' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $Root)) { Write-Warn "active folder not found: $Root"; return }
    $any = $false
    foreach ($d in (Get-ChildItem -LiteralPath $Root -Directory -Force | Sort-Object Name)) {
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { continue }
        $remotes = @(& git -C $d.FullName remote 2>$null)
        if ($remotes.Count -eq 0) { continue }
        $any = $true
        $info = Get-RepoBranchInfo $d.FullName
        if ($info.IsBase) { Write-Ok "$($d.Name): on base branch '$($info.Branch)'" }
        else { Write-Warn (Format-BranchWarning $d.Name $info) }
    }
    if (-not $any) { Write-Off 'no active\ git repos with a remote' }
}

# ---- Automations (read-only) -------------------------------------------------------------
# Uses Write-Ok/Write-Warn/Write-Bad/Format-Age from above.
# Strictly read-only; no admin needed. Missing items print [WARN] (they may never have been
# installed on this PC); [FAIL] only when something is configured but broken.

$RunKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Get-RunValue([string]$name) {
    try { return (Get-ItemProperty -Path $RunKeyPath -Name $name -ErrorAction Stop).$name } catch { return $null }
}

# First path in a command line: "quoted path" or an unquoted token ending in .exe/.ps1/.vbs/.cmd/.bat
function Get-PathFromCommand([string]$cmd, [string]$ext = 'exe|ps1|vbs|cmd|bat') {
    if (-not $cmd) { return $null }
    $m = [regex]::Match($cmd, '"([^"]+\.(?:' + $ext + '))"', 'IgnoreCase')
    if (-not $m.Success) { $m = [regex]::Match($cmd, '(\S+\.(?:' + $ext + '))(?:\s|$)', 'IgnoreCase') }
    if (-not $m.Success) { return $null }
    return (Expand-UserPath $m.Groups[1].Value)
}

# Expand ~, $HOME, %VAR% and $env:VAR; normalize slashes.
function Expand-UserPath([string]$p) {
    if (-not $p) { return $p }
    $p = $p.Trim()
    if ($p -match '^~(?=[\\/]|$)') { $p = $HOME + $p.Substring(1) }
    if ($p -match '^\$HOME(?=[\\/]|$)') { $p = $HOME + $p.Substring(5) }
    $p = [regex]::Replace($p, '\$env:([A-Za-z_][A-Za-z0-9_]*)', { param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value) })
    $p = [Environment]::ExpandEnvironmentVariables($p)
    return ($p -replace '/', '\')
}

# Returns @{ Status = 'ok'|'missing'|'denied'|'error'; Task; Info; Msg }
function Get-TaskSafe([string]$name, [switch]$WithInfo) {
    $r = @{ Status = 'ok'; Task = $null; Info = $null; Msg = '' }
    try {
        $r.Task = Get-ScheduledTask -TaskName $name -ErrorAction Stop | Select-Object -First 1
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'No MSFT_ScheduledTask objects found|cannot find|not found') { $r.Status = 'missing' }
        elseif ($msg -match 'Access is denied|0x80070005') { $r.Status = 'denied' }
        else { $r.Status = 'error'; $r.Msg = $msg }
        return $r
    }
    if ($WithInfo) {
        try { $r.Info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop }
        catch { $r.Msg = if ($_.Exception.Message -match 'Access is denied|0x80070005') { "can't read run history without admin" } else { $_.Exception.Message } }
    }
    return $r
}

function Format-TaskResult($info) {
    if (-not $info) { return 'last run unknown' }
    $code = [int64]$info.LastTaskResult
    $when = if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'never' }
    $txt = switch ($code) {
        0      { 'OK (0)' }
        267009 { 'running (0x41301)' }
        267011 { 'not run yet (0x41303)' }
        default { ('0x{0:X}' -f $code) }
    }
    return "last run $when, result $txt"
}

# Common task check. Returns the Get-TaskSafe result for extra checks.
function Test-AutomationTask([string]$name, [string]$label) {
    $t = Get-TaskSafe $name -WithInfo
    switch ($t.Status) {
        'missing' { Write-Warn "$label task '$name' not found (not installed on this PC?)"; return $t }
        'denied'  { Write-Warn "$label task '$name': can't read without admin"; return $t }
        'error'   { Write-Warn "$label task '$name': could not read ($($t.Msg))"; return $t }
    }
    $state = "$($t.Task.State)"
    $res = Format-TaskResult $t.Info
    if ($t.Msg) { $res = $t.Msg }
    $code = if ($t.Info) { [int64]$t.Info.LastTaskResult } else { 0 }
    if ($state -eq 'Disabled') { Write-Bad "$label task '$name' is DISABLED; $res" }
    elseif ($code -notin @(0, 267009, 267011)) { Write-Warn "$label task '$name' $state; $res" }
    else { Write-Ok "$label task '$name' $state; $res" }
    return $t
}

# Startup Apps toggle for a Startup-folder shortcut or Run value (read-only).
# StartupApproved first byte: even = on, odd = off. No value = never toggled = on.
function Get-StartupToggleInfo([string]$kind, [string]$name) {
    foreach ($hive in @('HKCU:', 'HKLM:')) {
        $k = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$kind"
        try { $b = (Get-ItemProperty -Path $k -Name $name -ErrorAction Stop).$name } catch { continue }
        if ($b -and $b.Length -gt 0) {
            $st = if (($b[0] % 2) -eq 1) { 'off' } else { 'on' }
            return @{ State = $st; Key = $k; Name = $name }
        }
    }
    return @{ State = 'on'; Key = $null; Name = $name }
}
function Get-StartupToggle([string]$kind, [string]$name) { (Get-StartupToggleInfo $kind $name).State }

# Startup toggle of a Store (MSIX) app's StartupTask (read-only). State 2/4 = on, 0/1/3 = off.
function Get-PackagedStartupState([string]$pkgName) {
    $pkg = Get-AppxPackage -Name $pkgName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pkg) { return @{ State = 'nopkg'; TaskId = ''; Key = $null } }
    $ids = @()
    try {
        $mf = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
        $ids = @([regex]::Matches((Get-Content -LiteralPath $mf -Raw -ErrorAction Stop), 'StartupTask[^>]*TaskId="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    } catch { }
    if (-not $ids) { return @{ State = 'unknown'; TaskId = 'no startup task in manifest'; Key = $null } }
    $base = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$($pkg.PackageFamilyName)"
    $id = $ids[0]
    $key = Join-Path $base $id
    try { $s = (Get-ItemProperty -Path $key -Name State -ErrorAction Stop).State } catch { return @{ State = 'off'; TaskId = $id; Key = $key } }
    if ($s -in @(2, 4)) { return @{ State = 'on'; TaskId = $id; Key = $key } }
    if ($s -eq 3) { return @{ State = 'policy'; TaskId = $id; Key = $key } }
    return @{ State = 'off'; TaskId = $id; Key = $key }
}

# Switched-off startup apps found by Show-Automations; Invoke-StartupFixOffer asks to turn each back on.
$script:StartupOff = @()

# Interactive only (Workstation Status without -NoPause). Asks per app; changes nothing on "n".
function Invoke-StartupFixOffer {
    if (-not $script:StartupOff) { return }
    Write-Host ''
    foreach ($o in $script:StartupOff) {
        $ans = Read-Host "  $($o.Label) startup is OFF. Turn it back on? [y/N]"
        if ($ans -notmatch '^(y|yes)$') { Write-Off "$($o.Label) startup left off"; continue }
        try {
            if ($o.Type -eq 'approved') {
                $b = [byte[]](Get-ItemProperty -Path $o.Key -Name $o.Name -ErrorAction Stop).($o.Name)
                $b[0] = 2
                Set-ItemProperty -Path $o.Key -Name $o.Name -Value $b -Type Binary -ErrorAction Stop
                $now = (Get-StartupToggleInfo $o.Kind $o.Name).State
            } else {
                if (-not (Test-Path -LiteralPath $o.Key)) { New-Item -Path $o.Key -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $o.Key -Name State -Value 2 -Type DWord -ErrorAction Stop
                $now = (Get-PackagedStartupState $o.Pkg).State
            }
            if ($now -eq 'on') { Write-Ok "$($o.Label) startup turned on" } else { Write-Warn "$($o.Label) startup still reads $now; use Settings > Apps > Startup" }
        } catch {
            if ($_.Exception.Message -match 'denied|Requested registry access') { Write-Warn "$($o.Label): needs admin; use Settings > Apps > Startup" }
            else { Write-Warn "$($o.Label): could not turn on ($($_.Exception.Message)); use Settings > Apps > Startup" }
        }
    }
}

function Show-Automations {
    Write-Host ''
    Write-Host 'Automations (read-only)' -ForegroundColor Cyan

    # 1. GrokBot Run entry
    $v = Get-RunValue 'GrokBot'
    if (-not $v) { Write-Warn 'HKCU Run GrokBot missing (Grok Bot will not open at logon)' }
    else {
        $exe = Get-PathFromCommand $v 'exe'
        if ($exe -and (Test-Path -LiteralPath $exe)) { Write-Ok "HKCU Run GrokBot -> $exe" }
        else { Write-Bad "HKCU Run GrokBot points at a missing file: $v" }
    }

    # 2. Latch-EnsureGrokBot task + its script (runs straight from this toolkit: <toolkit>\latch\ensure-grokbot.ps1)
    $lt = Test-AutomationTask 'Latch-EnsureGrokBot' 'Grok Bot launcher'
    $egWant = Join-Path $BridgeRoot 'latch\ensure-grokbot.ps1'
    if ($lt.Status -eq 'ok') {
        $eg = $null
        foreach ($a in @($lt.Task.Actions)) { if (-not $eg) { $eg = Get-PathFromCommand "$($a.Arguments)" 'ps1' } }
        if (-not $eg) { Write-Warn "Grok Bot launcher task has no script path in its action" }
        elseif (-not (Test-Path -LiteralPath $eg)) { Write-Bad "Grok Bot launcher task runs a missing script: $eg" }
        elseif ($eg -ieq $egWant) { Write-Ok "launcher script (from the repo clone): $eg" }
        else { Write-Warn "Grok Bot launcher task still runs an old copy ($eg); re-run install-admin.ps1 (admin) so it runs $egWant" }
    }

    # 3. Claude-Memory-To-Cursor-Sync task: age + script from its action
    $t = Test-AutomationTask 'Claude-Memory-To-Cursor-Sync' 'memory sync'
    if ($t.Status -eq 'ok') {
        if ($t.Info -and $t.Info.LastRunTime -and $t.Info.LastRunTime.Year -gt 2000) {
            $age = (Get-Date) - $t.Info.LastRunTime
            if ($age.TotalMinutes -gt 45) { Write-Warn "memory sync last ran $(Format-Age $age) ago (expected every 15 min)" }
        }
        foreach ($a in @($t.Task.Actions)) {
            $script = Get-PathFromCommand "$($a.Arguments)" 'ps1|vbs|cmd|bat'
            if (-not $script) { $script = Get-PathFromCommand "$($a.Execute)" 'ps1|vbs|cmd|bat' }
            if (-not $script) { Write-Warn "memory sync action has no script path: $($a.Execute) $($a.Arguments)"; continue }
            if ($a.WorkingDirectory -and -not [IO.Path]::IsPathRooted($script)) { $script = Join-Path (Expand-UserPath $a.WorkingDirectory) $script }
            if (Test-Path -LiteralPath $script) {
                Write-Ok "memory sync script present: $script"
                # A .vbs launcher usually names the real .ps1; check that too (read-only scan).
                if ($script -match '\.vbs$') {
                    $txt = Get-Content -LiteralPath $script -Raw -ErrorAction SilentlyContinue
                    foreach ($m in [regex]::Matches("$txt", '([A-Za-z0-9_.\-\\:/ ]+\.ps1)')) {
                        $p = $m.Groups[1].Value.Trim()
                        if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path (Split-Path -Parent $script) (Split-Path -Leaf $p) }
                        if (Test-Path -LiteralPath $p) { Write-Ok "  launches $p" } else { Write-Warn "  launcher names $p, which does not exist" }
                    }
                }
            } else { Write-Bad "memory sync script missing: $script" }
        }
    }

    # 4. Claude hooks and memory folders (settings.json parsed read-only)
    $claudeDir = Join-Path $HOME '.claude'
    $settingsPath = Join-Path $claudeDir 'settings.json'
    $settings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        try { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
        catch { Write-Bad "can't parse $settingsPath ($($_.Exception.Message))" }
    } else { Write-Warn "no Claude settings at $settingsPath (Claude Code not set up here?)" }

    $mlg = Join-Path $claudeDir 'hooks\memory-link-guard.ps1'
    $hookCmds = @()
    if ($settings -and $settings.hooks) {
        foreach ($ev in $settings.hooks.PSObject.Properties) {
            foreach ($group in @($ev.Value)) {
                foreach ($h in @($group.hooks)) { if ($h.command) { $hookCmds += [pscustomobject]@{ Event = $ev.Name; Command = "$($h.command)" } } }
            }
        }
    }
    $mlgRef = @($hookCmds | Where-Object { $_.Command -match 'memory-link-guard' })
    if (-not (Test-Path -LiteralPath $mlg)) { Write-Warn "memory-link-guard.ps1 missing: $mlg" }
    elseif (-not $mlgRef) { Write-Warn 'memory-link-guard.ps1 exists but no hook in settings.json runs it' }
    else { Write-Ok "memory-link-guard hook: $(($mlgRef | ForEach-Object Event | Sort-Object -Unique) -join ', ') -> $mlg" }
    foreach ($c in @($hookCmds | Where-Object { $_.Command -match 'context-guard' })) {
        $p = Get-PathFromCommand $c.Command 'ps1'
        if ($p -and (Test-Path -LiteralPath $p)) { Write-Ok "context-guard hook ($($c.Event)) -> $p" }
        else { Write-Bad "context-guard hook ($($c.Event)) points at a missing script: $($c.Command)" }
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
    $wm = Join-Path $claudeDir 'working-memory'
    if (Test-Path -LiteralPath $wm) {
        $item = Get-Item -LiteralPath $wm -Force
        $target = @($item.Target) | Select-Object -First 1
        if ($target) {
            if (Test-Path -LiteralPath $target) { Write-Ok "working-memory link -> $target" } else { Write-Bad "working-memory link target missing: $target" }
        } else { Write-Ok "working-memory folder present: $wm" }
    } elseif ((Get-Item -LiteralPath $wm -Force -ErrorAction SilentlyContinue)) {
        Write-Bad "working-memory is a broken link: $wm"
    } else { Write-Ok 'working-memory not present (optional)' }

    # 4b. Claude reads AGENTS.md too ("read both"), and the Projects root has no CLAUDE.md
    if ($settings) {
        $ifv = $null
        foreach ($pn in 'cc-plugin-agents-md@builtin','agents-md@builtin') {
            $pc = $null; if ($settings.pluginConfigs) { $pc = $settings.pluginConfigs.$pn }
            if ($pc -and $pc.options -and $pc.options.instructionFiles) { $ifv = "$($pc.options.instructionFiles)"; break }
        }
        if ($ifv -eq 'claude-md-and-agents-md') { Write-Ok "Claude reads both CLAUDE.md and AGENTS.md ($ifv)" }
        else { Write-Warn "Claude 'read both' setting is off (instructionFiles=$(if($ifv){$ifv}else{'unset'})); AGENTS.md may be skipped" }
    }
    $rootClaude = Join-Path $BridgeProjects 'CLAUDE.md'
    if (Test-Path -LiteralPath $rootClaude) { Write-Warn "root CLAUDE.md found ($rootClaude); merge it into AGENTS.md" }
    else { Write-Ok 'Projects root has no CLAUDE.md (AGENTS.md only)' }

    # 5. Startup apps: entries present AND their Settings > Apps > Startup switch on.
    # Off switches are only reported here; Workstation Status (interactive) then offers to turn them on.
    $script:StartupOff = @()
    $startup = [Environment]::GetFolderPath('Startup')
    $wsh = New-Object -ComObject WScript.Shell
    $cursorLinks = @()
    foreach ($l in @(Get-ChildItem -LiteralPath $startup -Filter *.lnk -ErrorAction SilentlyContinue)) {
        try { $s = $wsh.CreateShortcut($l.FullName); if ($s.TargetPath -match '\\Cursor\.exe$') { $cursorLinks += [pscustomobject]@{ Name = $l.Name; Target = $s.TargetPath } } } catch { }
    }
    if (-not $cursorLinks) { Write-Warn "no Cursor.exe shortcut in Startup folder ($startup)" }
    foreach ($c in $cursorLinks) {
        $tog = Get-StartupToggleInfo 'StartupFolder' $c.Name
        if (-not (Test-Path -LiteralPath $c.Target)) { Write-Bad "Startup $($c.Name) points at a missing file: $($c.Target)" }
        elseif ($tog.State -eq 'off') {
            Write-Warn "Cursor startup switch is OFF (Settings > Apps > Startup)"
            $script:StartupOff += [pscustomobject]@{ Label = 'Cursor'; Type = 'approved'; Kind = 'StartupFolder'; Key = $tog.Key; Name = $c.Name; Pkg = $null }
        }
        else { Write-Ok "Startup $($c.Name) -> $($c.Target) (switch on)" }
    }
    if ($v) {
        $gt = Get-StartupToggleInfo 'Run' 'GrokBot'
        if ($gt.State -eq 'off') {
            Write-Warn 'Grok Bot startup switch is OFF (Settings > Apps > Startup)'
            $script:StartupOff += [pscustomobject]@{ Label = 'Grok Bot'; Type = 'approved'; Kind = 'Run'; Key = $gt.Key; Name = 'GrokBot'; Pkg = $null }
        }
    }
    $claude = Get-PackagedStartupState 'Claude'
    switch ($claude.State) {
        'on'      { Write-Ok "Claude startup switch on ($($claude.TaskId))" }
        'off'     {
            Write-Warn 'Claude startup switch is OFF (Settings > Apps > Startup)'
            $script:StartupOff += [pscustomobject]@{ Label = 'Claude'; Type = 'msix'; Kind = $null; Key = $claude.Key; Name = $null; Pkg = 'Claude' }
        }
        'policy'  { Write-Warn 'Claude startup is turned off by policy (cannot change here)' }
        'nopkg'   { Write-Off 'Claude desktop app (Store package) not installed; startup switch not checked' }
        default   { Write-Warn "Claude startup switch state unknown ($($claude.TaskId))" }
    }

    # 5b. Desktop Commander remote: Startup shortcut + the repo launcher (workstation\desktop-commander-remote; not a scheduled task)
    $dcDir    = Join-Path $BridgeRoot 'desktop-commander-remote'
    $dcScript = Join-Path $dcDir 'start-dc-remote.ps1'
    $dcLnk    = Join-Path ([Environment]::GetFolderPath('Startup')) 'Desktop Commander Remote.lnk'
    $dcManual = Join-Path (Split-Path $BridgeRoot -Parent) 'shortcuts\Desktop Commander Remote Start.lnk'
    if (-not (Test-Path -LiteralPath $dcScript)) {
        Write-Off 'Desktop Commander remote not installed (no start-dc-remote.ps1)'
    } else {
        if (Test-Path -LiteralPath $dcLnk) {
            $tog = Get-StartupToggleInfo 'StartupFolder' 'Desktop Commander Remote.lnk'
            if ($tog.State -eq 'off') {
                Write-Warn 'Desktop Commander remote Startup shortcut is OFF (Settings > Apps > Startup)'
                $script:StartupOff += [pscustomobject]@{ Label = 'Desktop Commander remote'; Type = 'approved'; Kind = 'StartupFolder'; Key = $tog.Key; Name = 'Desktop Commander Remote.lnk'; Pkg = $null }
            } else { Write-Ok "Startup Desktop Commander Remote.lnk -> $dcScript (switch on)" }
        } else {
            Write-Warn "Desktop Commander remote script present but Startup shortcut missing ($dcLnk)"
        }
        if (Test-Path -LiteralPath $dcManual) { Write-Ok "manual Start shortcut: $dcManual" }
        else { Write-Off 'manual Desktop Commander Remote Start.lnk not in workstation\shortcuts' }
    }

    # 6. Retired items must stay gone
    $back = @()
    foreach ($n in @('LatchBridgeLogon', 'CursorWorker')) { if (Get-RunValue $n) { $back += "HKCU Run $n" } }
    $denied = @()
    foreach ($n in @('Cursor-Worker', 'Cursor-Worker-Health', 'ClaudeCode-RemoteControl')) {
        $r = Get-TaskSafe $n
        if ($r.Status -eq 'ok') { $back += "task $n" } elseif ($r.Status -in @('denied', 'error')) { $denied += $n }
    }
    # Old installed toolkit copies under <Projects> (the toolkit runs from the repo clone now)
    foreach ($lf in @($WsLegacyFolders)) {
        $lp = Join-Path $BridgeProjects $lf
        if ($lf -and (Test-Path -LiteralPath $lp)) { Write-Warn "old toolkit copy still there: $lp (scripts now run from $BridgeRoot). Stop its workers, then archive it." }
    }
    if ($back) { Write-Warn "retired items are BACK: $($back -join ', ')" }
    else { Write-Ok 'retired items absent (Run LatchBridgeLogon/CursorWorker; tasks Cursor-Worker, Cursor-Worker-Health, ClaudeCode-RemoteControl)' }
    if ($denied) { Write-Warn "can't read without admin: task $($denied -join ', ')" }
}
