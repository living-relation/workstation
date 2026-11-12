#Requires -Version 5.1
# Helpers for the per-project Claude remote-control shortcuts.
# Windows PowerShell 5.1. Keep this file ASCII-only.
# Dot-sourcing does not run claude. Tests call Invoke-RcRemoteLaunch with a fake invoker.

# A shortcut folder is a real git repo directly inside active\: its .git is a directory.
# A worktree's .git is a file that points at the main repo, so it gets no shortcut.
# A plain folder, and a name that starts with a dot (.cursor), are not shortcut folders.
function Test-RcGitRepoDirectory([string]$Path) {
    if (-not $Path) { return $false }
    $git = Join-Path $Path '.git'
    return [bool](Test-Path -LiteralPath $git -PathType Container)
}

function Get-RcProjectFolders([string]$ActiveDir) {
    if (-not $ActiveDir -or -not (Test-Path -LiteralPath $ActiveDir -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $ActiveDir -Force -Directory | Where-Object {
        $_.Name -and $_.Name -notlike '.*' -and (Test-RcGitRepoDirectory $_.FullName)
    } | Sort-Object Name)
}

function Get-RcSafeFilePart([string]$FolderName) {
    $part = ($FolderName -replace '[<>:"/\\|?*]', '-').Trim().Trim('.')
    if (-not $part) { $part = 'project' }
    return $part
}

# One token, stable across launches. --bg ignores --session-id and keeps --name.
function Get-RcSessionName([string]$FolderName) {
    $slug = ($FolderName -replace '[^\w.-]', '-').Trim('-')
    if (-not $slug) { $slug = 'project' }
    return "rc-$slug"
}

function Get-RcOpenLinkName([string]$FolderName) { "Start Claude remote - $(Get-RcSafeFilePart $FolderName).lnk" }
function Get-RcCloseLinkName([string]$FolderName) { "Stop Claude remote - $(Get-RcSafeFilePart $FolderName).lnk" }
# Link names this generator writes now, and the old names it wrote before 2026-10-31 ("RC <folder>", "Close RC <folder>").
$script:RcLinkPattern = '^(Start|Stop) Claude remote - .+\.lnk$'
$script:RcOldLinkPattern = '^(Close )?RC .+\.lnk$'

function Normalize-RcPath([string]$Path) {
    if (-not $Path) { return '' }
    $text = "$Path".Trim()
    try { return ([IO.Path]::GetFullPath($text)).TrimEnd('\', '/') } catch { return $text.TrimEnd('\', '/') }
}

# Defaults from this script's place in the clone, plus workstation.json when it exists.
# Pass ConfigPath '' to skip the config file (tests).
function Get-RcDefaults([string]$ScriptRoot, [string]$ConfigPath) {
    $toolkit = Split-Path -Parent $ScriptRoot
    $package = Split-Path -Parent $toolkit
    if ($null -eq $ConfigPath) { $ConfigPath = Join-Path $env:LOCALAPPDATA 'Workstation\workstation.json' }
    $projects = $null
    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $root = [string](Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).projectsRoot
            if ($root -and (Test-Path -LiteralPath $root)) { $projects = $root.TrimEnd('\') }
        } catch { }
    }
    if (-not $projects) {
        $up = Split-Path -Parent $package
        if ((Split-Path -Leaf $up) -ieq 'active') { $projects = Split-Path -Parent $up } else { $projects = $up }
        $projects = "$projects".TrimEnd('\')
    }
    return @{
        ActiveDir = [IO.Path]::Combine($projects, 'active')
        LinkDir   = [IO.Path]::Combine($package, 'shortcuts', 'rc')
    }
}

# claude agents --json is an array, or wrapped as { agents: [...] } / { sessions: [...] }.
# Extra text around the JSON is ignored. Windows PowerShell 5.1 returns a JSON array as one
# Object[], and @() around that nests it, so this walks the array in a foreach.
function ConvertFrom-RcAgentsJson([string]$Text) {
    $text = "$Text"
    if (-not $text.Trim()) { return @() }
    $startArr = $text.IndexOf('[')
    $startObj = $text.IndexOf('{')
    if ($startArr -ge 0 -and ($startObj -lt 0 -or $startArr -lt $startObj)) { $json = $text.Substring($startArr) }
    elseif ($startObj -ge 0) { $json = $text.Substring($startObj) }
    else { throw 'no JSON array or object in claude agents output' }
    $end = [Math]::Max($json.LastIndexOf(']'), $json.LastIndexOf('}'))
    if ($end -ge 0) { $json = $json.Substring(0, $end + 1) }
    $parsed = $json | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $parsed) { return @() }
    $names = @($parsed.PSObject.Properties.Name)
    $items = @()
    if ($parsed -is [System.Array]) {
        foreach ($item in $parsed) { if ($null -ne $item) { $items += $item } }
    } elseif (($names -contains 'agents') -and $null -ne $parsed.agents -and ($names -notcontains 'cwd')) {
        foreach ($item in $parsed.agents) { if ($null -ne $item) { $items += $item } }
    } elseif (($names -contains 'sessions') -and $null -ne $parsed.sessions -and ($names -notcontains 'cwd')) {
        foreach ($item in $parsed.sessions) { if ($null -ne $item) { $items += $item } }
    } else { $items += $parsed }
    return @($items)
}

# Sessions for this folder and this shortcut's name. Stopped ones are already gone.
function Select-RcSessions($Sessions, [string]$RepoPath, [string]$SessionName) {
    $want = Normalize-RcPath $RepoPath
    if (-not $want -or -not $SessionName) { return @() }
    @($Sessions | Where-Object {
        $_ -and
        ((Normalize-RcPath "$($_.cwd)") -ieq $want) -and
        ("$($_.name)" -ieq $SessionName) -and
        ("$($_.state)" -notin @('stopped', 'done', 'failed'))
    })
}

# The short id `claude stop` takes. agents JSON uses `id`; fall back to sessionId.
function Get-RcStopId($Session) {
    if ($Session -and "$($Session.id)") { return "$($Session.id)".Trim() }
    if ($Session -and "$($Session.sessionId)") { return "$($Session.sessionId)".Trim() }
    return ''
}

# "backgrounded <sep> b4e02f32 <sep> rc-name" from claude --bg. The separator is not a stable character.
function Get-RcBackgroundId([string]$Text) {
    if ("$Text" -match 'backgrounded\s+\S+\s+([0-9a-fA-F]{6,})') { return $Matches[1] }
    return ''
}

# True only for this session's process: --remote-control and --name as its own argument.
# rc-foo does not match rc-foobar. The shared `claude.exe daemon run` does not match.
function Test-RcProcessCommandLine([string]$Cmd, [string]$SessionName) {
    if (-not $Cmd -or -not $SessionName) { return $false }
    if ($Cmd -notmatch '(^|\s)--remote-control(=|\s|$)') { return $false }
    $esc = [regex]::Escape($SessionName)
    return [bool]($Cmd -match "(^|\s)--name(?:=|\s+)$esc(?=\s|$)")
}

function Select-RcProcs($Procs, [string]$SessionName) {
    @($Procs | Where-Object {
        $_ -and $_.Name -in @('claude.exe', 'node.exe') -and (Test-RcProcessCommandLine "$($_.CommandLine)" $SessionName)
    })
}

# Of the matched processes, the ones whose parent is not also matched. taskkill /T on these ends the tree.
function Get-RcKillRoots($Procs) {
    $ids = @($Procs | ForEach-Object { [int]$_.ProcessId })
    @($Procs | Where-Object { $ids -notcontains [int]$_.ParentProcessId })
}

# Write one start link and one stop link per git repo. Remove our links whose repo is gone
# (including a plain folder or a worktree that used to get a pair), and the old-named
# "RC <folder>" / "Close RC <folder>" links this generator wrote before the rename.
# Leaves any other file in LinkDir alone. Returns a hashtable: Ok, Projects, Created, Updated, Removed, Errors.
# Pass Shell only from tests (a fake). The real generator uses WScript.Shell.
function Write-RcShortcuts {
    param(
        [Parameter(Mandatory = $true)][string]$ActiveDir,
        [Parameter(Mandatory = $true)][string]$LinkDir,
        [Parameter(Mandatory = $true)][string]$OpenScript,
        [Parameter(Mandatory = $true)][string]$CloseScript,
        [object]$Shell = $null
    )
    $errors = @()
    $result = @{ Ok = $true; Projects = 0; Created = 0; Updated = 0; Removed = 0; Errors = @() }
    if (-not (Test-Path -LiteralPath $OpenScript -PathType Leaf)) { $errors += "missing $OpenScript" }
    if (-not (Test-Path -LiteralPath $CloseScript -PathType Leaf)) { $errors += "missing $CloseScript" }
    if (-not (Test-Path -LiteralPath $ActiveDir -PathType Container)) { $errors += "project folder not found: $ActiveDir" }
    if ($errors.Count) { $result.Ok = $false; $result.Errors = @($errors); return $result }

    if (-not (Test-Path -LiteralPath $LinkDir)) { New-Item -ItemType Directory -Path $LinkDir -Force | Out-Null }
    $winRoot = $env:SystemRoot
    if (-not $winRoot) { $winRoot = 'C:\Windows' }
    $psExe = Join-Path $winRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shell32 = Join-Path $winRoot 'System32\shell32.dll'
    $wsh = $Shell
    if (-not $wsh) {
        try { $wsh = New-Object -ComObject WScript.Shell } catch {
            $errors += "could not create shortcuts: $($_.Exception.Message)"
            $result.Ok = $false
            $result.Errors = @($errors)
            return $result
        }
    }
    $projects = @(Get-RcProjectFolders $ActiveDir)
    $result.Projects = $projects.Count
    $expected = @{}
    foreach ($p in $projects) {
        $pairs = @(
            @{ Link = (Get-RcOpenLinkName $p.Name); Script = $OpenScript; Icon = 137; Desc = "Start Claude remote control in $($p.Name)" },
            @{ Link = (Get-RcCloseLinkName $p.Name); Script = $CloseScript; Icon = 131; Desc = "Stop Claude remote control in $($p.Name)" }
        )
        foreach ($pair in $pairs) {
            $lnkPath = Join-Path $LinkDir $pair.Link
            $expected[$pair.Link.ToLower()] = $true
            $existed = Test-Path -LiteralPath $lnkPath
            try {
                $s = $wsh.CreateShortcut($lnkPath)
                $s.TargetPath = $psExe
                $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($pair.Script)`" -Repo `"$($p.FullName)`""
                $s.WorkingDirectory = $p.FullName
                $s.WindowStyle = 1
                $s.Description = $pair.Desc
                $s.IconLocation = "$shell32,$($pair.Icon)"
                $s.Save()
                $check = $wsh.CreateShortcut($lnkPath)
                $leaf = [IO.Path]::GetFileName($pair.Script)
                $ok = ($check.TargetPath -ieq $psExe) -and ($check.Arguments -like "*$leaf*") -and ($check.Arguments -like "*$($p.FullName)*") -and ($check.WorkingDirectory -ieq $p.FullName)
                if (-not $ok) { $errors += "read-back failed for $($pair.Link)"; continue }
                if ($existed) { $result.Updated++ } else { $result.Created++ }
            } catch { $errors += "$($pair.Link): $($_.Exception.Message)" }
        }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $LinkDir -Filter *.lnk -File -ErrorAction SilentlyContinue)) {
        if ($expected.ContainsKey($f.Name.ToLower())) { continue }
        if ($f.Name -notmatch $script:RcLinkPattern -and $f.Name -notmatch $script:RcOldLinkPattern) { continue }
        Remove-Item -LiteralPath $f.FullName -Force
        $result.Removed++
    }
    if ($errors.Count) { $result.Ok = $false }
    $result.Errors = @($errors)
    return $result
}
# --name / --session-id value on a claude command line. rc-foo does not match inside rc-foobar.
function Get-RcCommandValue([string]$Cmd, [string]$Flag) {
    if (-not $Cmd -or -not $Flag) { return '' }
    $esc = [regex]::Escape($Flag)
    if ($Cmd -match "(^|\s)$esc(?:=|\s+)(\S+)") { return $Matches[2] }
    return ''
}

# Folder name for a remote-control session. A cwd under active\<folder> wins.
# The Phone access session (claude-root-start.ps1) lives in the projects root.
function Get-RcRepoLabel([string]$Cwd, [string]$SessionName, [string]$ProjectsRoot) {
    $path = Normalize-RcPath $Cwd
    $root = Normalize-RcPath $ProjectsRoot
    $active = ''
    if ($root) { $active = Normalize-RcPath ([IO.Path]::Combine($root, 'active')) }
    if ($path -and $active) {
        $prefix = $active + '\'
        if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $leaf = ($path.Substring($prefix.Length) -split '\\', 2)[0]
            if ($leaf) { return $leaf }
        }
    }
    if ($path -and $root -and ($path -ieq $root)) { return 'projects root' }
    if ($SessionName -match '^rc-(.+)$') { return $Matches[1] }
    if ($SessionName -eq 'workstation-remote-control') { return 'projects root' }
    if ($path) {
        $leaf = Split-Path $path -Leaf
        if ($leaf) { return $leaf }
    }
    if ($SessionName) { return $SessionName }
    return 'unknown'
}

# One row per remote-control session: Label is the repo, Detail is name, id, and state.
# The PTY host is not its own row. A process is skipped when its session was already listed.
function Get-RcStatusRows($Sessions, $Procs, [string]$ProjectsRoot) {
    $rows = @()
    $seenId = @{}
    $seenName = @{}
    foreach ($s in @($Sessions)) {
        if (-not $s) { continue }
        $name = "$($s.name)".Trim()
        $full = "$($s.sessionId)".Trim()
        $id = Get-RcStopId $s
        if ($full -and $seenId.ContainsKey($full)) { continue }
        if ($id -and $seenId.ContainsKey($id)) { continue }
        if ($name -and $seenName.ContainsKey($name.ToLower())) { continue }
        if ($full) { $seenId[$full] = $true }
        if ($id) { $seenId[$id] = $true }
        if ($name) { $seenName[$name.ToLower()] = $true }
        $bits = @()
        if ($name) { $bits += $name }
        if ($id) { $bits += "session $id" }
        $state = "$($s.state)".Trim()
        if ($state) { $bits += $state }
        $rows += [pscustomobject]@{ Label = (Get-RcRepoLabel "$($s.cwd)" $name $ProjectsRoot); Detail = ($bits -join ', ') }
    }
    foreach ($p in @($Procs)) {
        $cmd = "$($p.CommandLine)"
        if ($cmd -match '--bg-pty-host') { continue }
        if ($cmd -notmatch '(^|\s)--remote-control(=|\s|$)') { continue }
        $name = Get-RcCommandValue $cmd '--name'
        $full = Get-RcCommandValue $cmd '--session-id'
        $short = ''
        if ($full -and $full.Length -ge 8) { $short = $full.Substring(0, 8) }
        if ($full -and $seenId.ContainsKey($full)) { continue }
        if ($short -and $seenId.ContainsKey($short)) { continue }
        if ($name -and $seenName.ContainsKey($name.ToLower())) { continue }
        if ($full) { $seenId[$full] = $true }
        if ($short) { $seenId[$short] = $true }
        if ($name) { $seenName[$name.ToLower()] = $true }
        $bits = @()
        if ($name) { $bits += $name }
        if ($short) { $bits += "session $short" }
        $detail = if ($bits) { $bits -join ', ' } else { "pid $($p.ProcessId)" }
        $rows += [pscustomobject]@{ Label = (Get-RcRepoLabel '' $name $ProjectsRoot); Detail = $detail }
    }
    return @($rows | Sort-Object Label, Detail)
}

# The projects-root session Phone access (claude-root-start.ps1) owns. Per-project sessions are named rc-<folder>.
function Select-ProjectsRootRcSessions($Sessions, [string]$SavedId) {
    $name = 'workstation-remote-control'
    @($Sessions | Where-Object {
        $_ -and (("$($_.name)" -eq $name) -or ($SavedId -and "$($_.sessionId)" -eq $SavedId))
    })
}

# "2.1.301 (Claude Code)" -> 2.1.301. Empty when the text has no version.
function Get-RcCliVersion([string]$Text) {
    if ("$Text" -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    return ''
}

# Length and write time of the CLI binary. Changes when an update replaces claude.exe.
function Get-RcBinaryStamp([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        return ('{0}:{1}' -f $item.Length, $item.LastWriteTimeUtc.Ticks)
    } catch { return '' }
}

# `claude daemon status` text. A worker line "N from a different CLI version" is not the
# supervisor itself being old; that case is the version field compared with the CLI.
# Windows can print a pid while control.sock is unreachable: that supervisor is not usable.
function ConvertFrom-RcDaemonStatus([string]$Text, $ExitCode = 0) {
    $text = "$Text"
    $daemonPid = ''
    $version = ''
    if ($text -match '(?im)^\s*pid:\s*(\d+)') { $daemonPid = $Matches[1] }
    if ($text -match '(?im)^\s*version:\s*(\d+\.\d+\.\d+)') { $version = $Matches[1] }
    $control = ''
    if ($text -match '(?i)control\.sock:\s*(\S+)') { $control = $Matches[1].ToLower() }
    $skew = $false
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '(?i)from a different') { continue }
        if ($line -match '(?i)different version') { $skew = $true }
    }
    $notRunning = [bool]($text -match '(?i)not running')
    $running = (-not $notRunning) -and ($daemonPid -ne '') -and ($version -ne '') -and ($control -ne 'unreachable')
    return @{
        Running  = [bool]$running
        Pid      = $daemonPid
        Version  = $version
        Control  = $control
        Skew     = [bool]$skew
        ExitCode = $ExitCode
    }
}

