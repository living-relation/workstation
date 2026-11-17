# Shared helpers for the manual Cursor worker. Dot-source only.
# Windows PowerShell 5.1, ASCII only.
# One worker per folder the user picks under <Projects>\active.
# Nothing here registers a task, a Startup item, a Run key, or a hook.
# Projects root: paths.ps1 (install's workstation.json, else the clone location).
# WORKSTATION_PROJECTS_ROOT overrides that for tests only.

$__cwPaths = Join-Path (Split-Path -Parent $PSScriptRoot) 'paths.ps1'
if (-not (Test-Path variable:WsProjectsRoot)) { . $__cwPaths }

$CwMarker = 'workstation=manual'
$CwPortFirst = 8791
$CwPortLast = 8810

function Get-CwProcesses {
    if ($env:WORKSTATION_FAKE_PROCS) {
        if ($env:WORKSTATION_FAKE_PROCS -eq 'none') { return @() }
        try { return @($env:WORKSTATION_FAKE_PROCS | ConvertFrom-Json) } catch { return @() }
    }
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { return @() }
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
}

function Get-ActiveProjectsDir {
    $root = $WsProjectsRoot
    if ($env:WORKSTATION_PROJECTS_ROOT) { $root = $env:WORKSTATION_PROJECTS_ROOT }
    if (-not $root) { return $null }
    $root = $root.Trim().TrimEnd('\', '/')
    return (Join-Path $root 'active')
}

function Get-ActiveFolders {
    $dir = Get-ActiveProjectsDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    $na = $A.Trim().TrimEnd('\', '/').ToLowerInvariant()
    $nb = $B.Trim().TrimEnd('\', '/').ToLowerInvariant()
    return ($na -eq $nb)
}

function Resolve-ActiveFolder([string]$NameOrPath) {
    if (-not $NameOrPath) { return $null }
    $want = $NameOrPath.Trim().Trim('"').TrimEnd('\', '/')
    foreach ($d in @(Get-ActiveFolders)) {
        if ((Test-SamePath $d.FullName $want) -or ($d.Name -ieq $want)) { return $d.FullName }
    }
    return $null
}

function Test-FolderOrigin([string]$Dir) {
    if (-not $Dir) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) { return $false }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    $out = & git -C $Dir remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return [bool]("$out".Trim())
}

function Format-FolderChoice([int]$Number, $Dir, [string]$Suffix) {
    $tag = ''
    if (-not (Test-FolderOrigin $Dir.FullName)) { $tag = ' (no git remote)' }
    return ('  {0}. {1}{2}{3}' -f $Number, $Dir.Name, $tag, $Suffix)
}

function Get-SafeToken([string]$Text, [int]$Max) {
    $t = ''
    if ($Text) { $t = [string]$Text }
    $t = $t -replace '[^A-Za-z0-9._-]', '-'
    $t = $t -replace '-{2,}', '-'
    $t = $t.Trim('-', '.')
    if (-not $t) { $t = 'worker' }
    if ($Max -gt 0 -and $t.Length -gt $Max) { $t = $t.Substring(0, $Max).Trim('-', '.') }
    if (-not $t) { $t = 'worker' }
    return $t
}

function Get-WorkerSlug([string]$Folder) {
    $leaf = Get-SafeToken (Split-Path -Leaf $Folder) 24
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Folder.TrimEnd('\', '/').ToLowerInvariant())
        $hash = ([BitConverter]::ToString($md5.ComputeHash($bytes))).Replace('-', '').Substring(0, 8).ToLowerInvariant()
    } finally { $md5.Dispose() }
    return ($leaf + '-' + $hash)
}

function Get-WorkerDisplayName([string]$Folder) {
    $hostName = ''
    try { $hostName = [System.Net.Dns]::GetHostName() } catch { $hostName = '' }
    if (-not $hostName) { $hostName = [string]$env:COMPUTERNAME }
    if (-not $hostName) { $hostName = 'pc' }
    $leaf = Get-SafeToken (Split-Path -Leaf $Folder) 24
    return (Get-SafeToken ($hostName + '-' + $leaf) 48)
}

function Get-CursorWorkerRoot {
    return (Join-Path $WsStateDir 'cursor-worker')
}

function Get-WorkerDataDir([string]$Folder) {
    return (Join-Path (Join-Path (Get-CursorWorkerRoot) 'instances') (Get-WorkerSlug $Folder))
}

# Flags verified 2026-11-17 against:
#   https://cursor.com/docs/cli/reference/parameters  (agent worker [options] start)
#   https://cursor.com/docs/cloud-agent/self-hosted/my-machines
#   https://cursor.com/docs/cloud-agent/self-hosted/pool  (options before start)
#   https://cursor.com/docs/cli/changelog  (data-dir lock; idle 0 keeps the worker)
function Get-CursorWorkerArgList([string]$Name, [string]$Folder, [string]$DataDir, [string]$MgmtAddr) {
    return @(
        'worker',
        '--name', $Name,
        '--worker-dir', $Folder,
        '--data-dir', $DataDir,
        '--management-addr', $MgmtAddr,
        '--idle-release-timeout', '0',
        '--label', $CwMarker,
        'start'
    )
}

function Format-CmdArg([string]$Text) {
    if ($null -eq $Text) { return '""' }
    if ($Text -match '[\s"]') { return '"' + ($Text -replace '"', '\"') + '"' }
    return $Text
}

function Format-CmdLine([string[]]$CmdArgs) {
    return ((@($CmdArgs) | ForEach-Object { Format-CmdArg $_ }) -join ' ')
}

function Resolve-AgentCli {
    if ($env:WORKSTATION_FAKE_AGENT) {
        if ($env:WORKSTATION_FAKE_AGENT -eq 'missing') { return $null }
        return $env:WORKSTATION_FAKE_AGENT
    }
    foreach ($name in @('agent.cmd', 'agent.exe', 'agent.ps1', 'agent')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
    }
    if ($env:LOCALAPPDATA) {
        $root = Join-Path $env:LOCALAPPDATA 'cursor-agent'
        foreach ($name in @('agent.cmd', 'agent.exe', 'agent.ps1')) {
            $p = Join-Path $root $name
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

function Get-AgentHostPath {
    $ps = $null
    if ($env:SystemRoot) { $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    if ($ps -and (Test-Path -LiteralPath $ps)) { return $ps }
    $self = Get-Process -Id $PID -ErrorAction SilentlyContinue
    if ($self -and $self.Path) { return $self.Path }
    return 'powershell.exe'
}

# Returns FilePath + Arguments for Start-Process. agent.ps1 needs Windows PowerShell.
function Get-AgentStartInfo([string]$Cli, [string[]]$WorkerArgs) {
    $tail = Format-CmdLine $WorkerArgs
    $ext = ''
    try { $ext = [IO.Path]::GetExtension($Cli).ToLowerInvariant() } catch { $ext = '' }
    if ($ext -eq '.ps1') {
        $arg = '-NoProfile -ExecutionPolicy Bypass -File ' + (Format-CmdArg $Cli) + ' ' + $tail
        return @{ FilePath = (Get-AgentHostPath); Arguments = $arg; Command = $tail }
    }
    return @{ FilePath = $Cli; Arguments = $tail; Command = $tail }
}

function Test-TcpPortFree([int]$Port) {
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $Port
        $listener.Start()
        return $true
    } catch { return $false }
    finally { if ($listener) { try { $listener.Stop() } catch { } } }
}

function Get-WorkerMgmtPort([int[]]$Used) {
    $usedSet = @{}
    foreach ($u in @($Used)) { if ($u) { $usedSet["$u"] = $true } }
    for ($p = $CwPortFirst; $p -le $CwPortLast; $p++) {
        if ($usedSet.ContainsKey("$p")) { continue }
        if (Test-TcpPortFree $p) { return $p }
    }
    return 0
}

function Get-FlagValue([string]$Cmd, [string]$Flag) {
    if (-not $Cmd) { return $null }
    $pat = '(?i)(?:^|\s)' + [regex]::Escape($Flag) + '\s+(?:"([^"]*)"|(\S+))'
    $m = [regex]::Match($Cmd, $pat)
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Success) { return $m.Groups[1].Value }
    return $m.Groups[2].Value
}

function Test-OurWorkerCommand([string]$Cmd) {
    if (-not $Cmd) { return $false }
    if ($Cmd -match '(?i)start-cursor-worker\.ps1|stop-cursor-worker\.ps1|cursor-worker-lib\.ps1') { return $false }
    $marked = ($Cmd -match [regex]::Escape($CwMarker)) -or ($Cmd -match '(?i)cursor-worker[\\/]+instances[\\/]')
    if (-not $marked) { return $false }
    return [bool]($Cmd -match '(?i)(^|[\s''"=])worker([\s''"]|$)')
}

function Test-WorkerHostName([string]$Name) {
    return [bool]("$Name" -match '^(powershell|pwsh|cmd|agent|node|cursor-agent)(\.exe)?$')
}

function Get-WorkerLedger {
    $inst = Join-Path (Get-CursorWorkerRoot) 'instances'
    if (-not (Test-Path -LiteralPath $inst -PathType Container)) { return @() }
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $inst -Recurse -Filter worker.json -File -ErrorAction SilentlyContinue)) {
        try {
            $item = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
            $out += $item
        } catch { }
    }
    return @($out)
}

function New-WorkerRow([int]$ProcId, [int]$ParentId, [string]$ProcName, [string]$Cmd, [string]$Folder, [string]$DisplayName, [string]$DataDir, [string]$Mgmt) {
    return [pscustomobject]@{
        Pid = $ProcId; ParentProcessId = $ParentId; Name = $ProcName; CommandLine = $Cmd
        Folder = $Folder; DisplayName = $DisplayName; DataDir = $DataDir; Mgmt = $Mgmt
    }
}

function Get-CursorWorkerRows {
    param($Procs)
    if ($null -eq $Procs) { $Procs = @(Get-CwProcesses) }
    $cands = @()
    $seen = @{}
    foreach ($p in @($Procs)) {
        $cmd = "$($p.CommandLine)"
        if (-not (Test-OurWorkerCommand $cmd)) { continue }
        $id = 0; $pp = 0
        try { $id = [int]$p.ProcessId } catch { continue }
        try { $pp = [int]$p.ParentProcessId } catch { $pp = 0 }
        $seen["$id"] = $true
        $cands += New-WorkerRow $id $pp "$($p.Name)" $cmd (Get-FlagValue $cmd '--worker-dir') (Get-FlagValue $cmd '--name') (Get-FlagValue $cmd '--data-dir') (Get-FlagValue $cmd '--management-addr')
    }
    foreach ($rec in @(Get-WorkerLedger)) {
        $id = 0
        try { $id = [int]$rec.pid } catch { continue }
        if ($id -le 0 -or $seen.ContainsKey("$id")) { continue }
        $proc = @($Procs | Where-Object { [int]$_.ProcessId -eq $id }) | Select-Object -First 1
        if (-not $proc) { continue }
        $cmd = "$($proc.CommandLine)"
        if ($cmd -and -not (Test-OurWorkerCommand $cmd)) { continue }
        if (-not $cmd -and -not (Test-WorkerHostName "$($proc.Name)")) { continue }
        $pp = 0
        try { $pp = [int]$proc.ParentProcessId } catch { $pp = 0 }
        $seen["$id"] = $true
        $cands += New-WorkerRow $id $pp "$($proc.Name)" $cmd "$($rec.folder)" "$($rec.name)" "$($rec.dataDir)" "$($rec.mgmt)"
    }
    $ids = @{}
    foreach ($c in @($cands)) { $ids["$($c.Pid)"] = $true }
    $roots = @()
    foreach ($c in @($cands)) {
        if ($c.ParentProcessId -gt 0 -and $ids.ContainsKey("$($c.ParentProcessId)")) { continue }
        $roots += $c
    }
    return @($roots)
}

function Get-CursorWorkerHealthLines {
    $lines = @()
    $rows = @(Get-CursorWorkerRows)
    if ($rows.Count -eq 0) {
        $lines += [pscustomobject]@{ Level = 'OK'; Text = 'Cursor worker is not running (manual Start only)' }
    } else {
        $bits = @($rows | ForEach-Object {
            $nm = $_.DisplayName; if (-not $nm) { $nm = 'worker' }
            $folder = $_.Folder; if (-not $folder) { $folder = 'folder not recorded' }
            '{0} pid {1} ({2})' -f $nm, $_.Pid, $folder
        })
        $lines += [pscustomobject]@{ Level = 'OK'; Text = ('Cursor worker: {0} running (manual): {1}' -f $rows.Count, ($bits -join '; ')) }
    }
    $auto = @(Get-CursorWorkerAutostartHits)
    if ($auto.Count) {
        $lines += [pscustomobject]@{ Level = 'WARN'; Text = ('Cursor worker starts on its own: ' + ($auto -join ', ')) }
    } else {
        $lines += [pscustomobject]@{ Level = 'OK'; Text = 'Cursor worker does not start at sign-in, reboot, or app launch' }
    }
    return @($lines)
}

function Test-CwAutostartText([string]$Text) {
    if (-not $Text) { return $false }
    return [bool]($Text -match '(?i)start-cursor-worker\.ps1|cursor-worker[\\/]run-worker\.ps1|(^|[\\/"\s''])agent(\.ps1|\.cmd|\.exe)?\s+worker\b')
}

function Get-CursorWorkerAutostartHits {
    if ($env:WORKSTATION_FAKE_AUTOSTART) {
        if ($env:WORKSTATION_FAKE_AUTOSTART -eq 'none') { return @() }
        try { return @($env:WORKSTATION_FAKE_AUTOSTART | ConvertFrom-Json) } catch { return @() }
    }
    $hits = New-Object System.Collections.Generic.List[string]
    $startupDirs = @()
    try { $startupDirs += [Environment]::GetFolderPath('Startup') } catch { }
    try { $startupDirs += [Environment]::GetFolderPath('CommonStartup') } catch { }
    foreach ($dir in @($startupDirs | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $wsh = $null
        try { $wsh = New-Object -ComObject WScript.Shell } catch { $wsh = $null }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)) {
            $cmd = ''
            if ($f.Extension -eq '.lnk' -and $wsh) {
                try { $s = $wsh.CreateShortcut($f.FullName); $cmd = "$($s.TargetPath) $($s.Arguments)" } catch { $cmd = '' }
            } elseif (@('.vbs', '.cmd', '.bat', '.ps1') -contains $f.Extension.ToLower()) {
                try { $cmd = [IO.File]::ReadAllText($f.FullName) } catch { $cmd = '' }
            }
            if ((Test-CwAutostartText $cmd) -or ($f.BaseName -eq 'CursorWorker')) { [void]$hits.Add($f.FullName) }
        }
    }
    foreach ($run in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
        try {
            if (-not (Test-Path -LiteralPath $run)) { continue }
            $props = Get-ItemProperty -LiteralPath $run -ErrorAction Stop
        } catch { continue }
        foreach ($p in @($props.PSObject.Properties)) {
            if ($p.Name -like 'PS*') { continue }
            $v = [string]$p.Value
            if ($p.Name -eq 'CursorWorker' -or (Test-CwAutostartText $v)) { [void]$hits.Add("Run:$($p.Name)") }
        }
    }
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })
            foreach ($t in @($tasks)) {
                $name = [string]$t.TaskName
                $act = ''
                try { $act = (@($t.Actions) | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join ' ; ' } catch { $act = '' }
                if ($name -eq 'Cursor-Worker' -or $name -eq 'Cursor-Worker-Health' -or (Test-CwAutostartText $act)) {
                    [void]$hits.Add("Task:$name")
                }
            }
        } catch { }
    }
    $homes = @()
    if ($env:USERPROFILE) { $homes += $env:USERPROFILE }
    if ($HOME -and (@($homes | Where-Object { $_ -eq $HOME }).Count -eq 0)) { $homes += $HOME }
    foreach ($h in @($homes)) {
        foreach ($pair in @(@('.cursor', 'hooks.json'), @('.claude', 'settings.json'))) {
            $p = Join-Path (Join-Path $h $pair[0]) $pair[1]
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            $text = ''
            try { $text = [IO.File]::ReadAllText($p) } catch { $text = '' }
            if (Test-CwAutostartText $text) { [void]$hits.Add($p) }
        }
    }
    return @($hits | Select-Object -Unique)
}