# Ready to host a new session: supervisor is up, its pipe answers, and its version matches
# the CLI we are about to launch (so it will not self-restart for an upgrade under the session).
function Test-RcDaemonReady($Status, [string]$CliVersion) {
    if (-not $Status -or -not $Status.Running -or $Status.Skew) { return $false }
    if ($CliVersion -and $Status.Version -and ($Status.Version -ne $CliVersion)) { return $false }
    return $true
}

# One CLI call. InvokeCli receives a single string[] (update, --version, daemon status,
# daemon run, agents --json, or --bg --remote-control --name <name>).
# Returns @{ ExitCode; Text }. Tests pass a fake; nothing here starts claude itself.
function Test-RcCliResult($Item) {
    if ($null -eq $Item) { return $false }
    $dict = $Item
    try {
        if ($Item.PSObject -and ($Item.PSObject.BaseObject -is [System.Collections.IDictionary])) { $dict = $Item.PSObject.BaseObject }
    } catch { }
    if ($dict -is [System.Collections.IDictionary]) {
        if ($dict.Contains('ExitCode')) { return $true }
    }
    try { return [bool]($Item.PSObject.Properties['ExitCode']) } catch { return $false }
}

function Invoke-RcCliCall {
    param([scriptblock]$InvokeCli, [string[]]$ArgumentList)
    if (-not $InvokeCli) { return @{ ExitCode = 1; Text = 'no claude invoker' } }
    # .Invoke keeps the string[] as one argument. The call operator wraps it, so a
    # fake sees "System.String[]" instead of the words. Windows PowerShell 5.1 may
    # wrap the hashtable result; Test-RcCliResult unwraps that.
    try { $raw = @($InvokeCli.Invoke(@(, [string[]]$ArgumentList))) } catch { return @{ ExitCode = 1; Text = "$($_.Exception.Message)" } }
    $hit = $null
    foreach ($item in @($raw)) { if (Test-RcCliResult $item) { $hit = $item } }
    if ($null -eq $hit) { return @{ ExitCode = 1; Text = '' } }
    $code = 1
    if ($null -ne $hit.ExitCode) { $code = [int]$hit.ExitCode }
    $text = ''
    if ($null -ne $hit.Text) { $text = [string]$hit.Text }
    return @{ ExitCode = $code; Text = $text }
}

# The real invoker used by the shortcut scripts. `daemon run` is not waited on (it stays up).
# `update` may download a version, so it gets a longer timeout. Tests never call this.
function New-RcClaudeInvoker {
    param(
        [Parameter(Mandatory = $true)][string]$ClaudeExe,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )
    $state = @{ N = 0 }
    $block = {
        param($ArgumentList)
        $cliArgs = @($ArgumentList)
        $state.N++
        if ($cliArgs.Count -ge 2 -and $cliArgs[0] -eq 'daemon' -and $cliArgs[1] -eq 'run') {
            try {
                Start-Process -FilePath $ClaudeExe -ArgumentList $cliArgs -WorkingDirectory $RepoPath -WindowStyle Hidden -ErrorAction Stop | Out-Null
                return @{ ExitCode = 0; Text = '' }
            } catch { return @{ ExitCode = 1; Text = "$($_.Exception.Message)" } }
        }
        $outFile = Join-Path $env:TEMP ("rc-cli-{0}-{1}.out.txt" -f $PID, $state.N)
        $errFile = Join-Path $env:TEMP ("rc-cli-{0}-{1}.err.txt" -f $PID, $state.N)
        $timeout = 20000
        if ($cliArgs.Count -ge 1 -and $cliArgs[0] -eq 'update') { $timeout = 90000 }
        if ($cliArgs -contains '--bg') { $timeout = 30000 }
        try {
            $proc = Start-Process -FilePath $ClaudeExe -ArgumentList $cliArgs -WorkingDirectory $RepoPath `
                -WindowStyle Hidden -PassThru -ErrorAction Stop `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        } catch { return @{ ExitCode = 1; Text = "$($_.Exception.Message)" } }
        $exited = $false
        try { $exited = $proc.WaitForExit($timeout) } catch { $exited = $false }
        $outText = ''
        $errText = ''
        try { if (Test-Path -LiteralPath $outFile) { $outText = [IO.File]::ReadAllText($outFile) } } catch { }
        try { if (Test-Path -LiteralPath $errFile) { $errText = [IO.File]::ReadAllText($errFile) } } catch { }
        $text = ($outText + "`n" + $errText).Trim()
        if (-not $exited) {
            if ($cliArgs -contains '--bg') { return @{ ExitCode = 0; Text = $text } }
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
            return @{ ExitCode = 124; Text = $text }
        }
        $code = $proc.ExitCode
        if ($null -eq $code) { $code = 0 }
        return @{ ExitCode = [int]$code; Text = $text }
    }
    return $block.GetNewClosure()
}

# Start one remote-control session and report success only when `claude agents --json`
# still lists it. A cold `claude --bg` both starts the background service and prints
# "backgrounded" before Claude's startup update replaces claude.exe. The service then
# logs "self-restarting for upgrade" and "post-takeover prewarm burst ... refused", and
# the session is gone. The second click works because that service is already on the new
# binary. So: apply any pending update first, start the service if it is down, and do not
# create the session until the service is up on this CLI version with a stable pid.
# If the session is missing once that is true, start it one more time.
# InvokeCli is the only way out to claude (see Invoke-RcCliCall). Sleep and GetBinaryStamp
# are replaceable so tests do not wait or touch a real binary.
function Invoke-RcRemoteLaunch {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$InvokeCli,
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$SessionName,
        [scriptblock]$GetBinaryStamp = { '' },
        [scriptblock]$Sleep = { param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds },
        [int]$PollMilliseconds = 1000,
        [int]$MaxPolls = 75,
        [int]$MaxStarts = 2,
        [int]$ReadyMisses = 3,
        [int]$DownPollsBeforeStart = 15
    )
    $logs = New-Object System.Collections.Generic.List[string]
    $bgText = New-Object System.Collections.Generic.List[string]
    function Note([string]$Message) { if ($Message) { $logs.Add($Message) } }
    function Stamp { return "$(& $GetBinaryStamp)" }
    function Read-Status { return (ConvertFrom-RcDaemonStatus (Invoke-RcCliCall $InvokeCli @('daemon', 'status')).Text) }
    function Read-Live {
        $r = Invoke-RcCliCall $InvokeCli @('agents', '--json')
        if ($r.ExitCode -ne 0) { return @{ Ok = $false; Sessions = @() } }
        try { $parsed = @(ConvertFrom-RcAgentsJson $r.Text) } catch { return @{ Ok = $false; Sessions = @() } }
        return @{ Ok = $true; Sessions = @(Select-RcSessions $parsed $RepoPath $SessionName) }
    }
    # Hashtable so Start-Once and the poll loop share one counter (a nested function
    # assigning $starts would not update the caller's copy).
    $run = @{ Starts = 0; Misses = 0; Confirm = 0; ConfirmPid = '' }
    function Start-Once {
        $run.Starts++
        $bg = Invoke-RcCliCall $InvokeCli @('--bg', '--remote-control', '--name', $SessionName)
        if ($bg.Text) { $bgText.Add($bg.Text) }
        if ($bg.ExitCode -ne 0) { Note "claude --bg exited $($bg.ExitCode)" }
        $run.Misses = 0
        $run.Confirm = 0
        $run.ConfirmPid = ''
    }
    function Finish([bool]$Ok, [string]$Detail, $Sessions) {
        $sid = ''
        $full = ''
        $first = @($Sessions) | Select-Object -First 1
        if ($first) {
            $sid = Get-RcStopId $first
            $full = "$($first.sessionId)".Trim()
        }
        if (-not $sid) { $sid = Get-RcBackgroundId (($bgText | Select-Object -Last 1)) }
        return @{
            Ok        = $Ok
            Starts    = $run.Starts
            SessionId = $sid
            FullId    = $full
            Detail    = $Detail
            Output    = ($bgText -join "`n")
            Log       = @($logs)
        }
    }

    $verText = Invoke-RcCliCall $InvokeCli @('--version')
    $cliVersion = Get-RcCliVersion $verText.Text
    $baseStamp = Stamp
    $first = Read-Status
    $daemon = $first
    $settled = $false
    if (Test-RcDaemonReady $first $cliVersion) {
        & $Sleep $PollMilliseconds
        $secondStamp = Stamp
        $second = Read-Status
        if ((Test-RcDaemonReady $second $cliVersion) -and ($second.Pid -eq $first.Pid) -and ($secondStamp -eq $baseStamp)) {
            $settled = $true
            $daemon = $second
        }
    }
    $settleGaveUp = $false
    if (-not $settled) {
        Note 'Checking for a Claude update before starting the session'
        $upd = Invoke-RcCliCall $InvokeCli @('update')
        $updLine = ''
        foreach ($line in ("$($upd.Text)" -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -and $trimmed.Length -le 180) { $updLine = $trimmed }
        }
        if ($upd.ExitCode -ne 0) { Note "Claude update did not finish (exit $($upd.ExitCode)); continuing" }
        elseif ($updLine) { Note $updLine }
        else { Note 'Claude update check finished' }
        $newVer = Get-RcCliVersion (Invoke-RcCliCall $InvokeCli @('--version')).Text
        if ($newVer) { $cliVersion = $newVer }
        $baseStamp = Stamp
        $polls = 0
        $seenPid = ''
        $didWarm = $false
        $downPolls = 0
        $loggedWait = $false
        while ($polls -lt $MaxPolls) {
            $polls++
            $stampNow = Stamp
            if ($baseStamp -and $stampNow -and ($stampNow -ne $baseStamp)) {
                Note 'Claude binary changed; waiting for the background service'
                $baseStamp = $stampNow
                $seenPid = ''
                $downPolls = 0
                & $Sleep $PollMilliseconds
                continue
            }
            $status = Read-Status
            if (-not $status.Running) {
                $downPolls++
                $seenPid = ''
                if (-not $didWarm) {
                    Note 'Starting the background service before the session'
                    [void](Invoke-RcCliCall $InvokeCli @('daemon', 'run'))
                    $didWarm = $true
                } elseif ($downPolls -ge $DownPollsBeforeStart) {
                    $settleGaveUp = $true
                    $daemon = $status
                    break
                }
            } elseif (Test-RcDaemonReady $status $cliVersion) {
                $downPolls = 0
                if ($seenPid -and ($seenPid -eq $status.Pid)) {
                    $daemon = $status
                    $settled = $true
                    break
                }
                $seenPid = $status.Pid
            } else {
                $downPolls = 0
                $seenPid = ''
                if (-not $loggedWait) {
                    Note 'Waiting for the background service to finish updating'
                    $loggedWait = $true
                }
            }
            & $Sleep $PollMilliseconds
        }
        if (-not $settled) { $settleGaveUp = $true }
    }

    $polls = 0
    $loggedRetry = $false
    while ($polls -lt $MaxPolls) {
        $polls++
        $stampNow = Stamp
        if ($baseStamp -and $stampNow -and ($stampNow -ne $baseStamp)) {
            Note 'Claude binary changed; waiting for the background service'
            $baseStamp = $stampNow
            $run.Confirm = 0
            $run.ConfirmPid = ''
            $run.Misses = 0
            & $Sleep $PollMilliseconds
            continue
        }
        $daemon = Read-Status
        $ready = Test-RcDaemonReady $daemon $cliVersion
        $live = Read-Live
        $listed = $live.Ok -and (@($live.Sessions).Count -gt 0)
        if ($listed -and $ready) {
            $run.Misses = 0
            if ($run.Confirm -ge 1 -and $run.ConfirmPid -eq "$($daemon.Pid)") {
                $why = $(if ($run.Starts -eq 0) { 'already running' } else { 'started' })
                return (Finish $true $why $live.Sessions)
            }
            $run.Confirm = 1
            $run.ConfirmPid = "$($daemon.Pid)"
        } elseif ($live.Ok -and $ready -and -not $listed) {
            $run.Confirm = 0
            $run.ConfirmPid = ''
            $run.Misses++
            if ($run.Starts -eq 0 -or $run.Misses -ge $ReadyMisses) {
                if ($run.Starts -ge $MaxStarts) { break }
                if ($run.Starts -ge 1 -and -not $loggedRetry) {
                    Note 'Session was not running after start; starting it once more'
                    $loggedRetry = $true
                }
                Start-Once
            }
        } elseif ($run.Starts -eq 0 -and $settleGaveUp -and -not $listed) {
            Start-Once
            $settleGaveUp = $false
        } else {
            $run.Confirm = 0
            $run.ConfirmPid = ''
        }
        if ($polls -ge $MaxPolls) { break }
        & $Sleep $PollMilliseconds
    }
    return (Finish $false "session $SessionName was not running after $($run.Starts) start(s)" @())
}
